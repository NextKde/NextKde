#!/usr/bin/env python3
"""Allowlisted, per-user source installer. Python 3 standard library only.

The publication trust boundary is the fixed NextKde GitHub repository, not a
signature. This program is shipped with its consumer, never downloaded as code.
"""
import argparse
import contextlib
import fcntl
import hashlib
import http.client
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import signal
import socket
import ssl
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

APPS = {
    "calendar": ("kos-apps", "org.nextks.calendar", ("kos-calendar",)),
    "calculator": ("kos-apps", "org.nextks.calculator", ("kos-calculator",)),
    "weather": ("kos-apps", "org.nextks.weather", ("kos-weather",)),
    "listenfree": ("ListenFree", "org.nextkde.ListenFree", ("listenfree",)),
}
SEMVER = re.compile(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\Z")
REVISION = re.compile(r"[0-9a-f]{40}\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
OWNER = "nextkde-source-installer-v1"
MAX_JSON = 256 * 1024
MAX_ARCHIVE = 256 * 1024 * 1024
MAX_EXTRACTED = 1024 * 1024 * 1024
NETWORK_TIMEOUT = 15
CHILD_TIMEOUT = 1800


class Failure(Exception):
    def __init__(self, code, message, **details):
        super().__init__(message)
        self.code, self.details = code, {"message": message, **details}


def fail(code, message, **details):
    raise Failure(code, message, **details)


def present(path):
    return path.exists() or path.is_symlink()


def regular(path):
    return path.is_file() and not path.is_symlink()


def secure_dir(path):
    """Never follow an attacker/user supplied symlink in managed storage."""
    if not path.is_absolute() or ".." in path.parts:
        fail("UNSAFE_PATH", "Storage paths must be absolute and canonical", path=str(path))
    for part in reversed((path, *path.parents)):
        if part.is_symlink():
            fail("UNSAFE_PATH", "Storage directory is a symlink", path=str(part))
        if present(part) and not part.is_dir():
            fail("UNSAFE_PATH", "Storage directory is not a directory", path=str(part))
    path.mkdir(parents=True, exist_ok=True, mode=0o700)


def read_json(path):
    if not regular(path) or path.stat().st_size > MAX_JSON:
        fail("CORRUPT_STATE", "Missing or unsafe ownership metadata", path=str(path))
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, UnicodeError) as exc:
        fail("CORRUPT_STATE", "Invalid ownership metadata", error=str(exc))


def write_json(path, value):
    if present(path) and not regular(path):
        fail("UNSAFE_PATH", "Metadata target is not a regular file", path=str(path))
    fd, temporary = tempfile.mkstemp(prefix=".metadata-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(value, stream, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


@contextlib.contextmanager
def network_deadline(seconds):
    """Unix main-thread wall deadline also interrupts DNS/headers/redirects."""
    previous = signal.getsignal(signal.SIGALRM)
    started = time.monotonic()
    def expired(signum, frame):
        raise TimeoutError("Absolute network deadline exceeded")
    signal.signal(signal.SIGALRM, expired)
    old_timer = signal.getitimer(signal.ITIMER_REAL)
    signal.setitimer(signal.ITIMER_REAL, min(seconds, old_timer[0]) if old_timer[0] else seconds)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)
        if old_timer[0]:
            signal.setitimer(signal.ITIMER_REAL, max(0.001, old_timer[0] - (time.monotonic() - started)), old_timer[1])


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def __init__(self, client):
        super().__init__()
        self.client = client

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        self.client.validate_url(newurl, redirected=True)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class GitHubClient:
    """Tests inject a client subclass; production accepts no endpoint overrides."""
    def __init__(self, repo):
        self.repo = repo
        self.opener = urllib.request.build_opener(SafeRedirect(self))

    def validate_url(self, url, redirected=False):
        value = urllib.parse.urlsplit(url)
        if value.scheme != "https" or value.username or value.password or value.port not in (None, 443):
            fail("UNTRUSTED_URL", "Only allowlisted GitHub HTTPS URLs are accepted")
        host, path = value.hostname, value.path
        allowed = (
            host == "api.github.com" and path.startswith(f"/repos/NextKde/{self.repo}/")
            or host == "github.com" and path.startswith(f"/NextKde/{self.repo}/")
            or host == "codeload.github.com" and path.startswith(f"/NextKde/{self.repo}/")
            or redirected and host in ("release-assets.githubusercontent.com", "objects.githubusercontent.com")
        )
        if not allowed or value.fragment:
            fail("UNTRUSTED_URL", "URL is outside the fixed app repository")

    def fetch(self, url, destination=None, limit=MAX_JSON):
        self.validate_url(url)
        for attempt in range(3):
            deadline = time.monotonic() + (300 if destination else 45)
            try:
                request = urllib.request.Request(url, headers={
                    "User-Agent": "NextKde-AppInstaller/1", "Accept": "application/vnd.github+json"})
                with network_deadline(300 if destination else 45), self.opener.open(request, timeout=NETWORK_TIMEOUT) as response:
                    self.validate_url(response.url, redirected=response.url != url)
                    length = response.headers.get("Content-Length")
                    if length and (not length.isdecimal() or int(length) > limit):
                        fail("RESPONSE_TOO_LARGE", "Invalid or excessive Content-Length", limit=limit)
                    chunks, total = [], 0
                    with open(destination, "wb") if destination else contextlib.nullcontext(None) as output:
                        while True:
                            if time.monotonic() >= deadline:
                                raise TimeoutError("Absolute download deadline exceeded")
                            # read1 returns after one socket read rather than
                            # waiting for a full buffer from a slow-drip peer.
                            reader = getattr(response, "read1", response.read)
                            chunk = reader(min(65536, limit + 1 - total))
                            if time.monotonic() >= deadline:
                                raise TimeoutError("Absolute download deadline exceeded")
                            if not chunk:
                                break
                            total += len(chunk)
                            if total > limit:
                                fail("RESPONSE_TOO_LARGE", "Download exceeds size limit", limit=limit)
                            if output:
                                output.write(chunk)
                            else:
                                chunks.append(chunk)
                    if length and total != int(length):
                        raise http.client.IncompleteRead(b"", int(length) - total)
                    return b"".join(chunks) if not destination else None
            except urllib.error.HTTPError as exc:
                exc.close()
                if exc.code == 404:
                    fail("RELEASE_UNAVAILABLE", "No published stable release or release artifact")
                if exc.code == 429 or exc.code == 403 and exc.headers.get("X-RateLimit-Remaining") == "0":
                    fail("RATE_LIMITED", "GitHub rate limit reached; retry later",
                         retryAfter=exc.headers.get("Retry-After"), rateLimitReset=exc.headers.get("X-RateLimit-Reset"))
                if exc.code not in (408, 500, 502, 503, 504) or attempt == 2:
                    fail("NETWORK_ERROR", "GitHub HTTP request failed", httpStatus=exc.code)
            except (ssl.SSLError, ssl.CertificateError) as exc:
                fail("TLS_ERROR", "TLS validation failed", error=str(exc))
            except urllib.error.URLError as exc:
                if isinstance(exc.reason, (ssl.SSLError, ssl.CertificateError)):
                    fail("TLS_ERROR", "TLS validation failed", error=str(exc.reason))
                if attempt == 2:
                    fail("NETWORK_TIMEOUT" if isinstance(exc.reason, TimeoutError) else "NETWORK_ERROR",
                         "Cannot reach GitHub", error=str(exc.reason))
            except (TimeoutError, socket.timeout) as exc:
                if attempt == 2:
                    fail("NETWORK_TIMEOUT", "GitHub download deadline exceeded", error=str(exc))
            except (ConnectionError, http.client.IncompleteRead, http.client.RemoteDisconnected) as exc:
                if attempt == 2:
                    fail("NETWORK_ERROR", "GitHub response was disconnected or truncated", error=str(exc))
            time.sleep(0.25 * (attempt + 1))

    def json(self, url):
        try:
            result = json.loads(self.fetch(url))
        except (ValueError, UnicodeError) as exc:
            fail("INVALID_RELEASE", "Release JSON is invalid", error=str(exc))
        if not isinstance(result, dict):
            fail("INVALID_RELEASE", "Release JSON must be an object")
        return result

    def release(self, app_id, requested=None):
        release = self.json(f"https://api.github.com/repos/NextKde/{self.repo}/releases/latest")
        if release.get("draft") is not False or release.get("prerelease") is not False:
            fail("INVALID_RELEASE", "Only a published stable release is accepted")
        assets = release.get("assets")
        if not isinstance(assets, list):
            fail("INVALID_RELEASE", "Release assets are missing")
        manifest_name = app_id + ".app-release.json" if self.repo == "kos-apps" else "app-release.json"
        matches = [a for a in assets if isinstance(a, dict) and a.get("name") == manifest_name]
        if len(matches) != 1:
            fail("RELEASE_UNAVAILABLE", "Release must publish exactly one matching application source manifest")
        url = matches[0].get("browser_download_url", "")
        expected_prefix = f"https://github.com/NextKde/{self.repo}/releases/download/"
        if not isinstance(url, str) or not url.startswith(expected_prefix) or not url.endswith("/" + manifest_name):
            fail("UNTRUSTED_URL", "Manifest is not a repository release asset")
        manifest = self.json(url)
        version, revision, checksum = (manifest.get(k) for k in ("version", "revision", "archiveSha256"))
        if (type(manifest.get("schemaVersion")) is not int or manifest["schemaVersion"] != 1
                or manifest.get("appId") != app_id or not isinstance(version, str) or not SEMVER.fullmatch(version)
                or not isinstance(revision, str) or not REVISION.fullmatch(revision)
                or not isinstance(checksum, str) or not SHA256.fullmatch(checksum)
                or release.get("tag_name") != "v" + version):
            fail("INVALID_RELEASE", "Release identity, version, tag, revision or SHA256 is invalid")
        if requested is not None and requested != version:
            fail("VERSION_MISMATCH", "Requested version does not match the latest stable release", requested=requested, discovered=version)
        archive = f"https://codeload.github.com/NextKde/{self.repo}/tar.gz/{revision}"
        supplied = manifest.get("archiveUrl", archive)
        if supplied != archive:
            fail("UNTRUSTED_URL", "Archive must be the fixed repository revision codeload URL")
        return {"schemaVersion": 1, "appId": app_id, "version": version, "revision": revision,
                "archiveSha256": checksum, "archiveUrl": archive}


def extract_archive(archive, target):
    try:
        with tarfile.open(archive, "r:gz") as source:
            members = source.getmembers()
            if len(members) > 100000 or sum(m.size for m in members) > MAX_EXTRACTED:
                fail("UNSAFE_ARCHIVE", "Source archive exceeds extraction limits")
            roots = set()
            for member in members:
                name = PurePosixPath(member.name)
                if (name.is_absolute() or ".." in name.parts or "\\" in member.name
                        or not name.parts or not (member.isdir() or member.isfile())
                        or member.issym() or member.islnk()):
                    fail("UNSAFE_ARCHIVE", "Source archive contains an unsafe entry", entry=member.name)
                roots.add(name.parts[0])
            if len(roots) != 1:
                fail("UNSAFE_ARCHIVE", "Source archive must have one top-level directory")
            # Validate the complete archive before creating any entry. No links,
            # devices or archive permissions are trusted.
            seen = set()
            for member in members:
                path = target.joinpath(*PurePosixPath(member.name).parts)
                if path in seen:
                    fail("UNSAFE_ARCHIVE", "Source archive contains duplicate paths")
                seen.add(path)
                if member.isdir():
                    path.mkdir(parents=True, exist_ok=True, mode=0o700)
                else:
                    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                    with source.extractfile(member) as content, path.open("xb") as output:
                        shutil.copyfileobj(content, output)
                    path.chmod(0o700 if member.mode & 0o111 else 0o600)
            root = target / roots.pop()
            if not regular(root / "CMakeLists.txt"):
                fail("INVALID_SOURCE", "Source archive has no root CMakeLists.txt")
            return root
    except (tarfile.TarError, EOFError, OSError) as exc:
        fail("UNSAFE_ARCHIVE", "Cannot safely unpack source archive", error=str(exc))


class Installer:
    def __init__(self, key, action, requested=None, client=None, emit=None, confirmed=False, expected_plan=None):
        self.key, self.action, self.requested = key, action, requested
        self.confirmed, self.expected_plan = confirmed, expected_plan
        self.repo, self.app_id, self.executables = APPS[key]
        home = Path.home()
        self.data = Path(os.environ.get("XDG_DATA_HOME", str(home / ".local/share")))
        namespace = self.app_id if self.repo == "kos-apps" else key
        self.state = Path(os.environ.get("XDG_STATE_HOME", str(home / ".local/state"))) / "nextkde-apps" / namespace
        self.root = self.data / "nextkde-apps" / namespace
        self.bin = home / ".local/bin"
        self.current = self.root / "current"
        self.metadata = self.root / "ownership.json"
        self.client = client or GitHubClient(self.repo)
        self.emit = emit or (lambda value: print(json.dumps(value, sort_keys=True), flush=True))
        self.release = None
        self.log = None
        self.installed_info = None

    def event(self, kind, code, success=True, stage=None, **details):
        self.emit({"schemaVersion": 1, "appId": self.app_id, "action": self.action,
                   "stage": stage or self.action, "type": kind, "success": success,
                   "code": code, "version": self.release.get("version") if self.release else None,
                   "revision": self.release.get("revision") if self.release else None, "details": details})

    @contextlib.contextmanager
    def lock(self):
        if self.action == "cleanup-plan":
            for part in (self.state, *self.state.parents):
                if part.is_symlink():
                    fail("UNSAFE_PATH", "Storage directory is a symlink", path=str(part))
            if not present(self.state / "lock"):
                yield
                return
            fd = os.open(self.state / "lock", os.O_RDONLY | os.O_NOFOLLOW)
        else:
            secure_dir(self.state)
            fd = os.open(self.state / "lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                fail("BUSY", "Another operation is running for this app")
            yield
        finally:
            os.close(fd)

    @property
    def journal(self):
        return self.state / "transaction.json"

    def validate_journal_info(self, info):
        if info is None:
            return
        if (not isinstance(info, dict) or info.get("managedBy") != OWNER or info.get("appId") != self.app_id
                or not isinstance(info.get("version"), str) or not SEMVER.fullmatch(info["version"])
                or not isinstance(info.get("revision"), str) or not REVISION.fullmatch(info["revision"])
                or not isinstance(info.get("versions"), list) or not isinstance(info.get("links"), dict)
                or any(not isinstance(r, str) or not REVISION.fullmatch(r) for r in info["versions"])
                or info["revision"] not in info["versions"]):
            fail("CORRUPT_STATE", "Transaction ownership metadata is invalid")
        base = self.expected_links(self.root / "nonexistent")
        for path, target in info["links"].items():
            if not isinstance(path, str) or not isinstance(target, str):
                fail("CORRUPT_STATE", "Transaction link is invalid")
            service = Path(path)
            valid_service = (service.parent == self.data / "dbus-1/services" and service.suffix == ".service"
                             and service.name not in (".service", "..service")
                             and target == str(self.current / "share/dbus-1/services" / service.name))
            if base.get(path) != target and not valid_service:
                fail("CORRUPT_STATE", "Transaction contains an unowned activation path")
        if not set(base).issubset(info["links"]):
            fail("CORRUPT_STATE", "Transaction omits required activation paths")

    def checked_unlink(self, path, target):
        path = Path(path)
        if not present(path):
            return
        if not path.is_symlink() or os.readlink(path) != target:
            fail("CORRUPT_STATE", "Transaction activation was replaced; refusing removal", path=str(path))
        secure_dir(path.parent)
        path.unlink()

    def set_current(self, info):
        if info is None:
            if present(self.current):
                if not self.current.is_symlink():
                    fail("CORRUPT_STATE", "Current activation was replaced")
                self.current.unlink()
            return
        target = self.root / "versions" / info["revision"]
        if target.is_symlink() or not target.is_dir():
            fail("CORRUPT_STATE", "Transaction version is unavailable")
        temporary = self.root / ".current-new"
        if present(temporary):
            if not temporary.is_symlink() or os.readlink(temporary) != str(target):
                fail("CORRUPT_STATE", "Transaction publication staging path was replaced")
            temporary.unlink()
        temporary.symlink_to(target)
        os.replace(temporary, self.current)
        root_fd = os.open(self.root, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(root_fd)
        finally:
            os.close(root_fd)

    def cleanup_plan(self, info):
        revisions = list(dict.fromkeys((info or {}).get("versions", [])))
        current = (info or {}).get("revision")
        previous = next((r for r in reversed(revisions) if r != current), None)
        keep = [r for r in revisions if r in (current, previous)]
        remove = [r for r in revisions if r not in keep]
        total = 0
        def inaccessible(error):
            raise error
        for revision in remove:
            directory = self.root / "versions" / revision
            if directory.lstat().st_uid != os.getuid():
                fail("UNSAFE_PATH", "Old version is not owned by this user", path=str(directory))
            for parent, directories, files in os.walk(directory, followlinks=False, onerror=inaccessible):
                for name in directories + files:
                    item = Path(parent) / name
                    metadata = item.lstat()
                    if metadata.st_uid != os.getuid() or not (stat.S_ISDIR(metadata.st_mode)
                            or stat.S_ISREG(metadata.st_mode) or stat.S_ISLNK(metadata.st_mode)):
                        fail("UNSAFE_PATH", "Owned version contains an unsafe object", path=str(item))
                    if stat.S_ISREG(metadata.st_mode):
                        total += metadata.st_size
        return {**self.status_details(info), "keptRevisions": keep, "removedRevisions": remove,
                "reclaimableBytes": total, "personalDataPreserved": True,
                "planToken": hashlib.sha256(json.dumps(info, sort_keys=True).encode()).hexdigest()}

    def recover_prune(self, transaction):
        old, new = transaction.get("old"), transaction.get("new")
        self.validate_journal_info(old)
        self.validate_journal_info(new)
        if not old or not new or transaction.get("candidate") is not None:
            fail("CORRUPT_STATE", "Prune journal is invalid")
        removed = transaction.get("removed")
        revisions = list(dict.fromkeys(old["versions"]))
        previous = next((r for r in reversed(revisions) if r != old["revision"]), None)
        keep = [r for r in revisions if r in (old["revision"], previous)]
        expected = {**old, "versions": keep}
        if (new != expected or removed != [r for r in revisions if r not in keep]
                or read_json(self.metadata) not in (old, new)):
            fail("CORRUPT_STATE", "Prune journal changes unowned state")
        if not self.current.is_symlink() or os.readlink(self.current) != str(self.root / "versions" / old["revision"]):
            fail("CORRUPT_STATE", "Current activation changed during cleanup")
        for path, target in old["links"].items():
            if not Path(path).is_symlink() or os.readlink(path) != target:
                fail("CORRUPT_STATE", "Activation changed during cleanup", path=path)
            if any(parent.is_symlink() for parent in Path(path).parents):
                fail("UNSAFE_PATH", "Activation parent changed during cleanup", path=path)
        # Commit the reduced inventory before deleting anything. The durable journal
        # retains ownership of removed directories until all deletions are fsynced.
        for directory in (self.root, self.root / "versions"):
            secure_dir(directory)
            if directory.stat().st_uid != os.getuid():
                fail("UNSAFE_PATH", "Version storage is not owned by this user")
        for revision in keep:
            path = self.root / "versions" / revision
            if path.is_symlink() or not path.is_dir():
                fail("CORRUPT_STATE", "Retained version is unavailable")
        write_json(self.metadata, new)
        fd = os.open(self.root / "versions", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            for revision in removed:
                try:
                    metadata = os.stat(revision, dir_fd=fd, follow_symlinks=False)
                except FileNotFoundError:
                    continue
                if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid():
                    fail("UNSAFE_PATH", "Prune version was replaced")
                if not shutil.rmtree.avoids_symlink_attacks:
                    fail("UNSAFE_PATH", "This platform cannot safely remove version directories")
                shutil.rmtree(revision, dir_fd=fd)
                os.fsync(fd)
        finally:
            os.close(fd)
        self.journal.unlink()
        fd = os.open(self.state, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)

    def recover(self):
        """Idempotent redo/undo under the app lock; never infer ownership."""
        if not present(self.journal):
            return
        transaction = read_json(self.journal)
        if isinstance(transaction, dict) and transaction.get("schemaVersion") == 1 and transaction.get("kind") == "prune":
            self.recover_prune(transaction)
            return
        if not isinstance(transaction, dict) or transaction.get("schemaVersion") != 1 or transaction.get("kind") not in ("install", "uninstall"):
            fail("CORRUPT_STATE", "Transaction journal is invalid")
        old, new = transaction.get("old"), transaction.get("new")
        self.validate_journal_info(old)
        self.validate_journal_info(new)
        candidate = transaction.get("candidate")
        if transaction["kind"] == "install" and (not isinstance(candidate, str) or not REVISION.fullmatch(candidate)
                or old and candidate in old["versions"]):
            fail("CORRUPT_STATE", "Transaction candidate is invalid")
        for directory in (self.root, self.root / "versions"):
            if directory.is_symlink():
                fail("CORRUPT_STATE", "Transaction storage was replaced")
        for item in (old, new):
            for revision in (item or {}).get("versions", []):
                if (self.root / "versions" / revision).is_symlink():
                    fail("CORRUPT_STATE", "Transaction version was replaced")
        for item in (old, new):
            for path, target in (item or {}).get("links", {}).items():
                link = Path(path)
                if present(link) and (not link.is_symlink() or os.readlink(link) != target):
                    fail("CORRUPT_STATE", "Transaction activation was replaced", path=path)
                for parent in link.parents:
                    if parent.is_symlink():
                        fail("CORRUPT_STATE", "Transaction activation parent was replaced", path=str(parent))
        if new and (new["revision"] != candidate or set(new["versions"]) != set((old or {}).get("versions", []) + [candidate])):
            fail("CORRUPT_STATE", "Transaction version inventory is invalid")
        allowed_current = {str(self.root / "versions" / item["revision"]) for item in (old, new) if item}
        if present(self.current) and (not self.current.is_symlink() or os.readlink(self.current) not in allowed_current):
            fail("CORRUPT_STATE", "Transaction current activation was replaced")
        if present(self.metadata) and read_json(self.metadata) not in (old, new):
            fail("CORRUPT_STATE", "Transaction ownership metadata was replaced")
        temporary = self.root / ".current-new"
        if present(temporary):
            if not temporary.is_symlink() or os.readlink(temporary) not in allowed_current:
                fail("CORRUPT_STATE", "Transaction staging link was replaced")
            temporary.unlink()
        # A committed metadata replacement is the publication commit point.
        committed = bool(new and present(self.metadata) and read_json(self.metadata) == new)
        if transaction["kind"] == "uninstall":
            if not old or new is not None or candidate is not None:
                fail("CORRUPT_STATE", "Uninstall journal is invalid")
            for path, target in old["links"].items():
                self.checked_unlink(path, target)
            self.set_current(None)
            for revision in old["versions"]:
                directory = self.root / "versions" / revision
                if directory.is_symlink():
                    fail("CORRUPT_STATE", "Owned version was replaced")
                if directory.is_dir():
                    shutil.rmtree(directory)
            if present(self.metadata):
                if read_json(self.metadata) != old:
                    fail("CORRUPT_STATE", "Uninstall ownership metadata was replaced")
                self.metadata.unlink()
        elif committed:
            self.set_current(new)
            for path, target in new["links"].items():
                secure_dir(Path(path).parent)
                if not present(Path(path)):
                    Path(path).symlink_to(target)
                elif not Path(path).is_symlink() or os.readlink(path) != target:
                    fail("CORRUPT_STATE", "Committed activation was replaced")
            for path, target in (old or {}).get("links", {}).items():
                if path not in new["links"]:
                    self.checked_unlink(path, target)
        else:
            # Restore old publication before deleting an unpublished candidate.
            for path, target in (new or {}).get("links", {}).items():
                if path not in (old or {}).get("links", {}):
                    self.checked_unlink(path, target)
            if present(self.root):
                self.set_current(old)
                if old:
                    write_json(self.metadata, old)
                elif present(self.metadata):
                    fail("CORRUPT_STATE", "Unexpected ownership metadata during rollback")
                directory = self.root / "versions" / candidate
                if directory.is_symlink():
                    fail("CORRUPT_STATE", "Transaction candidate was replaced")
                if directory.is_dir():
                    shutil.rmtree(directory)
        # Directory persistence precedes removing the recovery record.
        for item in (old, new):
            for path in (item or {}).get("links", {}):
                parent = Path(path).parent
                if parent.is_dir():
                    fd = os.open(parent, os.O_RDONLY | os.O_DIRECTORY)
                    try:
                        os.fsync(fd)
                    finally:
                        os.close(fd)
        for directory in (self.root / "versions", self.root):
            if directory.is_dir():
                fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
                try:
                    os.fsync(fd)
                finally:
                    os.close(fd)
        # Remove only known empty containers, never unrelated contents.
        temporary = self.root / ".current-new"
        if present(temporary):
            allowed = {str(self.root / "versions" / r) for r in [candidate, *((old or {}).get("versions", []))] if r}
            if not temporary.is_symlink() or os.readlink(temporary) not in allowed:
                fail("CORRUPT_STATE", "Transaction staging link is unsafe")
            temporary.unlink()
        for directory in (self.root / "versions", self.root):
            if directory.is_dir() and not any(directory.iterdir()):
                directory.rmdir()
        self.journal.unlink()
        state_fd = os.open(self.state, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(state_fd)
        finally:
            os.close(state_fd)

    def owned(self):
        if not present(self.root):
            return None
        if self.root.is_symlink() or not self.root.is_dir():
            fail("UNSAFE_PATH", "App root is not a real directory")
        if not present(self.metadata):
            # A nonempty root without ownership is never adopted or removed.
            if any(self.root.iterdir()):
                fail("CORRUPT_STATE", "App root has no ownership manifest")
            return None
        versions = self.root / "versions"
        if versions.is_symlink() or not versions.is_dir():
            fail("CORRUPT_STATE", "Version storage is missing or unsafe")
        info = read_json(self.metadata)
        if (not isinstance(info, dict) or info.get("managedBy") != OWNER or info.get("appId") != self.app_id
                or not isinstance(info.get("versions"), list) or not isinstance(info.get("links"), dict)
                or not isinstance(info.get("revision"), str) or not REVISION.fullmatch(info["revision"])
                or not isinstance(info.get("version"), str) or not SEMVER.fullmatch(info["version"])):
            fail("CORRUPT_STATE", "App ownership manifest is invalid")
        if any(not isinstance(r, str) or not REVISION.fullmatch(r) for r in info["versions"]):
            fail("CORRUPT_STATE", "Version ownership list is invalid")
        if info["revision"] not in info["versions"]:
            fail("CORRUPT_STATE", "Current version is not owned")
        expected = self.root / "versions" / info["revision"]
        if (not self.current.is_symlink() or os.readlink(self.current) != str(expected)
                or expected.is_symlink() or not expected.is_dir()):
            fail("CORRUPT_STATE", "Current version is missing or not an owned symlink")
        for revision in info["versions"]:
            version = self.root / "versions" / revision
            if version.is_symlink() or not version.is_dir():
                fail("CORRUPT_STATE", "Owned version directory is missing or unsafe")
        allowed = self.expected_links(expected)
        for path, target in info["links"].items():
            if path not in allowed or target != allowed[path]:
                fail("CORRUPT_STATE", "Ownership metadata contains an unexpected link")
            candidate = Path(path)
            if not candidate.is_symlink() or os.readlink(candidate) != target:
                fail("CORRUPT_STATE", "An owned activation link is missing or replaced", path=path)
        if set(info["links"]) != set(allowed):
            fail("CORRUPT_STATE", "Ownership metadata omits activation links")
        return info

    def desktop_name(self):
        return (self.app_id if self.repo == "kos-apps" else self.executables[0]) + ".desktop"

    def expected_links(self, version):
        links = {}
        for executable in self.executables:
            links[str(self.bin / executable)] = str(self.current / "bin" / executable)
            desktop = self.desktop_name()
            links[str(self.data / "applications" / desktop)] = str(self.current / "share/applications" / desktop)
        services = version / "share/dbus-1/services"
        if services.is_dir():
            for source in services.glob("*.service"):
                if not regular(source):
                    fail("UNSAFE_INSTALL", "D-Bus service is not a regular file")
                links[str(self.data / "dbus-1/services" / source.name)] = str(self.current / "share/dbus-1/services" / source.name)
        return links

    def conflicts(self, info, links=None):
        owned = info["links"] if info else {}
        links = links or self.expected_links(self.current)
        for path in links:
            target = Path(path)
            if present(target) and path not in owned:
                fail("EXTERNALLY_MANAGED", "Existing user activation is not owned by this installer", path=path)
        if self.repo == "kos-apps":
            old_desktop = self.data / "applications" / (self.executables[0] + ".desktop")
            if present(old_desktop) and str(old_desktop) not in owned:
                fail("EXTERNALLY_MANAGED", "Old desktop activation is not installer-owned; review tools/purge-legacy-apps.py for explicit legacy program/data cleanup", path=str(old_desktop))
        for executable in self.executables:
            for directory in os.get_exec_path():
                candidate = Path(directory) / executable
                if present(candidate) and os.access(candidate, os.X_OK) and str(candidate) not in owned:
                    fail("EXTERNALLY_MANAGED", "Executable already supplied by another installation", path=str(candidate))
        data_dirs = [Path(p) for p in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if p]
        for directory in data_dirs:
            if directory == self.data:
                continue
            for executable in self.executables:
                desktop = directory / "applications" / self.desktop_name()
                old_desktop = directory / "applications" / (executable + ".desktop")
                if present(desktop) or present(old_desktop):
                    fail("EXTERNALLY_MANAGED", "Desktop activation is supplied by another installation", path=str(desktop if present(desktop) else old_desktop))
            for link in links:
                path = Path(link)
                if path.suffix == ".service" and present(directory / "dbus-1/services" / path.name):
                    fail("EXTERNALLY_MANAGED", "D-Bus activation is supplied by another installation", path=str(path))

    def run_child(self, args, stage):
        self.event("progress", "RUNNING", stage=stage, log=str(self.log))
        with self.log.open("ab") as output:
            output.write(("\n$ " + shlex.join(args) + "\n").encode())
            output.flush()
            child = subprocess.Popen(args, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = child.wait(timeout=CHILD_TIMEOUT)
            except (BaseException,):
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait(timeout=5)
                except ProcessLookupError:
                    pass
                finally:
                    # The direct child may exit before its descendants. Kill
                    # any remaining members even when wait() already returned.
                    try:
                        os.killpg(child.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                raise
        if code:
            fail("DEPENDENCY_UNSATISFIED" if stage == "configure" else "BUILD_FAILED",
                 "CMake configure failed; install the development dependencies documented by the app and retry manually"
                 if stage == "configure" else "Build or install failed; see log (the build is not retried)",
                 stage=stage, exitCode=code, log=str(self.log))

    def source(self, temporary):
        archive = temporary / "source.tar.gz"
        self.event("progress", "DOWNLOADING", stage="download")
        self.client.fetch(self.release["archiveUrl"], destination=archive, limit=MAX_ARCHIVE)
        digest = hashlib.sha256()
        with archive.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != self.release["archiveSha256"]:
            fail("INTEGRITY_ERROR", "Source archive SHA256 does not match the published manifest")
        directory = temporary / "source"
        directory.mkdir(mode=0o700)
        return extract_archive(archive, directory)

    def tools(self):
        missing = [name for name in ("cmake", "ninja", "c++") if shutil.which(name) is None]
        if missing:
            fail("DEPENDENCY_UNSATISFIED", "Install required build tools with your distribution package manager", missing=missing)

    def validate_install(self, version):
        for executable in self.executables:
            binary = version / "bin" / executable
            desktop = version / "share/applications" / self.desktop_name()
            if not regular(binary) or not os.access(binary, os.X_OK) or not regular(desktop):
                fail("INVALID_INSTALL", "Expected executable or desktop file is missing", executable=executable)
            text = desktop.read_text(encoding="utf-8")
            exec_lines = [line[5:] for line in text.splitlines() if line.startswith("Exec=")]
            if not exec_lines:
                fail("INVALID_INSTALL", "Desktop file has no Exec entry", path=str(desktop))
            for command in exec_lines:
                try:
                    token = shlex.split(command)[0]
                except (ValueError, IndexError):
                    fail("INVALID_INSTALL", "Desktop Exec is malformed")
                if token not in self.executables and token not in [str(version / "bin" / name) for name in self.executables]:
                    fail("EXTERNALLY_MANAGED", "Desktop Exec points outside the owned app", command=command)
        services = version / "share/dbus-1/services"
        if services.is_dir():
            for service in services.glob("*.service"):
                if not regular(service):
                    fail("UNSAFE_INSTALL", "D-Bus activation must be a regular file")
                lines = service.read_text(encoding="utf-8").splitlines()
                commands = [line[5:] for line in lines if line.startswith("Exec=")]
                if len(commands) != 1 or any(line.startswith("SystemdService=") for line in lines):
                    fail("INVALID_INSTALL", "D-Bus activation must directly execute its owned immutable binary")
                try:
                    binary = Path(shlex.split(commands[0])[0])
                except (ValueError, IndexError):
                    fail("INVALID_INSTALL", "D-Bus Exec is malformed")
                if not binary.is_absolute() or binary.parent != version / "bin" or not regular(binary) or not os.access(binary, os.X_OK):
                    fail("EXTERNALLY_MANAGED", "D-Bus Exec points outside the owned immutable binaries")
        for path in version.rglob("*"):
            if path.is_symlink():
                resolved = path.resolve()
                if not resolved.is_relative_to(version):
                    fail("UNSAFE_INSTALL", "Installed symlink escapes the immutable prefix", path=str(path))

    def install(self, info, check=False):
        self.tools()
        final = self.root / "versions" / self.release["revision"]
        if not check and info and info["revision"] == self.release["revision"]:
            return "ALREADY_INSTALLED", self.status_details(info)
        if present(final) and not check:
            fail("VERSION_CONFLICT", "Version directory already exists; refusing to overwrite it")
        secure_dir(self.state / "logs")
        fd, log_name = tempfile.mkstemp(prefix=f"{self.action}-", suffix=".log", dir=self.state / "logs")
        os.close(fd)
        self.log = Path(log_name)
        if not check:
            write_json(self.journal, {"schemaVersion": 1, "kind": "install", "candidate": self.release["revision"], "old": info, "new": None})
        try:
            with tempfile.TemporaryDirectory(prefix="work-", dir=self.state) as scratch:
                work = Path(scratch)
                source = self.source(work)
                self.run_child(["cmake", "-S", str(source), "-B", str(work / "build"), "-G", "Ninja",
                                "-DBUILD_TESTING=OFF", "-DCMAKE_BUILD_TYPE=Release", f"-DCMAKE_INSTALL_PREFIX={final}",
                                *([f"-DKOS_APPS={self.key}"] if self.repo == "kos-apps" else [])], "configure")
                if check:
                    return "READY", {"dependenciesSatisfied": True, "log": str(self.log), **self.status_details(info)}
                secure_dir(self.root)
                secure_dir(self.root / "versions")
                final.mkdir(mode=0o700)
                self.run_child(["cmake", "--build", str(work / "build"), "--parallel", "2"], "build")
                self.run_child(["cmake", "--install", str(work / "build")], "install")
                self.validate_install(final)
                links = self.expected_links(final)
                self.conflicts(info, links)
                metadata = {"managedBy": OWNER, "appId": self.app_id, "version": self.release["version"],
                            "revision": self.release["revision"], "versions": list(dict.fromkeys((info or {}).get("versions", []) + [self.release["revision"]])),
                            "links": links}
                write_json(self.journal, {"schemaVersion": 1, "kind": "install", "candidate": self.release["revision"], "old": info, "new": metadata})
                for path, target in links.items():
                    secure_dir(Path(path).parent)
                    if not present(Path(path)):
                        Path(path).symlink_to(target)
                self.set_current(metadata)
                write_json(self.metadata, metadata)
                self.recover()
                return "INSTALLED", {**self.status_details(metadata), "log": str(self.log)}
        finally:
            if not check:
                self.recover()

    def status_details(self, info):
        return {"installed": bool(info), "managed": bool(info), "available": True,
                "version": info["version"] if info else None, "revision": info["revision"] if info else None,
                "currentVersion": info["version"] if info else None,
                "currentRevision": info["revision"] if info else None, "root": str(self.root),
                "desktopFile": str(self.data / "applications" / self.desktop_name()) if info else None}

    def execute(self):
        with self.lock():
            # Validate ancestors even for read-only/offline operations.
            for directory in (self.data, self.root.parent):
                for parent in (directory, *directory.parents):
                    if parent.is_symlink():
                        fail("UNSAFE_PATH", "Managed storage has a symlink ancestor", path=str(parent))
            if self.action == "cleanup-plan" and present(self.journal):
                fail("RECOVERY_REQUIRED", "A pending transaction must be recovered before cleanup can be previewed")
            if self.action != "cleanup-plan":
                self.recover()
            info = self.owned()
            self.installed_info = info
            if self.action in ("cleanup-plan", "prune"):
                if not info:
                    return "NOT_INSTALLED", self.status_details(None)
                plan = self.cleanup_plan(info)
                if self.action == "cleanup-plan" or not plan["removedRevisions"]:
                    return "CLEANUP_PLAN" if self.action == "cleanup-plan" else "NOTHING_TO_PRUNE", plan
                if self.expected_plan is not None and self.expected_plan != plan["planToken"]:
                    fail("PLAN_CHANGED", "Owned versions changed after preview; inspect cleanup-plan again")
                if not self.confirmed:
                    fail("CONFIRMATION_REQUIRED", "Preview cleanup-plan, then use prune --yes to remove only the listed old program versions", **plan)
                new = {**info, "versions": plan["keptRevisions"]}
                write_json(self.journal, {"schemaVersion": 1, "kind": "prune", "candidate": None,
                                         "old": info, "new": new, "removed": plan["removedRevisions"]})
                self.recover()
                self.installed_info = new
                return "PRUNED", {**plan, **self.status_details(new)}
            if self.action == "uninstall":
                if not info:
                    return "NOT_INSTALLED", self.status_details(None)
                # The validated inventory is durable before the first removal;
                # a later offline invocation resumes interrupted uninstall.
                write_json(self.journal, {"schemaVersion": 1, "kind": "uninstall", "candidate": None, "old": info, "new": None})
                self.recover()
                return "UNINSTALLED", self.status_details(None)
            self.conflicts(info)
            if self.action == "status":
                self.release = {"version": info["version"], "revision": info["revision"]} if info else None
                return "INSTALLED" if info else "NOT_INSTALLED", self.status_details(info)
            self.event("progress", "CHECKING_RELEASE", stage="release")
            try:
                with network_deadline(90):
                    self.release = self.client.release(self.app_id, self.requested)
            except TimeoutError:
                fail("NETWORK_TIMEOUT", "Release discovery exceeded its total 90-second deadline")
            latest = tuple(map(int, self.release["version"].split(".")))
            installed = tuple(map(int, info["version"].split("."))) if info else None
            if info and latest == installed and info["revision"] != self.release["revision"]:
                fail("VERSION_REPLACED", "Published revision changed without a version increase; refusing replacement")
            update_available = bool(info and latest > installed)
            if self.action == "check-update":
                return "UPDATE_AVAILABLE" if update_available else "UP_TO_DATE" if info else "AVAILABLE", {
                    **self.status_details(info), "latestVersion": self.release["version"],
                    "updateAvailable": update_available}
            if info and latest < installed:
                fail("DOWNGRADE_REFUSED", "Latest publication is older than the installed version; current version retained")
            if self.action == "update" and not info:
                fail("NOT_INSTALLED", "Install the app before requesting an update")
            return self.install(info, check=self.action == "check")

    def run(self):
        try:
            code, details = self.execute()
            self.event("result", code, **details)
            return 0
        except Failure as exc:
            details = self.status_details(self.installed_info)
            if exc.code == "EXTERNALLY_MANAGED" and not self.installed_info:
                desktop = next((str(directory / "applications" / name)
                    for directory in [self.data, *(Path(p) for p in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":") if p)]
                    for name in (self.desktop_name(), self.executables[0] + ".desktop")
                    if (directory / "applications" / name).is_file()), None)
                details.update(installed=True, managed=False, externalInstallation=True, desktopFile=desktop)
            self.event("result", exc.code, success=False, **{**details, **exc.details})
            return 2
        except (KeyboardInterrupt, subprocess.TimeoutExpired) as exc:
            try:
                current = self.owned()
            except Failure:
                current = self.installed_info
            self.event("result", "CANCELLED" if isinstance(exc, KeyboardInterrupt) else "TIMED_OUT", success=False,
                       **self.status_details(current), message="Operation interrupted; publication recovered or recovery journal retained",
                       log=str(self.log) if self.log else None)
            return 130 if isinstance(exc, KeyboardInterrupt) else 3
        except Exception as exc:
            self.event("result", "INSTALLER_ERROR", success=False, message=str(exc), log=str(self.log) if self.log else None)
            return 1


class JsonArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        raise Failure("INVALID_ARGUMENT", message)


def main(argv=None):
    parser = JsonArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, choices=APPS)
    parser.add_argument("action", choices=("check", "check-update", "install", "update", "status", "uninstall", "cleanup-plan", "prune"))
    parser.add_argument("--version")
    parser.add_argument("--yes", action="store_true", help="Confirm removal of installer-owned old program versions")
    parser.add_argument("--expected-plan", help="Refuse cleanup if ownership changed since preview")
    try:
        args = parser.parse_args(argv)
    except Failure as exc:
        print(json.dumps({"schemaVersion": 1, "appId": None, "action": None, "stage": "arguments",
                          "type": "result", "success": False, "code": exc.code,
                          "version": None, "revision": None, "details": exc.details}), flush=True)
        return 2
    installer = Installer(args.app, args.action, args.version, confirmed=args.yes, expected_plan=args.expected_plan)
    if args.version and not SEMVER.fullmatch(args.version):
        installer.event("result", "INVALID_VERSION", success=False, message="Version must be a semantic x.y.z version")
        return 2
    # SIGTERM follows the same child process-group cleanup as Ctrl-C.
    def terminate(signum, frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, terminate)
    return installer.run()


if __name__ == "__main__":
    sys.exit(main())
