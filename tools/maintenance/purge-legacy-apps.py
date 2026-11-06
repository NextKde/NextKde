#!/usr/bin/env python3
"""Remove retired Calendar/Calculator/Weather programs and data; preview by default."""

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys


APPS = {
    "calendar": ("org.nextkde.Calendar", ("kos-calendar", "kos-pim-service", "kos-todo")),
    "calculator": ("org.nextkde.Calculator", ("kos-calculator",)),
    "weather": ("org.nextkde.Weather", ("kos-weather", "kos-weather-backend")),
}
OWNER = "nextkde-source-installer-v1"
REVISION = re.compile(r"[0-9a-f]{40}\Z")
LIMIT = 50000


def present(path):
    return os.path.lexists(path)


def overlaps(left, right):
    return left == right or left in right.parents or right in left.parents


def ancestors(path):
    for parent in reversed(path.parents):
        if not present(parent):
            continue
        info = parent.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_mode & 0o022:
            # The sticky system temporary directory is not a supported data root.
            raise ValueError(f"unsafe ancestor (symlink or writable by others): {parent}")
        if info.st_uid not in (0, os.getuid()):
            raise ValueError(f"ancestor owned by another user: {parent}")


def inspect(path):
    """Snapshot owned nodes, never descending through a symlink or mount boundary."""
    ancestors(path)
    device = path.lstat().st_dev
    result = {}

    def record(node):
        info = node.lstat()
        if info.st_uid != os.getuid() or info.st_dev != device:
            raise ValueError(f"foreign ownership or mount boundary: {node}")
        if not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)
                or stat.S_ISLNK(info.st_mode)):
            raise ValueError(f"special file: {node}")
        if not stat.S_ISLNK(info.st_mode) and info.st_mode & 0o022:
            raise ValueError(f"file/directory writable by others: {node}")
        result[str(node)] = (info.st_dev, info.st_ino, info.st_mode, info.st_size,
                             info.st_mtime_ns, info.st_ctime_ns,
                             os.readlink(node) if stat.S_ISLNK(info.st_mode) else None)
        if len(result) > LIMIT:
            raise ValueError("target exceeds inspection limit")
        if stat.S_ISDIR(info.st_mode):
            for child in sorted(node.iterdir()):
                record(child)

    record(path)
    return result


def delete_node(parent_fd, name, expected, absolute):
    """Use no-follow directory descriptors; substituted links cannot redirect removal."""
    info = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    saved = expected.get(str(absolute))
    if saved is None or (info.st_dev, info.st_ino, info.st_mode) != saved[:3]:
        raise ValueError(f"target identity changed: {absolute}")
    if stat.S_ISDIR(info.st_mode):
        fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
        try:
            opened = os.fstat(fd)
            if (opened.st_dev, opened.st_ino) != saved[:2]:
                raise ValueError(f"directory identity changed: {absolute}")
            for child in os.listdir(fd):
                delete_node(fd, child, expected, absolute / child)
        finally:
            os.close(fd)
        os.rmdir(name, dir_fd=parent_fd)
    else:
        if (info.st_size, info.st_mtime_ns, info.st_ctime_ns) != saved[3:6]:
            raise ValueError(f"file changed: {absolute}")
        os.unlink(name, dir_fd=parent_fd)


def remove(path, expected):
    if inspect(path) != expected:
        raise ValueError(f"target changed since preview: {path}")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parent.parts[1:]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        delete_node(fd, path.name, expected, path)
    finally:
        os.close(fd)


def command(executable, *arguments):
    return subprocess.run([executable, *arguments], capture_output=True, text=True,
                          timeout=15, check=True, env={**os.environ, "LC_ALL": "C"}).stdout


def flatpak_inventory(executable):
    # Without a scope selector Flatpak lists user AND all configured system installations.
    result = []
    for line in command(executable, "list", "--app", "--all",
                        "--columns=ref:full,active:full,installation").splitlines():
        fields = [field.strip() for field in line.split("\t")]
        if len(fields) != 3:
            raise ValueError("unreadable Flatpak inventory")
        ref, commit, scope = fields
        if not re.fullmatch(r"(?:app/)?[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", ref):
            raise ValueError("invalid Flatpak ref")
        if not re.fullmatch(r"[0-9a-f]{12,64}", commit) or not scope:
            raise ValueError("invalid Flatpak commit/installation")
        ref = ref if ref.startswith("app/") else "app/" + ref
        # list hard-truncates active commits even with :full. Resolve only our
        # retired IDs, using the same installation and exact ref, before deletion.
        if ref.split("/")[1] in {app[0] for app in APPS.values()}:
            selector = "--" + scope if scope in ("user", "system") else "--installation=" + scope
            full = command(executable, "info", selector, "--show-commit", ref).strip()
            if not re.fullmatch(r"[0-9a-f]{64}", full) or not full.startswith(commit):
                raise ValueError("invalid Flatpak commit or inventory changed during inspection")
            commit = full
        result.append((ref, commit, scope))
    return sorted(result)


def running(names, executable, old_ids):
    if executable:
        for app in command(executable, "ps", "--columns=application").splitlines():
            if app.strip() in old_ids:
                raise ValueError(f"close running Flatpak first: {app}")
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            words = (proc / "cmdline").read_bytes().split(b"\0")
            comm = (proc / "comm").read_text().strip()
            if (words and Path(os.fsdecode(words[0])).name in names
                    or any(comm == name[:15] for name in names)):
                raise ValueError(f"close application/helper first: PID {proc.name} ({comm})")
        except FileNotFoundError:
            continue


def installed_files(key):
    """Whitelist from retained old per-app and historical core CMake inventories."""
    _, executables = APPS[key]
    names = {"kos-" + key} | ({"kos-todo"} if key == "calendar" else set())
    files = {"bin/" + name for name in executables}
    for name in names:
        files |= {f"share/applications/{name}.desktop", f"share/icons/hicolor/scalable/apps/{name}.svg"}
    identities = {"calendar": ("org.nextkde.Kos.Calendar",),
                  "calculator": ("org.nextkde.Kos.Calculator",),
                  "weather": ("org.nextkde.Weather", "org.nextkde.Kos.Weather")}[key]
    files |= {f"share/metainfo/{identity}.metainfo.xml" for identity in identities}
    if key == "calendar":
        files |= {"share/dbus-1/services/org.nextkde.Kos.Pim1.service",
                  "share/systemd/user/kos-pim-service.service"}
    for prefix in (f"share/kos-{key}", f"share/doc/kos-{key}"):
        files |= {prefix + "/" + name for name in ("LICENSE", "SOURCE_PROVENANCE.md", "THIRD_PARTY_NOTICES.md")}
    return files


def source_targets(key, data, state, home):
    old_id, executables = APPS[key]
    root = data / "nextkde-apps" / key
    engine = state / "nextkde-apps" / key
    if not present(root):
        if present(engine):
            raise ValueError(f"orphan installer state; manual ownership review required: {engine}")
        return [], None
    if root.is_dir() and not root.is_symlink() and not any(root.iterdir()) and not present(engine):
        return [(root, inspect(root))], None
    snapshot = inspect(root)
    if root.is_symlink() or set(p.name for p in root.iterdir()) != {"ownership.json", "versions", "current"}:
        raise ValueError(f"unknown source root contents: {root}")
    metadata = root / "ownership.json"
    if metadata.is_symlink() or not metadata.is_file() or metadata.stat().st_size > 1024 * 1024:
        raise ValueError("unsafe source ownership record")
    info = json.loads(metadata.read_text())
    if (not isinstance(info, dict) or info.get("managedBy") != OWNER or info.get("appId") != old_id
            or not isinstance(info.get("versions"), list) or not info["versions"]
            or any(not isinstance(v, str) or not REVISION.fullmatch(v) for v in info["versions"])
            or info.get("revision") not in info["versions"]):
        raise ValueError("unknown/mixed source ownership; new IDs are never removed")
    versions = root / "versions"
    if versions.is_symlink() or not versions.is_dir() or set(p.name for p in versions.iterdir()) != set(info["versions"]):
        raise ValueError("unknown source revision directory")
    current = root / "current"
    if not current.is_symlink() or os.readlink(current) != str(versions / info["revision"]):
        raise ValueError("source current link was replaced")
    files = installed_files(key)
    for revision in info["versions"]:
        version = versions / revision
        if not version.is_dir() or version.is_symlink():
            raise ValueError("unsafe version directory")
        for raw in snapshot:
            node = Path(raw)
            if version not in node.parents:
                continue
            relative = node.relative_to(version).as_posix()
            mode = snapshot[raw][2]
            if stat.S_ISLNK(mode) or (stat.S_ISREG(mode) and relative not in files):
                raise ValueError(f"unknown installed file: {node}")
            if stat.S_ISDIR(mode) and not any(name.startswith(relative + "/") for name in files):
                raise ValueError(f"unknown installed directory: {node}")
    allowed = {}
    for name in executables:
        allowed[str(home / ".local/bin" / name)] = str(current / "bin" / name)
    for name in ({"kos-" + key} | ({"kos-todo"} if key == "calendar" else set())):
        path = data / "applications" / (name + ".desktop")
        allowed[str(path)] = str(current / "share/applications" / path.name)
    if key == "calendar":
        path = data / "dbus-1/services/org.nextkde.Kos.Pim1.service"
        allowed[str(path)] = str(current / "share/dbus-1/services" / path.name)
    owned = info.get("links")
    if not isinstance(owned, dict) or not owned:
        raise ValueError("missing activation ownership")
    targets = []
    for raw, target in owned.items():
        path = Path(raw)
        if allowed.get(raw) != target:
            raise ValueError(f"unknown activation ownership: {path}")
        # Missing links are safe to skip after an interrupted explicit purge.
        if present(path):
            if not path.is_symlink() or os.readlink(path) != target:
                raise ValueError(f"replaced activation link: {path}")
            targets.append((path, inspect(path)))
    if not present(engine):
        raise ValueError("missing source installer lock/state")
    engine_snapshot = inspect(engine)
    if engine.is_symlink() or present(engine / "transaction.json"):
        raise ValueError("pending transaction or unsafe installer state; manual recovery required")
    if any(p.name not in {"lock", "logs"} for p in engine.iterdir()):
        raise ValueError("unknown source installer state contents")
    if (engine / "lock").is_symlink() or not (engine / "lock").is_file():
        raise ValueError("unsafe source installer lock")
    targets.extend([(root, snapshot), (engine, engine_snapshot)])
    return targets, engine / "lock"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", choices=[*APPS, "all"], required=True)
    parser.add_argument("--apply", action="store_true", help="Delete listed legacy programs AND personal data")
    parser.add_argument("--yes", action="store_true", help="Noninteractive destructive confirmation (requires --apply)")
    args = parser.parse_args()
    if os.geteuid() == 0:
        parser.error("run as the affected desktop user, never root or sudo")
    if args.yes and not args.apply:
        parser.error("--yes requires --apply")
    if any(os.environ.get(name) for name in ("FLATPAK_USER_DIR", "FLATPAK_SYSTEM_DIR", "FLATPAK_CONFIG_DIR")):
        parser.error("custom Flatpak environment overrides are unsupported; use the original manager")
    home = Path.home()
    roots = [Path(os.environ.get(var) or str(home / fallback)) for var, fallback in (
        ("XDG_DATA_HOME", ".local/share"), ("XDG_STATE_HOME", ".local/state"),
        ("XDG_CONFIG_HOME", ".config"), ("XDG_CACHE_HOME", ".cache"))]
    for root in [home, *roots]:
        if not root.is_absolute() or root == Path("/") or ".." in root.parts:
            parser.error("unsafe HOME/XDG root")
        ancestors(root)
        if present(root) and (root.is_symlink() or not root.is_dir()):
            parser.error(f"unsafe data root: {root}")
    if any(overlaps(root, home / ".var/app") or root == home or root in home.parents for root in roots):
        parser.error("XDG root overlaps HOME or Flatpak private roots")
    if any(overlaps(left, right) for i, left in enumerate(roots) for right in roots[i + 1:]):
        parser.error("XDG roots must not overlap")
    data, state, config, cache = roots
    keys = list(APPS) if args.app == "all" else [args.app]
    names = {name for key in keys for name in APPS[key][1]}
    old_ids = {APPS[key][0] for key in keys}
    executable = shutil.which("flatpak")
    running(names, executable, old_ids)
    inventory = flatpak_inventory(executable) if executable else []
    targets, locks, removals, blocked, retained = [], [], [], [], []
    for key in keys:
        old_id = APPS[key][0]
        try:
            matching = [item for item in inventory if item[0].split("/")[1] == old_id]
            if any(scope != "user" for _, _, scope in matching):
                raise ValueError("system/custom-installation old Flatpak present; use its original manager first")
            if len(matching) > 1:
                raise ValueError("multiple old Flatpak refs; resolve branches/architectures with original manager first")
            source, lock = source_targets(key, data, state, home)
            targets.extend(source)
            if lock:
                locks.append(lock)
            paths = [config / "NextKde" / ("kos-" + key + ".conf"), cache / "NextKde" / ("kos-" + key)]
            if key == "calendar":
                paths += [data / "kos/pim", config / "NextKde/kos-todo.conf", cache / "NextKde/kos-todo"]
            elif key == "weather":
                paths += [state / "quickshell/kos-weather/standalone-backend"]
            sandbox = home / ".var/app" / old_id
            if present(sandbox) and not executable:
                raise ValueError("Flatpak unavailable: cannot confirm old sandbox installation/writers")
            paths.append(sandbox)
            for path in paths:
                if present(path):
                    targets.append((path, inspect(path)))
                else:
                    print(f"ABSENT {path}")
            removals.extend(matching)
            # A shared command can belong to the new installation: never unlink by name.
            for name in APPS[key][1]:
                found = shutil.which(name)
                if found and not any(Path(found) == path for path, _ in source):
                    retained.append(f"program outside verified old source ownership: {found} (original manager required if old)")
            for relative in sorted(installed_files(key)):
                for prefix in (home / ".local", Path("/usr/local"), Path("/usr")):
                    path = prefix / relative
                    if present(path) and not any(path == item for item, _ in source):
                        retained.append(f"unowned historical/core candidate, not deleted: {path}")
        except (ValueError, OSError) as exc:
            blocked.append(f"{key}: {exc}")
    protected = []
    for key in APPS:
        app_id = "org.nextks." + key
        protected += [data / "nextkde-apps" / app_id, state / "nextkde-apps" / app_id,
                      data / app_id, state / app_id, config / "NextKde" / (app_id + ".conf"),
                      cache / "NextKde" / app_id, home / ".var/app" / app_id]
    protected += [data / "nextkde-apps/listenfree", state / "nextkde-apps/listenfree",
                  state / "quickshell/shell-data-service", config / "NextKde/KosApplications.conf"]
    unique = {}
    for path, expected in targets:
        if any(overlaps(path, p) for p in protected):
            blocked.append(f"overlaps protected path: {path}")
        if any(path != other and overlaps(path, other) for other in unique):
            blocked.append(f"overlapping cleanup targets: {path}")
        unique[path] = expected
    targets = list(unique.items())
    for path, _ in targets:
        print(f"DELETE {path}")
    for ref, commit, _ in removals:
        print(f"UNINSTALL user {ref} @ {commit}")
    print("KEEP shared NextKde/KosApplications.conf and core weather state: not exclusively owned by these apps")
    for reason in dict.fromkeys(retained):
        print("RETAINED " + reason)
    for reason in blocked:
        print("BLOCKED " + reason)
    if blocked:
        print("Nothing changed: resolve blocked ownership before applying.")
        return 2
    if not args.apply:
        print("PREVIEW ONLY. Nothing changed. --apply deletes listed legacy programs AND personal data irreversibly.")
        return 0
    if not args.yes:
        if not sys.stdin.isatty():
            parser.error("noninteractive deletion requires --apply --yes")
        if input("Type DELETE LEGACY APPS AND DATA to confirm: ") != "DELETE LEGACY APPS AND DATA":
            return 130
    descriptors = []
    try:
        for lock in locks:
            fd = os.open(lock, os.O_RDONLY | os.O_NOFOLLOW)
            descriptors.append(fd)
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        running(names, executable, old_ids)
        for path, expected in targets:
            if inspect(path) != expected:
                raise ValueError(f"target changed after preview: {path}")
        if executable and flatpak_inventory(executable) != inventory:
            raise ValueError("Flatpak inventory changed after preview")
        for ref, commit, scope in removals:
            running(names, executable, old_ids)
            current = flatpak_inventory(executable)
            if [item for item in current if item[0].split("/")[1] == ref.split("/")[1]] != [(ref, commit, scope)]:
                raise ValueError(f"old Flatpak identity changed before uninstall: {ref}")
            subprocess.run([executable, "--user", "uninstall", "--app", "--no-related",
                            "--noninteractive", "--assumeyes", "--", ref], check=True, timeout=45)
            if any(item[0] == ref for item in flatpak_inventory(executable)):
                raise ValueError(f"Flatpak removal could not be confirmed: {ref}")
        running(names, executable, old_ids)
        for path, expected in targets:
            remove(path, expected)
            print(f"REMOVED {path}")
    finally:
        for fd in descriptors:
            os.close(fd)
    print("Listed targets removed. Shared/unowned/system items were retained; this is not a full-machine cleanup claim.")
    return 3 if retained else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.SubprocessError, RecursionError) as error:
        print(f"STOPPED: {error}. Removal may be partial; inspect reported paths before retrying.", file=sys.stderr)
        sys.exit(2)
