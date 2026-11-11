#!/usr/bin/env python3
"""Check for and apply KOS source updates (Python 3 standard library only).

--check compares the checkout with a release channel and reports; --run selects
that channel, then runs tools/kosctl install. Channels: stable (latest official
GitHub release tag) and main (origin/main, canary). Progress goes to
status.json, child output to agent.log.

Exit codes: 0 done (--run: updated), 1 failed or blocked, 2 install failed,
3 another agent already holds the lock.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import traceback
from datetime import datetime, timezone

SCHEMA_VERSION = 1
CHECK_TIMEOUT = 120
MERGE_TIMEOUT = 120
INSTALL_TIMEOUT = 3600
SUDO_TIMEOUT = 300
KEEPALIVE_SECONDS = 45
TERMINAL_STATES = ("up-to-date", "available", "blocked", "updated", "failed")
GIT_MARKERS = (
    "MERGE_HEAD",
    "CHERRY_PICK_HEAD",
    "REVERT_HEAD",
    "rebase-merge",
    "rebase-apply",
    "sequencer",
)
RECORD_HINT = "Run ./tools/kosctl install once from the checkout so it records the path."
RELEASE_TOOL = Path(__file__).resolve().parents[2] / "tools/release/source-release.py"


def now():
    # Milliseconds: coarse enough for Qt::ISODate, fine enough that a stamp
    # written after launch is never truncated below the controller's launch time.
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def state_dir():
    override = os.environ.get("KOS_UPDATE_AGENT_STATE_DIR")
    if override:
        return Path(override)
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state")
    return Path(base) / "kos/update"


def release_record():
    override = os.environ.get("KOS_RELEASE_RECORD")
    if override:
        return Path(override)
    prefix = os.environ.get("KOS_PREFIX") or str(Path.home() / ".local")
    return Path(prefix) / "share/kos/release.json"


def read_json(path):
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def append_text(path, text):
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.fchmod(fd, 0o600)
        os.write(fd, text.encode())
    finally:
        os.close(fd)


def git(root, *args, timeout=CHECK_TIMEOUT):
    try:
        return subprocess.run(
            ["git", "-C", str(root), *args],
            text=True,
            capture_output=True,
            timeout=timeout,
            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
        )
    except (OSError, subprocess.SubprocessError) as error:
        return subprocess.CompletedProcess(args, 1, "", str(error))


def tail(text, limit=400):
    return " ".join((text or "").split())[-limit:]


def read_version(root):
    try:
        return (Path(root) / "VERSION").read_text().strip()
    except OSError:
        return ""


def read_revision(root):
    result = git(root, "rev-parse", "HEAD")
    return result.stdout.strip() if result.returncode == 0 else ""


def current_branch(root):
    result = git(root, "symbolic-ref", "--short", "HEAD")
    return result.stdout.strip() if result.returncode == 0 else "detached"


def new_status():
    return {
        "schemaVersion": SCHEMA_VERSION,
        "state": "idle",
        "stage": "",
        "checkedAt": "",
        "startedAt": "",
        "finishedAt": "",
        "sourceRoot": "",
        "channel": "",
        "branch": "",
        "upstream": "",
        "dirty": False,
        "ahead": 0,
        "behind": 0,
        "canFastForward": False,
        "sourceAhead": False,
        "installedVersion": "",
        "installedRevision": "",
        "sourceVersion": "",
        "sourceRevision": "",
        "logPath": "",
        "needsRestart": False,
        "error": "",
    }


class Agent:
    def __init__(self, root=None, channel=None):
        self.directory = state_dir()
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.directory, 0o700)
        self.status_path = self.directory / "status.json"
        self.log_path = self.directory / "agent.log"
        self.lock_path = self.directory / "agent.lock"
        self.record_path = release_record()
        record = read_json(self.record_path)
        # A tagged install came from an official release; anything else follows main.
        self.channel = channel or ("stable" if str(record.get("tag") or "").strip() else "main")
        self.status = new_status()
        self.status["logPath"] = str(self.log_path)
        self.status["channel"] = self.channel
        self.status["installedVersion"] = str(record.get("version") or "")
        self.status["installedRevision"] = str(record.get("revision") or "")
        source = root or record.get("sourceRoot") or ""
        self.root = Path(str(source)).expanduser().resolve() if source else None
        self.kosctl = None
        if self.root:
            self.status["sourceRoot"] = str(self.root)
            self.status["sourceVersion"] = read_version(self.root)
            self.status["sourceRevision"] = read_revision(self.root)
            self.kosctl = Path(
                os.environ.get("KOS_UPDATE_AGENT_KOSCTL") or self.root / "tools/kosctl"
            )

    def log(self, message):
        append_text(self.log_path, f"[{now()}] {message}\n")

    def write(self):
        payload = json.dumps(self.status, indent=2) + "\n"
        fd, temporary = tempfile.mkstemp(prefix=".status-", dir=self.directory)
        try:
            with os.fdopen(fd, "w") as stream:
                os.fchmod(stream.fileno(), 0o600)
                stream.write(payload)
            os.replace(temporary, self.status_path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def set_state(self, state, stage=None, error=None, **fields):
        if stage is not None:
            self.status["stage"] = stage
        elif state in TERMINAL_STATES:
            self.status["stage"] = "done"
        if error is not None:
            self.status["error"] = error
        self.status["state"] = state
        self.status.update(fields)
        if state in TERMINAL_STATES:
            self.status["finishedAt"] = now()
        self.write()
        line = f"state={state} stage={self.status['stage']}"
        if self.status["error"]:
            line += f" error={self.status['error']}"
        self.log(line)

    def finish(self, state, **fields):
        self.status["checkedAt"] = now()
        self.set_state(state, **fields)

    def block(self, message):
        self.finish("blocked", error=message)
        return "blocked"

    def check(self):
        self.status["startedAt"] = now()
        self.status["error"] = ""
        self.status["dirty"] = False
        self.status["upstream"] = ""
        self.status["channel"] = self.channel
        # The constructor snapshot goes stale when another agent installs.
        record = read_json(self.record_path)
        if record.get("version"):
            self.status["installedVersion"] = str(record["version"])
        if record.get("revision"):
            self.status["installedRevision"] = str(record["revision"])
        self.set_state("checking")
        if not record.get("version") or not record.get("revision"):
            return self.block(
                "The install record is missing or incomplete; run ./tools/kosctl install once."
            )
        root = self.root
        if root is None:
            return self.block(f"No source checkout is recorded. {RECORD_HINT}")
        if not root.is_dir():
            return self.block(f"Recorded source checkout does not exist: {root}. {RECORD_HINT}")
        top = git(root, "rev-parse", "--show-toplevel")
        if top.returncode != 0:
            return self.block(f"Not a Git checkout: {root}. {RECORD_HINT}")
        if Path(top.stdout.strip()).resolve() != root:
            return self.block(
                f"Source path is not the root of a Git checkout: {root}. {RECORD_HINT}"
            )
        if git(root, "status", "--porcelain", "--untracked-files=normal").stdout.strip():
            self.status["dirty"] = True
            return self.block(
                "Working tree has local changes or untracked files; save them first."
            )
        for marker in GIT_MARKERS:
            location = git(root, "rev-parse", "--git-path", marker)
            if location.returncode != 0:
                continue
            path = Path(location.stdout.strip())
            if not path.is_absolute():
                path = root / path
            if path.exists():
                return self.block("Finish the in-progress Git operation first.")
        self.status["branch"] = current_branch(root)
        self.set_state("checking", "fetch")
        try:
            result = subprocess.run(
                [sys.executable, str(RELEASE_TOOL), "--root", str(root), "check", self.channel],
                text=True,
                capture_output=True,
                timeout=CHECK_TIMEOUT,
                env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
            )
        except (OSError, subprocess.SubprocessError) as error:
            self.finish("failed", stage="fetch", error=f"Cannot check for updates: {error}")
            return "failed"
        if result.returncode != 0:
            self.finish(
                "failed",
                stage="fetch",
                error="Update check failed: " + tail(result.stderr or result.stdout),
            )
            return "failed"
        try:
            info = json.loads(result.stdout)
            behind, ahead = int(info["behind"]), int(info["ahead"])
        except (KeyError, TypeError, ValueError):
            self.finish("failed", stage="fetch", error="Update check returned no revision.")
            return "failed"
        revision = read_revision(root)
        # The checkout can already match the channel while the deployed files are
        # older: an install did not finish. Offer the install again.
        source_ahead = bool(self.status["installedRevision"]) and (
            self.status["installedRevision"] != revision
        )
        self.status.update(
            channel=str(info.get("channel") or self.channel),
            upstream=str(info.get("target") or ""),
            behind=behind,
            ahead=ahead,
            canFastForward=ahead == 0,
            sourceAhead=source_ahead,
            sourceVersion=read_version(root),
            sourceRevision=revision,
        )
        if behind == 0 and not source_ahead:
            self.finish("up-to-date")
            return "up-to-date"
        self.finish("available")
        return "available"

    def askpass(self):
        candidate = os.environ.get("SUDO_ASKPASS", "")
        if candidate and os.access(candidate, os.X_OK):
            return candidate
        found = shutil.which("ksshaskpass")
        if found:
            os.environ["SUDO_ASKPASS"] = found
            return found
        # A standard Plasma install ships kdialog even without ksshaskpass.
        helper = Path(__file__).with_name("kos-askpass.sh")
        if shutil.which("kdialog") and helper.is_file() and os.access(helper, os.X_OK):
            os.environ["SUDO_ASKPASS"] = str(helper)
            return str(helper)
        return ""

    def sudo_without_password(self):
        # NOPASSWD installs need no prompt, and `sudo -v` still asks even when
        # every command is NOPASSWD. Probe with a no-op command instead.
        try:
            result = subprocess.run(
                ["sudo", "-n", "true"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=SUDO_TIMEOUT,
            )
        except (OSError, subprocess.SubprocessError):
            return False
        return result.returncode == 0

    def authorize(self):
        try:
            result = subprocess.run(
                ["sudo", "-A", "-v"],
                env={**os.environ, "LC_ALL": "C"},
                text=True,
                capture_output=True,
                timeout=SUDO_TIMEOUT,
            )
        except (OSError, subprocess.SubprocessError) as error:
            self.log(f"sudo authorization could not run: {error}")
            return False
        if result.returncode != 0:
            self.log("sudo authorization failed: " + tail(result.stderr or result.stdout))
            return False
        return True

    def keepalive(self, stop):
        while not stop.wait(KEEPALIVE_SECONDS):
            try:
                result = subprocess.run(
                    ["sudo", "-n", "true"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=SUDO_TIMEOUT,
                )
            except (OSError, subprocess.SubprocessError):
                return
            if result.returncode:
                self.log("sudo timestamp refresh failed; kosctl may ask again.")
                return

    def install(self):
        stop = threading.Event()
        keepalive = threading.Thread(target=self.keepalive, args=(stop,), daemon=True)
        keepalive.start()
        self.log("--- kosctl install ---")
        code = None
        try:
            fd = os.open(str(self.log_path), os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "ab") as stream:
                process = subprocess.Popen(
                    [str(self.kosctl), "install"],
                    cwd=str(self.root),
                    env={**os.environ, "KOS_SUDO_ASKPASS": "1"},
                    stdin=subprocess.DEVNULL,
                    stdout=stream,
                    stderr=subprocess.STDOUT,
                )
                try:
                    code = process.wait(timeout=INSTALL_TIMEOUT)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        except OSError as error:
            self.set_state("failed", "install", error=f"Cannot run {self.kosctl}: {error}")
            return 2
        finally:
            stop.set()
            keepalive.join(timeout=1)
        if code is None:
            self.set_state(
                "failed", "install", error=f"kosctl install timed out after {INSTALL_TIMEOUT}s."
            )
            return 2
        if code != 0:
            self.set_state(
                "failed", "install", error=f"kosctl install failed (exit {code}); see the log."
            )
            return 2
        return 0

    def select(self):
        self.log(f"--- source-release.py select {self.channel} ---")
        try:
            result = subprocess.run(
                [sys.executable, str(RELEASE_TOOL), "--root", str(self.root), "select", self.channel],
                text=True,
                capture_output=True,
                timeout=MERGE_TIMEOUT,
                env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
            )
        except (OSError, subprocess.SubprocessError) as error:
            self.set_state("failed", "merge", error=f"Cannot select {self.channel}: {error}")
            return 1
        if result.returncode != 0:
            self.set_state(
                "failed",
                "merge",
                error=f"Selecting the {self.channel} channel failed: "
                + tail(result.stderr or result.stdout),
            )
            return 1
        return 0

    def run(self):
        state = self.check()
        if state != "available":
            self.log(f"not updating: {state}")
            return 1
        # Leave the terminal "available" behind immediately: the sudo prompt can
        # wait for the user while the controller is still watching.
        self.set_state("updating", "auth")
        if not self.sudo_without_password():
            askpass = self.askpass()
            if not askpass:
                self.set_state(
                    "failed",
                    error="A graphical sudo prompt is required: install ksshaskpass or kdialog, or set SUDO_ASKPASS.",
                )
                return 1
            # Authorize before touching the checkout: a cancelled prompt leaves it intact.
            if not self.authorize():
                self.set_state(
                    "failed", error="sudo authorization failed; the source checkout is unchanged."
                )
                return 1
        self.set_state("updating", "merge")
        code = self.select()
        if code != 0:
            return code
        self.status["branch"] = current_branch(self.root)
        self.status["sourceVersion"] = read_version(self.root)
        self.status["sourceRevision"] = read_revision(self.root)
        self.set_state("updating", "install")
        code = self.install()
        if code != 0:
            return code
        record = read_json(self.record_path)
        if record.get("version"):
            self.status["installedVersion"] = str(record["version"])
        if record.get("revision"):
            self.status["installedRevision"] = str(record["revision"])
        self.status["sourceVersion"] = read_version(self.root)
        self.status["sourceRevision"] = read_revision(self.root)
        self.status["sourceAhead"] = bool(self.status["installedRevision"]) and (
            self.status["installedRevision"] != self.status["sourceRevision"]
        )
        self.set_state("updated", needsRestart=True)
        return 0

    def crash(self):
        self.log(traceback.format_exc())
        try:
            self.set_state("failed", error="The update agent crashed; see the log.")
        except OSError:
            pass


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--check", action="store_true", help="fetch and report only")
    action.add_argument("--run", action="store_true", help="select the channel and install")
    parser.add_argument("--root", help="source checkout override")
    parser.add_argument("--channel", choices=("stable", "main"), help="release channel to follow")
    args = parser.parse_args(argv)
    try:
        os.setsid()  # keep running when the Settings window that started us closes
    except OSError:
        pass
    agent = Agent(args.root, args.channel)
    lock = os.open(str(agent.lock_path), os.O_RDWR | os.O_CREAT, 0o600)
    os.fchmod(lock, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        agent.log("another update agent is already running; not starting")
        os.close(lock)
        return 3
    try:
        if args.run:
            return agent.run()
        return 1 if agent.check() == "failed" else 0
    except Exception:
        agent.crash()
        return 1


if __name__ == "__main__":
    sys.exit(main())
