#!/usr/bin/env python3
"""Synthetic, isolated installer coverage. No real app builds or user installs."""
import contextlib
import hashlib
import http.server
import importlib.util
import io
import json
import os
from pathlib import Path
import ssl
import subprocess
import tarfile
import time
import tempfile
import threading
import unittest
from unittest import mock
import urllib.error

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("app_installer", ROOT / "tools/app-installer.py")
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)
REV = "a" * 40
REV2 = "b" * 40


def archive_bytes(extra=None):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w:gz") as tar:
        for name, data in {"source/CMakeLists.txt": b"project(Fake)\n", **(extra or {})}.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tar.addfile(info, io.BytesIO(data))
    return stream.getvalue()


class FixtureClient(app.GitHubClient):
    """Only test code can redirect requests to the synthetic loopback server."""
    def __init__(self, repo, base):
        super().__init__(repo)
        self.base = base

    def validate_url(self, url, redirected=False):
        if url.startswith(self.base + "/"):
            return
        return super().validate_url(url, redirected)

    def fetch(self, url, destination=None, limit=app.MAX_JSON):
        super().validate_url(url)
        if url.endswith("/releases/latest"):
            route = "/release"
        elif url.endswith(".app-release.json") or url.endswith("/app-release.json"):
            route = "/manifest"
        else:
            route = "/archive"
        return super().fetch(self.base + route, destination, limit)


class InstallerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (ROOT / "tmp").mkdir(exist_ok=True)
        cls.responses = {}
        cls.requests = []
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                cls.requests.append(self.path)
                status, body, headers = cls.responses.get(self.path, (404, b"missing", {}))
                self.send_response(status)
                for name, value in headers.items():
                    self.send_header(name, value)
                self.end_headers()
                self.wfile.write(body)
            def log_message(self, *args):
                pass
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = "http://127.0.0.1:" + str(cls.server.server_port)

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="app-installer-", dir=ROOT / "tmp")
        self.folder = Path(self.temporary.name)
        self.home = self.folder / "home"
        self.home.mkdir()
        self.tools = self.folder / "tools"
        self.tools.mkdir()
        self.env = mock.patch.dict(os.environ, {"HOME": str(self.home), "XDG_DATA_HOME": str(self.home / "data"),
            "XDG_STATE_HOME": str(self.home / "state"), "XDG_DATA_DIRS": str(self.folder / "system"),
            "PATH": str(self.tools)}, clear=False)
        self.env.start()
        self.make_tools()
        self.publish()
        type(self).requests.clear()

    def tearDown(self):
        self.env.stop()
        self.temporary.cleanup()

    def make_tools(self):
        # CMake fixture never invokes a compiler or reads production source.
        script = '''#!{python}
import json, os, pathlib, sys
args=sys.argv[1:]
if "-S" in args:
    if os.environ.get("FIXTURE_CONFIGURE_FAIL"): sys.exit(11)
    build=pathlib.Path(args[args.index("-B")+1]); build.mkdir(parents=True)
    prefix=next(a.split("=",1)[1] for a in args if a.startswith("-DCMAKE_INSTALL_PREFIX="))
    selected=next((a.split("=",1)[1] for a in args if a.startswith("-DKOS_APPS=")), "listenfree")
    (build/"fixture.json").write_text(json.dumps({{"prefix":prefix,"app":selected}}))
elif "--build" in args:
    if os.environ.get("FIXTURE_BUILD_FAIL"): sys.exit(12)
elif "--install" in args:
    config=json.loads((pathlib.Path(args[1])/"fixture.json").read_text())
    prefix=pathlib.Path(config["prefix"]); selected=config["app"]
    (prefix/"bin").mkdir(parents=True, exist_ok=True)
    (prefix/"share/applications").mkdir(parents=True, exist_ok=True)
    command="listenfree" if selected=="listenfree" else "kos-"+selected
    desktop="listenfree" if selected=="listenfree" else "org.nextks."+selected
    binary=prefix/"bin"/command; binary.write_text("#!/bin/sh\\nexit 0\\n"); binary.chmod(0o755)
    (prefix/"share/applications"/(desktop+".desktop")).write_text("[Desktop Entry]\\nType=Application\\nExec="+str(binary)+"\\n")
    if selected=="calendar":
        (prefix/"share/dbus-1/services").mkdir(parents=True)
        (prefix/"share/dbus-1/services/org.nextks.calendar.Pim.service").write_text("[D-BUS Service]\\nName=org.nextks.calendar.Pim\\nExec="+str(binary)+"\\n")
'''.format(python=os.sys.executable)
        (self.tools / "cmake").write_text(script)
        (self.tools / "cmake").chmod(0o755)
        for name in ("ninja", "c++"):
            (self.tools / name).write_text("#!/bin/sh\nexit 0\n")
            (self.tools / name).chmod(0o755)

    def publish(self, version="1.2.3", revision=REV):
        self.archive = archive_bytes()
        key = getattr(self, "key", "calendar")
        repository, self.app_id, _ = app.APPS[key]
        self.manifest = {"schemaVersion": 1, "appId": self.app_id, "version": version,
                         "revision": revision, "archiveSha256": hashlib.sha256(self.archive).hexdigest()}
        asset = self.app_id + ".app-release.json" if repository == "kos-apps" else "app-release.json"
        self.release = {"draft": False, "prerelease": False, "tag_name": "v" + version,
                        "assets": [{"name": asset, "browser_download_url":
                            "https://github.com/NextKde/" + repository + "/releases/download/v" + version + "/" + asset}]}
        self.sync()

    def sync(self):
        type(self).responses = {"/release": (200, json.dumps(self.release).encode(), {}),
            "/manifest": (200, json.dumps(self.manifest).encode(), {}), "/archive": (200, self.archive, {})}

    def invoke(self, action, requested=None, **options):
        events = []
        engine = app.Installer(getattr(self, "key", "calendar"), action, requested,
            client=FixtureClient(app.APPS[getattr(self, "key", "calendar")][0], self.base),
            emit=events.append, **options)
        exit_code = engine.run()
        results = [event for event in events if event["type"] == "result"]
        self.assertEqual(len(results), 1, events)
        self.assertEqual(results[0]["schemaVersion"], 1)
        self.assertEqual(results[0]["appId"], self.app_id)
        return exit_code, results[0], engine

    def installed(self):
        code, result, engine = self.invoke("install")
        self.assertEqual(code, 0, result)
        return engine

    def test_full_install_offline_status_uninstall_preserves_data(self):
        engine = self.installed()
        user_data = self.home / "data/calendar/events.json"
        user_data.parent.mkdir(); user_data.write_text("keep")
        type(self).responses = {}
        type(self).requests.clear()
        self.assertTrue(engine.current.is_symlink())
        self.assertEqual(self.invoke("status")[1]["details"]["version"], "1.2.3")
        self.assertEqual(self.invoke("uninstall")[1]["code"], "UNINSTALLED")
        self.assertFalse(engine.root.exists())
        self.assertEqual(user_data.read_text(), "keep")
        self.assertEqual(type(self).requests, [])

    def test_status_and_uninstall_idempotent_without_network(self):
        for action in ("status", "uninstall", "uninstall"):
            self.assertEqual(self.invoke(action)[1]["code"], "NOT_INSTALLED")
        self.assertEqual(type(self).requests, [])

    def test_release_lookup_and_version(self):
        code, result, _ = self.invoke("check-update", "1.2.3")
        self.assertEqual(code, 0)
        self.assertEqual(result["version"], "1.2.3")
        self.assertFalse(result["details"]["installed"])

    def test_version_mismatch(self):
        self.assertEqual(self.invoke("check-update", "2.0.0")[1]["code"], "VERSION_MISMATCH")

    def test_no_release(self):
        type(self).responses["/release"] = (404, b"missing", {})
        self.assertEqual(self.invoke("check-update")[1]["code"], "RELEASE_UNAVAILABLE")

    def test_rate_limited_no_retry(self):
        type(self).responses["/release"] = (429, b"slow", {})
        self.assertEqual(self.invoke("check-update")[1]["code"], "RATE_LIMITED")
        self.assertEqual(type(self).requests.count("/release"), 1)

    def test_transient_error_three_attempts(self):
        type(self).responses["/release"] = (503, b"retry", {})
        with mock.patch.object(app.time, "sleep"):
            self.assertEqual(self.invoke("check-update")[1]["code"], "NETWORK_ERROR")
        self.assertEqual(type(self).requests.count("/release"), 3)

    def test_tls_error_not_retried(self):
        client = app.GitHubClient("kos-apps")
        with mock.patch.object(client.opener, "open", side_effect=urllib.error.URLError(ssl.SSLError("bad cert"))) as request:
            with self.assertRaises(app.Failure) as failure:
                client.fetch("https://api.github.com/repos/NextKde/kos-apps/releases/latest")
            self.assertEqual(failure.exception.code, "TLS_ERROR")
            self.assertEqual(request.call_count, 1)

    def test_json_size_limit(self):
        type(self).responses["/release"] = (200, b" " * (app.MAX_JSON + 1), {})
        self.assertEqual(self.invoke("check-update")[1]["code"], "RESPONSE_TOO_LARGE")

    def test_prerelease_tag_identity_rejected(self):
        for field, value in (("prerelease", True), ("draft", True), ("tag_name", "wrong")):
            with self.subTest(field=field):
                self.publish(); self.release[field] = value; self.sync()
                self.assertEqual(self.invoke("check-update")[1]["code"], "INVALID_RELEASE")

    def test_manifest_identity_revision_checksum_validation(self):
        for field, value in (("schemaVersion", True), ("appId", "other"), ("revision", "../escape"),
                             ("version", "01.2.3"), ("archiveSha256", "bad")):
            with self.subTest(field=field):
                self.publish(); self.manifest[field] = value; self.sync()
                self.assertEqual(self.invoke("check-update")[1]["code"], "INVALID_RELEASE")

    def test_urls_reject_external_redirects(self):
        client = app.GitHubClient("kos-apps")
        for url in ("http://github.com/NextKde/kos-apps/x", "https://evil.com/x",
                    "https://github.com/Other/kos-calendar/x", "https://github.com/NextKde/kos-apps-evil/x",
                    "https://github.com:444/NextKde/kos-apps/x"):
            with self.subTest(url=url), self.assertRaises(app.Failure):
                client.validate_url(url, redirected=True)
        with self.assertRaises(app.Failure):
            client.validate_url("https://release-assets.githubusercontent.com/a")
        client.validate_url("https://release-assets.githubusercontent.com/a", redirected=True)

    def test_hash_mismatch_no_install(self):
        self.manifest["archiveSha256"] = "0" * 64; self.sync()
        _, result, engine = self.invoke("install")
        self.assertEqual(result["code"], "INTEGRITY_ERROR")
        self.assertFalse(engine.current.exists())
        self.assertFalse(engine.root.exists())

    def test_archive_traversal_links_and_duplicates(self):
        for kind in ("traversal", "symlink", "hardlink", "duplicate"):
            with self.subTest(kind=kind):
                data = io.BytesIO()
                with tarfile.open(fileobj=data, mode="w:gz") as tar:
                    entry = tarfile.TarInfo("../escape" if kind == "traversal" else "source/item")
                    if kind in ("symlink", "hardlink"):
                        entry.type = tarfile.SYMTYPE if kind == "symlink" else tarfile.LNKTYPE
                        entry.linkname = "/etc/passwd"
                    tar.addfile(entry)
                    if kind == "duplicate": tar.addfile(entry)
                self.archive = data.getvalue()
                self.manifest["archiveSha256"] = hashlib.sha256(self.archive).hexdigest(); self.sync()
                self.assertEqual(self.invoke("install")[1]["code"], "UNSAFE_ARCHIVE")

    def test_check_configures_without_installing(self):
        code, result, engine = self.invoke("check")
        self.assertEqual(code, 0, result)
        self.assertEqual(result["code"], "READY")
        self.assertFalse(engine.root.exists())
        self.assertEqual(engine.log.stat().st_mode & 0o777, 0o600)

    def test_dependency_failure_actionable(self):
        with mock.patch.dict(os.environ, {"FIXTURE_CONFIGURE_FAIL": "1"}):
            _, result, engine = self.invoke("check")
        self.assertEqual(result["code"], "DEPENDENCY_UNSATISFIED")
        self.assertIn("development dependencies", result["details"]["message"])
        self.assertTrue(engine.log.exists())
        self.assertFalse(engine.root.exists())

    def test_missing_tools(self):
        (self.tools / "c++").unlink()
        self.assertEqual(self.invoke("install")[1]["code"], "DEPENDENCY_UNSATISFIED")

    def test_failed_update_keeps_current(self):
        engine = self.installed()
        target = os.readlink(engine.current)
        self.publish("1.2.4", REV2)
        with mock.patch.dict(os.environ, {"FIXTURE_BUILD_FAIL": "1"}):
            self.assertEqual(self.invoke("update")[1]["code"], "BUILD_FAILED")
        self.assertEqual(os.readlink(engine.current), target)
        self.assertFalse((engine.root / "versions" / REV2).exists())
        self.assertEqual(self.invoke("status")[1]["details"]["currentVersion"], "1.2.3")

    def test_successful_update_preserves_old_version(self):
        engine = self.installed(); self.publish("1.2.4", REV2)
        self.assertTrue(self.invoke("check-update")[1]["details"]["updateAvailable"])
        self.assertEqual(self.invoke("update")[1]["code"], "INSTALLED")
        self.assertTrue((engine.root / "versions" / REV).is_dir())
        self.assertEqual(engine.current.resolve().name, REV2)
        self.assertEqual(self.invoke("install")[1]["code"], "ALREADY_INSTALLED")

    def test_network_failure_preserves_installed_details(self):
        self.installed(); type(self).responses = {}
        result = self.invoke("check-update")[1]
        self.assertEqual(result["code"], "RELEASE_UNAVAILABLE")
        self.assertTrue(result["details"]["installed"])
        self.assertEqual(result["details"]["currentVersion"], "1.2.3")

    def test_unowned_local_desktop_conflict(self):
        path = self.home / "data/applications/kos-calendar.desktop"
        path.parent.mkdir(parents=True); path.write_text("external")
        self.assertEqual(self.invoke("install")[1]["code"], "EXTERNALLY_MANAGED")
        self.assertEqual(path.read_text(), "external")

    def test_system_desktop_and_path_conflict(self):
        path = self.folder / "system/applications/kos-calendar.desktop"
        path.parent.mkdir(parents=True); path.write_text("external")
        self.assertEqual(self.invoke("status")[1]["code"], "EXTERNALLY_MANAGED")
        path.unlink()
        path = self.tools / "kos-calendar"; path.write_text("external"); path.chmod(0o755)
        self.assertEqual(self.invoke("install")[1]["code"], "EXTERNALLY_MANAGED")

    def test_dbus_conflict_retains_existing_service(self):
        path = self.home / "data/dbus-1/services/org.nextks.calendar.Pim.service"
        path.parent.mkdir(parents=True); path.write_text("existing-core")
        self.assertEqual(self.invoke("install")[1]["code"], "EXTERNALLY_MANAGED")
        self.assertEqual(path.read_text(), "existing-core")

    def test_corrupt_manifest_or_current_refuses_uninstall(self):
        engine = self.installed()
        engine.current.unlink()
        self.assertEqual(self.invoke("uninstall")[1]["code"], "CORRUPT_STATE")
        self.assertTrue((engine.root / "versions" / REV).exists())

    def test_ownership_escape_rejected(self):
        engine = self.installed()
        metadata = json.loads(engine.metadata.read_text())
        metadata["links"][str(self.home / "precious")] = "/tmp/escape"
        engine.metadata.write_text(json.dumps(metadata))
        self.assertEqual(self.invoke("uninstall")[1]["code"], "CORRUPT_STATE")

    def test_symlink_storage_refused(self):
        external = self.folder / "external"; external.mkdir()
        (self.home / "data").symlink_to(external, target_is_directory=True)
        self.assertEqual(self.invoke("install")[1]["code"], "UNSAFE_PATH")
        self.assertEqual(list(external.iterdir()), [])

    def test_downgrade_refused_and_not_offered(self):
        self.installed(); self.publish("1.1.0", REV2)
        self.assertFalse(self.invoke("check-update")[1]["details"]["updateAvailable"])
        self.assertEqual(self.invoke("check-update")[1]["code"], "UP_TO_DATE")
        self.assertEqual(self.invoke("update")[1]["code"], "DOWNGRADE_REFUSED")
        self.assertEqual(self.invoke("install")[1]["code"], "DOWNGRADE_REFUSED")

    def test_same_version_different_revision_refused(self):
        self.installed(); self.publish("1.2.3", REV2)
        self.assertEqual(self.invoke("check-update")[1]["code"], "VERSION_REPLACED")
        self.assertEqual(self.invoke("update")[1]["code"], "VERSION_REPLACED")

    def test_replaced_link_refuses_uninstall(self):
        engine = self.installed()
        desktop = self.home / "data/applications/org.nextks.calendar.desktop"
        desktop.unlink(); desktop.write_text("external")
        self.assertEqual(self.invoke("uninstall")[1]["code"], "CORRUPT_STATE")
        self.assertTrue(engine.current.exists())
        self.assertEqual(desktop.read_text(), "external")

    def test_system_dbus_activation_conflict(self):
        path = self.folder / "system/dbus-1/services/org.nextks.calendar.Pim.service"
        path.parent.mkdir(parents=True); path.write_text("existing")
        self.assertEqual(self.invoke("install")[1]["code"], "EXTERNALLY_MANAGED")
        self.assertEqual(path.read_text(), "existing")

    def test_truncated_response_retried_bounded(self):
        type(self).responses["/release"] = (200, b"{}", {"Content-Length": "99"})
        with mock.patch.object(app.time, "sleep"):
            self.assertEqual(self.invoke("check-update")[1]["code"], "NETWORK_ERROR")
        self.assertEqual(type(self).requests.count("/release"), 3)

    def test_external_status_identifies_unmanaged_desktop(self):
        path = self.folder / "system/applications/kos-calendar.desktop"
        path.parent.mkdir(parents=True); path.write_text("external")
        result = self.invoke("status")[1]
        self.assertTrue(result["details"]["installed"])
        self.assertFalse(result["details"]["managed"])
        self.assertEqual(result["details"]["desktopFile"], str(path))

    def test_check_installed_keeps_current(self):
        engine = self.installed(); old = os.readlink(engine.current)
        self.assertEqual(self.invoke("check")[1]["code"], "READY")
        self.assertEqual(os.readlink(engine.current), old)

    def test_invalid_cli_arguments_one_json_result(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            self.assertEqual(app.main(["--app", "not-allowed", "install"]), 2)
        lines = output.getvalue().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertEqual(json.loads(lines[0])["code"], "INVALID_ARGUMENT")

    def test_download_absolute_deadline_bounded(self):
        class SlowResponse:
            url = "https://api.github.com/repos/NextKde/kos-apps/releases/latest"
            headers = {}
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self, count): return b"x"
        client = app.GitHubClient("kos-apps")
        with mock.patch.object(client.opener, "open", return_value=SlowResponse()) as request, \
             mock.patch.object(app.time, "monotonic", side_effect=[0, 0, 46, 100, 100, 146, 200, 200, 246]), \
             mock.patch.object(app.time, "sleep"):
            with self.assertRaises(app.Failure) as failure:
                client.fetch(SlowResponse.url)
            self.assertEqual(failure.exception.code, "NETWORK_TIMEOUT")
            self.assertEqual(request.call_count, 3)

    def test_child_timeout_kills_process_group(self):
        engine = app.Installer("calendar", "check", emit=lambda value: None)
        engine.log = self.folder / "private.log"; engine.log.touch(mode=0o600)
        child_pid = self.folder / "child.pid"
        script = ("import subprocess,sys,time,signal; "
                  "p=subprocess.Popen([sys.executable,'-c','import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(30)']); "
                  "open(sys.argv[1],'w').write(str(p.pid)); time.sleep(30)")
        with mock.patch.object(app, "CHILD_TIMEOUT", 0.2):
            with self.assertRaises(subprocess.TimeoutExpired):
                engine.run_child([os.sys.executable, "-c", script, str(child_pid)], "build")
        self.assertTrue(child_pid.exists())
        process = Path("/proc") / child_pid.read_text()
        def stopped():
            try:
                return (process / "stat").read_text().split()[2] == "Z"
            except FileNotFoundError:
                return True
        for _ in range(20):
            if stopped():
                break
            time.sleep(0.01)
        self.assertTrue(stopped())

    def test_versions_parent_symlink_refused(self):
        engine = self.installed()
        versions = engine.root / "versions"
        external = self.folder / "external-versions"
        versions.rename(external); versions.symlink_to(external, target_is_directory=True)
        self.assertEqual(self.invoke("uninstall")[1]["code"], "CORRUPT_STATE")
        self.assertTrue((external / REV).is_dir())

    def test_publication_interrupt_after_each_boundary_recovers(self):
        boundaries = ("journal-building", "journal-prepared", "link", "staging", "current", "metadata")
        for boundary in boundaries:
            for updating in (False, True):
                if boundary == "link" and updating:
                    # Identical activation inventories reuse existing links.
                    continue
                with self.subTest(boundary=boundary, updating=updating):
                    # A separate isolated subfixture for every crash boundary.
                    self.tearDown(); self.setUp()
                    original_info = None
                    if updating:
                        old_engine = self.installed()
                        original_info = json.loads(old_engine.metadata.read_text())
                        self.publish("1.2.4", REV2)
                    original_write, original_symlink, original_replace = app.write_json, Path.symlink_to, app.os.replace
                    triggered = []
                    def crash():
                        if not triggered:
                            triggered.append(True)
                            raise KeyboardInterrupt()
                    def write(path, value):
                        original_write(path, value)
                        if (boundary == "journal-building" and path.name == "transaction.json" and value.get("new") is None
                                or boundary == "journal-prepared" and path.name == "transaction.json" and value.get("new") is not None
                                or boundary == "metadata" and path.name == "ownership.json"):
                            crash()
                    def symlink(path, target, *args, **kwargs):
                        original_symlink(path, target, *args, **kwargs)
                        if boundary == "link" and path.parent.name == "applications" or boundary == "staging" and path.name == ".current-new":
                            crash()
                    def replace(source, destination):
                        original_replace(source, destination)
                        if boundary == "current" and Path(destination).name == "current":
                            crash()
                    with mock.patch.object(app, "write_json", side_effect=write), \
                         mock.patch.object(Path, "symlink_to", symlink), \
                         mock.patch.object(app.os, "replace", side_effect=replace):
                        _, result, engine = self.invoke("update" if updating else "install")
                    self.assertTrue(triggered)
                    self.assertEqual(result["code"], "CANCELLED")
                    code, status, _ = self.invoke("status")
                    self.assertEqual(code, 0, status)
                    committed = boundary == "metadata"
                    self.assertEqual(status["details"]["installed"], committed or updating)
                    if committed or updating:
                        expected = "1.2.4" if committed and updating else "1.2.3"
                        self.assertEqual(status["details"]["currentVersion"], expected)
                    self.assertFalse(engine.journal.exists())
                    if updating and not committed:
                        self.assertEqual(json.loads(engine.metadata.read_text()), original_info)

    def test_kill_style_interrupted_candidate_recovered_next_invocation(self):
        engine = app.Installer("calendar", "status")
        with engine.lock():
            app.write_json(engine.journal, {"schemaVersion": 1, "kind": "install", "candidate": REV, "old": None, "new": None})
            candidate = engine.root / "versions" / REV
            candidate.mkdir(parents=True)
            (candidate / "partial").write_text("interrupted")
        self.assertEqual(self.invoke("status")[1]["code"], "NOT_INSTALLED")
        self.assertFalse(engine.root.exists())
        self.assertFalse(engine.journal.exists())

    def test_interrupted_uninstall_resumes_offline(self):
        engine = self.installed()
        original = engine.checked_unlink
        calls = []
        def interrupted(path, target):
            original(path, target)
            calls.append(path)
            raise KeyboardInterrupt()
        engine.action = "uninstall"
        with mock.patch.object(engine, "checked_unlink", side_effect=interrupted):
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(engine.run(), 130)
        self.assertEqual(len(calls), 1)
        self.assertTrue(engine.journal.exists())
        type(self).responses = {}; type(self).requests.clear()
        self.assertEqual(self.invoke("uninstall")[1]["code"], "NOT_INSTALLED")
        self.assertFalse(engine.root.exists())
        self.assertEqual(type(self).requests, [])

    def test_corrupt_journal_cannot_delete_external_paths(self):
        engine = self.installed()
        info = json.loads(engine.metadata.read_text())
        info["links"][str(self.home / "precious")] = "/tmp/unowned"
        precious = self.home / "precious"; precious.write_text("keep")
        app.write_json(engine.journal, {"schemaVersion": 1, "kind": "uninstall", "candidate": None, "old": info, "new": None})
        self.assertEqual(self.invoke("uninstall")[1]["code"], "CORRUPT_STATE")
        self.assertEqual(precious.read_text(), "keep")
        self.assertTrue(engine.current.exists())

    def test_network_deadline_interrupts_open_headers(self):
        client = app.GitHubClient("kos-apps")
        old = app.network_deadline
        def short_deadline(seconds): return old(0.02)
        def stalled(*args, **kwargs):
            time.sleep(2)
            self.fail("Open/header stall was not interrupted")
        with mock.patch.object(app, "network_deadline", side_effect=short_deadline), \
             mock.patch.object(client.opener, "open", side_effect=stalled) as request, \
             mock.patch.object(app.time, "sleep", wraps=time.sleep):
            with self.assertRaises(app.Failure) as failure:
                client.fetch("https://api.github.com/repos/NextKde/kos-apps/releases/latest")
        self.assertEqual(failure.exception.code, "NETWORK_TIMEOUT")
        self.assertEqual(request.call_count, 3)

    def test_committed_service_cleanup_failure_resumes(self):
        engine = self.installed()
        stale = self.home / "data/dbus-1/services/org.nextks.calendar.Pim.service"
        cmake = self.tools / "cmake"
        script = cmake.read_text()
        script = "\n".join(line for line in script.splitlines() if 'org.nextks.calendar.Pim.service' not in line) + "\n"
        cmake.write_text(script)
        self.publish("1.2.4", REV2)
        original = app.Installer.checked_unlink
        def failed_once(instance, path, target):
            if Path(path) == stale:
                raise PermissionError("synthetic service unlink interruption")
            return original(instance, path, target)
        with mock.patch.object(app.Installer, "checked_unlink", failed_once):
            _, result, _ = self.invoke("update")
        self.assertEqual(result["code"], "INSTALLER_ERROR")
        self.assertTrue(engine.journal.exists())
        code, status, _ = self.invoke("status")
        self.assertEqual(code, 0, status)
        self.assertEqual(status["details"]["currentVersion"], "1.2.4")
        self.assertFalse(stale.is_symlink())
        self.assertFalse(engine.journal.exists())

    def test_nested_network_deadline_never_extends_outer(self):
        started = time.monotonic()
        with self.assertRaises(TimeoutError):
            with app.network_deadline(0.03):
                with app.network_deadline(1):
                    time.sleep(0.2)
        self.assertLess(time.monotonic() - started, 0.15)
        self.assertEqual(app.signal.getitimer(app.signal.ITIMER_REAL)[0], 0)

    def test_nested_network_deadline_restores_elapsed_outer(self):
        with self.assertRaises(TimeoutError):
            with app.network_deadline(0.05):
                with app.network_deadline(1):
                    time.sleep(0.02)
                remaining = app.signal.getitimer(app.signal.ITIMER_REAL)[0]
                self.assertLess(remaining, 0.04)
                time.sleep(0.1)

    def test_total_release_discovery_deadline(self):
        class StalledClient:
            def release(self, *args): time.sleep(1)
        old = app.network_deadline
        def tiny(seconds): return old(0.02)
        engine = app.Installer("calendar", "check-update", client=StalledClient(), emit=lambda value: events.append(value))
        events = []
        with mock.patch.object(app, "network_deadline", side_effect=tiny):
            self.assertEqual(engine.run(), 2)
        self.assertEqual(events[-1]["code"], "NETWORK_TIMEOUT")
        self.assertEqual(len([event for event in events if event["type"] == "result"]), 1)

    def test_each_selected_app_lifecycle_and_scoped_activation(self):
        for key in app.APPS:
            with self.subTest(app=key):
                self.key = key
                self.publish()
                engine = self.installed()
                desktop = self.home / "data/applications" / engine.desktop_name()
                self.assertTrue(desktop.is_symlink())
                self.assertFalse((engine.current / "bin/kos-todo").exists())
                self.assertEqual(sorted(path.name for path in (engine.current / "bin").iterdir()),
                                 list(app.APPS[key][2]))
                self.publish("1.2.4", REV2)
                self.assertEqual(self.invoke("update")[1]["code"], "INSTALLED")
                self.assertEqual(self.invoke("status")[1]["details"]["currentVersion"], "1.2.4")
                self.assertEqual(self.invoke("uninstall")[1]["code"], "UNINSTALLED")
                self.assertFalse(desktop.is_symlink())
        self.key = "calendar"

    def test_cleanup_plan_and_confirmed_prune_preserve_two_versions_and_data(self):
        engine = self.installed()
        for version, revision in (("1.2.4", REV2), ("1.2.5", "c" * 40)):
            self.publish(version, revision)
            self.assertEqual(self.invoke("update")[1]["code"], "INSTALLED")
        personal = self.home / "data/org.nextks.calendar/pim/events.ics"
        personal.parent.mkdir(parents=True)
        personal.write_text("keep personal data")
        type(self).responses = {}
        type(self).requests.clear()
        plan = self.invoke("cleanup-plan")[1]["details"]
        self.assertEqual(plan["removedRevisions"], [REV])
        self.assertEqual(plan["keptRevisions"], [REV2, "c" * 40])
        self.assertEqual(self.invoke("prune")[1]["code"], "CONFIRMATION_REQUIRED")
        self.assertEqual(self.invoke("prune", confirmed=True, expected_plan="wrong")[1]["code"], "PLAN_CHANGED")
        self.assertEqual(self.invoke("prune", confirmed=True, expected_plan=plan["planToken"])[1]["code"], "PRUNED")
        self.assertFalse((engine.root / "versions" / REV).exists())
        self.assertTrue((engine.root / "versions" / REV2).is_dir())
        self.assertEqual(engine.current.resolve().name, "c" * 40)
        self.assertEqual(personal.read_text(), "keep personal data")
        self.assertEqual(type(self).requests, [])

    def test_interrupted_prune_recovers_offline_without_removing_current(self):
        engine = self.installed()
        for version, revision in (("1.2.4", REV2), ("1.2.5", "c" * 40)):
            self.publish(version, revision)
            self.assertEqual(self.invoke("update")[1]["code"], "INSTALLED")
        plan = self.invoke("cleanup-plan")[1]["details"]
        type(self).responses = {}; type(self).requests.clear()
        with mock.patch.object(app.shutil, "rmtree", side_effect=PermissionError("synthetic prune interruption")):
            result = self.invoke("prune", confirmed=True, expected_plan=plan["planToken"])[1]
        self.assertEqual(result["code"], "INSTALLER_ERROR")
        self.assertTrue(engine.journal.is_file())
        self.assertEqual(self.invoke("cleanup-plan")[1]["code"], "RECOVERY_REQUIRED")
        status = self.invoke("status")[1]
        self.assertEqual(status["details"]["currentVersion"], "1.2.5")
        self.assertEqual(engine.current.resolve().name, "c" * 40)
        self.assertTrue((engine.root / "versions" / REV2).is_dir())
        self.assertFalse((engine.root / "versions" / REV).exists())
        self.assertFalse(engine.journal.exists())
        self.assertEqual(type(self).requests, [])

    def test_other_app_release_manifest_cannot_satisfy_selected_app(self):
        self.release["assets"][0]["name"] = "org.nextks.weather.app-release.json"
        self.sync()
        self.assertEqual(self.invoke("check-update")[1]["code"], "RELEASE_UNAVAILABLE")

    def test_lock_busy(self):
        engine = app.Installer("calendar", "status")
        with engine.lock():
            self.assertEqual(self.invoke("status")[1]["code"], "BUSY")


if __name__ == "__main__":
    unittest.main()
