#!/usr/bin/env python3
"""Select a source release and report installed/source identities (stdlib only)."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

VERSION_PATTERN = r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?"
ROOT = Path(__file__).resolve().parent.parent


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True, stderr=subprocess.DEVNULL).strip()


def identity(root):
    version = (root / "VERSION").read_text().strip()
    if not re.fullmatch(VERSION_PATTERN, version):
        raise ValueError("Invalid VERSION file")
    result = {"version": version, "revision": "unknown", "tag": "", "dirty": None}
    try:
        # A source archive inside another checkout must not inherit its identity.
        if Path(git(root, "rev-parse", "--show-toplevel")).resolve() != root.resolve():
            return result
        result["revision"] = git(root, "rev-parse", "HEAD")
        result["dirty"] = bool(git(root, "status", "--porcelain", "--untracked-files=normal"))
        try:
            result["tag"] = git(root, "describe", "--tags", "--exact-match", "--match", "v[0-9]*")
        except subprocess.CalledProcessError:
            pass
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return result


def write_identity(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".release-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(data, stream, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def latest_release(repository):
    match = re.fullmatch(r"(?:https://github\.com/|git@github\.com:)([\w.-]+/[\w.-]+?)(?:\.git)?/?", repository)
    if not match:
        raise ValueError("Automatic stable selection requires a github.com repository; use an explicit vX.Y.Z tag")
    request = urllib.request.Request(
        f"https://api.github.com/repos/{match[1]}/releases/latest",
        headers={"Accept": "application/vnd.github+json", "User-Agent": "NextKDE-source-selector"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            release = json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            raise ValueError("No latest official release is available. To choose development explicitly, use: ./tools/kosctl update main") from error
        raise
    tag = release.get("tag_name", "")
    if release.get("draft") or release.get("prerelease") or not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("Latest release is not a stable vX.Y.Z release; refusing to fall back to main")
    return tag


def select(root, target, repository=None, mirror=None):
    if Path(git(root, "rev-parse", "--show-toplevel")).resolve() != root.resolve():
        raise ValueError("Source selection requires the root of a Git checkout")
    if git(root, "status", "--porcelain", "--untracked-files=normal"):
        raise ValueError("Working tree has local changes or untracked files; save them before switching versions")
    if git(root, "ls-files", "-u"):
        raise ValueError("Resolve the unfinished merge before switching versions")
    for marker in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply", "sequencer"):
        location = Path(git(root, "rev-parse", "--git-path", marker))
        if not location.is_absolute():
            location = root / location
        if location.exists():
            raise ValueError("Finish the in-progress Git operation before switching versions")
    remote = git(root, "remote", "get-url", "origin")
    if repository and remote.rstrip("/").removesuffix(".git") != repository.rstrip("/").removesuffix(".git"):
        raise ValueError("Existing origin differs from --repo; refusing to change repositories")
    if target == "stable":
        target = latest_release(remote)
    if target == "main":
        ref = "refs/heads/main"
    elif re.fullmatch("v" + VERSION_PATTERN, target):
        ref = "refs/tags/" + target
    else:
        raise ValueError("Choose stable, main, or an explicit vX.Y.Z[-rc.N] tag")
    # Fetch the exact remote ref. Never reuse an old FETCH_HEAD after failure,
    # overwrite local tags, reset branches, or silently continue on network errors.
    fetch_args = ["fetch", "--no-tags"]
    # Installer clones are shallow. Keep exact-ref updates shallow too, or a
    # release on another branch can pull discarded screenshot history back in.
    # Existing full developer checkouts keep their complete history.
    if git(root, "rev-parse", "--is-shallow-repository") == "true":
        fetch_args += ["--depth", "1"]
    try:
        subprocess.run(["git", "-C", str(root), *fetch_args, "origin", ref], check=True)
    except subprocess.CalledProcessError:
        if not mirror:
            raise
        if not remote.startswith("https://github.com/") or not mirror.startswith("https://"):
            raise ValueError("Mirror fallback requires HTTPS GitHub origin and HTTPS mirror")
        # A mirror changes transport only; keep origin and release API canonical.
        mirror_url = mirror.rstrip("/") + "/" + remote
        subprocess.run(["git", "-C", str(root), *fetch_args, mirror_url, ref], check=True)
    revision = git(root, "rev-parse", "FETCH_HEAD^{commit}")
    if target != "main":
        version = git(root, "show", revision + ":VERSION")
        if version != target[1:]:
            raise ValueError(f"Tag {target} disagrees with its VERSION file ({version})")
    subprocess.run(["git", "-C", str(root), "checkout", "--detach", revision], check=True)
    print(f"Selected {target}: {revision}")
    print("Source only. Apply with ./tools/kosctl install, then ./tools/kosctl start.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    commands = parser.add_subparsers(dest="command", required=True)
    selection = commands.add_parser("select")
    selection.add_argument("target", nargs="?", default="stable")
    selection.add_argument("--repo")
    selection.add_argument("--mirror")
    report = commands.add_parser("version")
    report.add_argument("--installed", type=Path, required=True)
    stamp = commands.add_parser("stamp")
    stamp.add_argument("destination", type=Path)
    stamp.add_argument("--from-file", type=Path)
    check = commands.add_parser("check-release")
    check.add_argument("tag")
    args = parser.parse_args()
    root = args.root.resolve()
    if args.command == "select":
        select(root, args.target, args.repo, args.mirror)
    elif args.command == "stamp":
        data = json.loads(args.from_file.read_text()) if args.from_file else identity(root)
        write_identity(args.destination, data)
    elif args.command == "check-release":
        data = identity(root)
        if not re.fullmatch("v" + VERSION_PATTERN, args.tag) or args.tag != "v" + data["version"]:
            raise ValueError("Release tag must equal v + VERSION")
        if data["dirty"] is not False or data["revision"] == "unknown":
            raise ValueError("Release requires a clean Git checkout")
        if git(root, "rev-parse", args.tag + "^{commit}") != data["revision"]:
            raise ValueError("Release tag must point at HEAD")
        print(json.dumps(data, indent=2))
    else:
        for label, path in (("Installed", args.installed), ("Source", root / "VERSION")):
            if not path.exists():
                print(f"{label}: unknown (no version record at {path})")
                continue
            data = json.loads(path.read_text()) if label == "Installed" else identity(root)
            dirty = " + local changes" if data.get("dirty") else ""
            print(f"{label}: {data['version']} ({data.get('revision', 'unknown')}){dirty}")
        print("Installed identifies deployed files, not the currently running processes or optional apps.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError, urllib.error.URLError) as error:
        print(f"NextKDE: {error}", file=sys.stderr)
        sys.exit(1)
