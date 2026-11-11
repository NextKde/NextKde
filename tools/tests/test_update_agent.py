"""Run in a VM or hosted CI only; never runs sudo, a build, or an install.

The agent is driven as a subprocess against a throwaway checkout, a local
"remote", and fake sudo/askpass/kosctl scripts placed first on PATH.
"""
import fcntl
import json
import os
from datetime import datetime, timedelta
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

AGENT = Path(__file__).parents[1] / "update/kos-update-agent.py"
STATUS_KEYS = {
    "schemaVersion", "state", "stage", "checkedAt", "startedAt", "finishedAt",
    "sourceRoot", "channel", "branch", "upstream", "dirty", "ahead", "behind",
    "canFastForward", "sourceAhead", "installedVersion", "installedRevision",
    "sourceVersion", "sourceRevision", "logPath", "needsRestart", "error",
}
FAKE_KOSCTL = """#!{python}
import json, os, pathlib, sys
with pathlib.Path(os.environ["FAKE_CALLS"]).open("a") as stream:
    stream.write("args={{}}\\n".format(" ".join(sys.argv[1:])))
    stream.write("askpass={{}}\\n".format(os.environ.get("KOS_SUDO_ASKPASS", "")))
    stream.write("cwd={{}}\\n".format(os.getcwd()))
status = os.environ.get("FAKE_STATUS")
if status:
    data = json.loads(pathlib.Path(status).read_text())
    with pathlib.Path(os.environ["FAKE_CALLS"]).open("a") as stream:
        stream.write("status={{}}/{{}}\\n".format(data["state"], data["stage"]))
record = os.environ.get("FAKE_RECORD")
if record and os.environ.get("FAKE_VERSION"):
    pathlib.Path(record).write_text(json.dumps({{
        "version": os.environ["FAKE_VERSION"],
        "revision": "installed-after-update",
        "tag": "",
        "dirty": False,
        "sourceRoot": os.environ.get("FAKE_SOURCE_ROOT", ""),
    }}))
sys.exit(int(os.environ.get("FAKE_EXIT", "0")))
"""
FAKE_SUDO = """#!{python}
import json, os, pathlib, sys
with pathlib.Path(os.environ["FAKE_SUDO_CALLS"]).open("a") as stream:
    stream.write("{{}}\\n".format(" ".join(sys.argv[1:])))
status = os.environ.get("FAKE_STATUS")
if status:
    data = json.loads(pathlib.Path(status).read_text())
    with pathlib.Path(os.environ["FAKE_SUDO_CALLS"]).open("a") as stream:
        stream.write("status={{}}/{{}}\\n".format(data["state"], data["stage"]))
if os.environ.get("FAKE_SUDO_NOPASSWD") == "1" and "-n" in sys.argv and "true" in sys.argv:
    sys.exit(0)
if "-n" in sys.argv and "true" in sys.argv:
    sys.exit(1)
sys.exit(int(os.environ.get("FAKE_SUDO_EXIT", "0")))
"""


class UpdateAgentTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        base = Path(self.workspace.name)
        self.remote = base / "origin"
        self.root = base / "checkout"
        self.bin = base / "bin"
        self.state_home = base / "state"
        self.home = base / "home"
        self.calls = base / "kosctl-calls.log"
        self.sudo_calls = base / "sudo-calls.log"
        self.record = base / "release.json"
        self.bin.mkdir()
        self.home.mkdir()
        self.remote.mkdir()
        self.fake_kosctl = base / "fake-kosctl"
        self.git(self.remote, "init", "-b", "main")
        self.configure(self.remote)
        (self.remote / "VERSION").write_text("0.1.0\n")
        self.git(self.remote, "add", ".")
        self.git(self.remote, "commit", "-m", "first release")
        subprocess.run(["git", "clone", str(self.remote), str(self.root)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.configure(self.root)
        self.head = self.git(self.root, "rev-parse", "HEAD")
        self.write_script(self.fake_kosctl, FAKE_KOSCTL.format(python=sys.executable))
        self.write_script(self.bin / "sudo", FAKE_SUDO.format(python=sys.executable))
        self.write_script(self.bin / "askpass", "#!/bin/sh\necho secret\n")
        self.write_record("0.1.0", self.head)

    @staticmethod
    def git(root, *args):
        return subprocess.check_output(["git", "-C", str(root), *args],
                                       text=True, stderr=subprocess.DEVNULL).strip()

    def configure(self, root):
        self.git(root, "config", "user.name", "VM Test")
        self.git(root, "config", "user.email", "vm@example.invalid")

    @staticmethod
    def write_script(path, text):
        path.write_text(text)
        path.chmod(0o755)

    def write_record(self, version, revision, source_root=None):
        self.record.write_text(json.dumps({
            "version": version,
            "revision": revision,
            "tag": "",
            "dirty": False,
            "sourceRoot": str(source_root or self.root),
        }))

    def advance(self, count=1):
        for index in range(1, count + 1):
            (self.remote / "VERSION").write_text(f"0.1.{index}\n")
            self.git(self.remote, "commit", "-am", f"commit {index}")
        return self.git(self.remote, "rev-parse", "HEAD")

    def env(self, **overrides):
        environment = {**os.environ}
        for name in ("KOS_SUDO_ASKPASS", "KOS_UPDATE_AGENT_STATE_DIR", "KOS_PREFIX"):
            environment.pop(name, None)
        environment.update({
            "PATH": f"{self.bin}:{os.environ.get('PATH', '/usr/bin:/bin')}",
            "HOME": str(self.home),
            "XDG_STATE_HOME": str(self.state_home),
            "KOS_RELEASE_RECORD": str(self.record),
            "KOS_UPDATE_AGENT_KOSCTL": str(self.fake_kosctl),
            "SUDO_ASKPASS": str(self.bin / "askpass"),
            "FAKE_CALLS": str(self.calls),
            "FAKE_SUDO_CALLS": str(self.sudo_calls),
        })
        environment.update({name: str(value) for name, value in overrides.items()})
        return environment

    def agent(self, *args, **overrides):
        return subprocess.run([sys.executable, str(AGENT), *args],
                              env=self.env(**overrides), text=True,
                              capture_output=True, timeout=120)

    def status_path(self):
        return self.state_home / "kos/update/status.json"

    def read_status(self):
        status = json.loads(self.status_path().read_text())
        self.assertEqual(status["schemaVersion"], 1)
        self.assertEqual(set(status), STATUS_KEYS)
        return status

    def assert_utc(self, value):
        parsed = datetime.fromisoformat(value)
        self.assertIsNotNone(parsed.tzinfo, value)
        self.assertEqual(parsed.utcoffset(), timedelta(0), value)

    def kosctl_calls(self):
        return dict(line.split("=", 1) for line in self.calls.read_text().splitlines())

    def test_check_reports_available(self):
        self.advance(2)
        result = self.agent("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        status = self.read_status()
        self.assertEqual(status["state"], "available")
        self.assertEqual(status["behind"], 2)
        self.assertEqual(status["ahead"], 0)
        self.assertTrue(status["canFastForward"])
        self.assertEqual(status["channel"], "main")
        self.assertEqual(status["branch"], "main")
        self.assertEqual(status["upstream"], "origin/main")
        self.assertFalse(status["dirty"])
        self.assertEqual(status["sourceRevision"], self.head)
        self.assertEqual(status["installedVersion"], "0.1.0")
        self.assertEqual(status["sourceVersion"], "0.1.0")
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), self.head)
        for name in ("startedAt", "checkedAt", "finishedAt"):
            self.assert_utc(status[name])
        directory = self.state_home / "kos/update"
        self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
        for name in ("status.json", "agent.log", "agent.lock"):
            self.assertEqual(stat.S_IMODE((directory / name).stat().st_mode), 0o600, name)

    def test_check_reports_up_to_date(self):
        result = self.agent("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        status = self.read_status()
        self.assertEqual(status["state"], "up-to-date")
        self.assertEqual(status["behind"], 0)
        self.assertEqual(status["stage"], "done")

    def test_local_changes_block_update(self):
        self.advance(1)
        (self.root / "VERSION").write_text("0.1.0\n# personal note\n")
        result = self.agent("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        status = self.read_status()
        self.assertEqual(status["state"], "blocked")
        self.assertTrue(status["dirty"])
        self.assertIn("local changes", status["error"])
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), self.head)

    def test_untracked_file_blocks_update(self):
        self.advance(1)
        (self.root / "personal.qml").write_text("keep this\n")
        result = self.agent("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_status()["state"], "blocked")
        self.assertEqual((self.root / "personal.qml").read_text(), "keep this\n")

    def test_local_commits_do_not_block_a_channel_update(self):
        target = self.advance(1)
        (self.root / "VERSION").write_text("0.1.9\n")
        self.git(self.root, "commit", "-am", "local work")
        mine = self.git(self.root, "rev-parse", "HEAD")
        result = self.agent("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        status = self.read_status()
        self.assertEqual(status["state"], "available")
        self.assertEqual(status["behind"], 1)
        self.assertEqual(status["ahead"], 1)
        result = self.agent("--run", FAKE_RECORD=self.record, FAKE_VERSION="0.1.1",
                            FAKE_SOURCE_ROOT=self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        # The channel is checked out; the old commit stays reachable on its branch.
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), target)
        self.assertEqual(self.git(self.root, "rev-parse", "main"), mine)

    def test_detached_head_checks_and_updates(self):
        self.git(self.root, "checkout", "--detach")
        target = self.advance(1)
        result = self.agent("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        status = self.read_status()
        self.assertEqual(status["state"], "available")
        self.assertEqual(status["branch"], "detached")
        result = self.agent("--run", FAKE_RECORD=self.record, FAKE_VERSION="0.1.1",
                            FAKE_SOURCE_ROOT=self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), target)

    def test_missing_branch_upstream_uses_origin_main(self):
        self.git(self.root, "branch", "--unset-upstream")
        self.advance(1)
        result = self.agent("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        status = self.read_status()
        self.assertEqual(status["state"], "available")
        self.assertEqual(status["upstream"], "origin/main")

    def test_channel_defaults_from_record_tag(self):
        self.record.write_text(json.dumps({
            "version": "0.1.0", "revision": self.head, "tag": "v0.1.0",
            "dirty": False, "sourceRoot": str(self.root),
        }))
        # A tag install follows stable; a local path origin cannot resolve one.
        result = self.agent("--check")
        self.assertEqual(result.returncode, 1)
        status = self.read_status()
        self.assertEqual(status["channel"], "stable")
        self.assertEqual(status["state"], "failed")
        # An explicit channel overrides the record.
        result = self.agent("--check", "--channel", "main")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.read_status()["channel"], "main")

    def test_run_selects_channel_and_installs(self):
        target = self.advance(1)
        result = self.agent("--run", FAKE_RECORD=self.record, FAKE_VERSION="0.1.1",
                            FAKE_SOURCE_ROOT=self.root, FAKE_STATUS=self.status_path())
        self.assertEqual(result.returncode, 0, result.stderr)
        status = self.read_status()
        self.assertEqual(status["state"], "updated")
        self.assertTrue(status["needsRestart"])
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), target)
        self.assertEqual(status["sourceVersion"], "0.1.1")
        self.assertEqual(status["installedVersion"], "0.1.1")
        self.assertEqual(status["installedRevision"], "installed-after-update")
        calls = self.kosctl_calls()
        self.assertEqual(calls["args"], "install")
        self.assertEqual(calls["askpass"], "1")
        self.assertEqual(Path(calls["cwd"]).resolve(), self.root.resolve())
        # Neither the sudo prompt nor the install may be observed as terminal.
        self.assertEqual(calls["status"], "updating/install")
        sudo = self.sudo_calls.read_text()
        self.assertIn("-A -v", sudo)
        self.assertIn("status=updating/auth", sudo)

    def test_nopasswd_update_skips_the_askpass_prompt(self):
        target = self.advance(1)
        result = self.agent("--run", FAKE_SUDO_NOPASSWD="1", FAKE_RECORD=self.record,
                            FAKE_VERSION="0.1.1", FAKE_SOURCE_ROOT=self.root,
                            FAKE_STATUS=self.status_path())
        self.assertEqual(result.returncode, 0, result.stderr)
        status = self.read_status()
        self.assertEqual(status["state"], "updated")
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), target)
        sudo = self.sudo_calls.read_text()
        self.assertIn("-n true", sudo)
        self.assertNotIn("-A -v", sudo)

    def test_source_ahead_offers_reinstall(self):
        # A select that never got installed: the channel has nothing new, HEAD is
        # already the channel commit, only the deployed revision is older.
        self.write_record("0.1.0", "stale-install")
        result = self.agent("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        status = self.read_status()
        self.assertEqual(status["state"], "available")
        self.assertEqual(status["behind"], 0)
        self.assertTrue(status["sourceAhead"])
        self.assertEqual(status["installedRevision"], "stale-install")
        self.assertEqual(status["sourceRevision"], self.head)

        result = self.agent("--run")
        self.assertEqual(result.returncode, 0, result.stderr)
        status = self.read_status()
        self.assertEqual(status["state"], "updated")
        self.assertTrue(status["needsRestart"])
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), self.head)
        self.assertEqual(self.kosctl_calls()["args"], "install")

    def test_authorization_failure_leaves_checkout_and_skips_install(self):
        self.advance(1)
        result = self.agent("--run", FAKE_SUDO_EXIT=1, FAKE_STATUS=self.status_path())
        self.assertEqual(result.returncode, 1)
        status = self.read_status()
        self.assertEqual(status["state"], "failed")
        self.assertIn("authorization", status["error"])
        self.assert_utc(status["startedAt"])
        self.assertIn("status=updating/auth", self.sudo_calls.read_text())
        self.assertEqual(self.git(self.root, "rev-parse", "HEAD"), self.head)
        self.assertFalse(self.calls.exists())

    def test_missing_source_root_is_blocked_with_fresh_start(self):
        self.record.write_text(json.dumps({"version": "0.1.0", "revision": "abc"}))
        result = self.agent("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        status = self.read_status()
        self.assertEqual(status["state"], "blocked")
        self.assertEqual(status["sourceRoot"], "")
        self.assertIn("kosctl install", status["error"])
        self.assert_utc(status["startedAt"])
        self.assert_utc(status["finishedAt"])

    def test_install_failure_is_reported(self):
        self.advance(1)
        result = self.agent("--run", FAKE_EXIT=7)
        self.assertEqual(result.returncode, 2)
        status = self.read_status()
        self.assertEqual(status["state"], "failed")
        self.assertEqual(status["stage"], "install")
        self.assertIn("exit 7", status["error"])

    def test_lock_conflict_exits_three_and_keeps_running_status(self):
        directory = self.state_home / "kos/update"
        directory.mkdir(parents=True)
        running = {
            "schemaVersion": 1, "state": "updating", "stage": "install",
            "startedAt": "2026-01-01T00:00:00+00:00",
        }
        self.status_path().write_text(json.dumps(running))
        before = self.status_path().read_bytes()
        lock = (directory / "agent.lock").open("a")
        self.addCleanup(lock.close)
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = self.agent("--check")
        self.assertEqual(result.returncode, 3)
        self.assertEqual(self.status_path().read_bytes(), before)
        self.assertIn("already running", (directory / "agent.log").read_text())

    def test_root_override_wins_over_release_record(self):
        self.write_record("9.9.9", self.head, source_root=self.home / "missing")
        result = self.agent("--check", "--root", self.root)
        self.assertEqual(result.returncode, 0, result.stderr)
        status = self.read_status()
        self.assertEqual(status["state"], "up-to-date")
        self.assertEqual(status["sourceRoot"], str(self.root.resolve()))


if __name__ == "__main__":
    unittest.main()
