#!/usr/bin/env python3
"""Run only inside a private bwrap + dbus-run-session namespace; virtual output only."""
import argparse
import array
import secrets
import os
import pathlib
import select
import socket
import stat
import subprocess
import tempfile
import time


def trusted_png(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode) or st.st_uid not in (0, 65534) or st.st_nlink != 1 or st.st_mode & 0o022 or not 0 < st.st_size <= 16 * 1024 * 1024:
        os.close(fd)
        raise ValueError("PNG must be a root-owned, non-writable published regular file")
    return fd


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kwin", required=True, type=pathlib.Path)
    parser.add_argument("--session", required=True, type=pathlib.Path)
    parser.add_argument("--png", required=True)
    parser.add_argument("--case", choices=("normal", "timeout", "cancel", "bootstrap", "nonce", "scm", "rejected", "revoke", "confirm-expired"), default="normal")
    args = parser.parse_args()
    if not os.environ.get("KOS_ISOLATED_HANDOFF_FIXTURE") or any(pathlib.Path("/dev/dri").glob("card*")):
        raise RuntimeError("use run-fixture.sh; physical DRM devices must be hidden")
    if os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY") or os.environ.get("GREETD_SOCK"):
        raise RuntimeError("host display/auth socket environment must be absent")
    runtime = pathlib.Path(os.environ["XDG_RUNTIME_DIR"])
    fifo = runtime / "fixture-exit.fifo"
    os.mkfifo(fifo, 0o600)
    fifo_fd = os.open(fifo, os.O_RDWR | os.O_NONBLOCK | os.O_CLOEXEC)
    png_fd = trusted_png(args.png)
    coordinator, compositor = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    import sys
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / "companion"))
    from greeter_config import prepare
    env = dict(prepare(os.environ), KOS_KWIN_BOOTSTRAP_FD=str(png_fd), KWIN_COMPOSE="Q", QT_QPA_PLATFORM="wayland", QT_QPA_PLATFORMTHEME="", GTK_USE_PORTAL="0", QT_NO_XDG_DESKTOP_PORTAL="1", QT_FORCE_STDERR_LOGGING="1", QT_LOGGING_TO_CONSOLE="1", QT_LOGGING_RULES="*.info=true;*.warning=true")
    inherited = [png_fd]
    if args.case != "bootstrap":
        env["KOS_KWIN_HANDOFF_CONTROL_FD"] = str(compositor.fileno())
        inherited.append(compositor.fileno())
    cmd = [str(args.kwin), "--virtual", "--width", "800", "--height", "600", "--no-lockscreen", "--no-global-shortcuts",
           "--output-count", "2", "--socket", "kos-fixture-wayland", "--exit-with-session", f"{args.session} {fifo}"]
    log = tempfile.TemporaryFile(mode="w+t")
    child = subprocess.Popen(cmd, env=env, pass_fds=inherited, stdout=log, stderr=subprocess.STDOUT)
    compositor.close()
    os.close(png_fd)
    try:
        deadline = time.monotonic() + 15
        while not (runtime / "kos-fixture-wayland").exists():
            if child.poll() is not None or time.monotonic() >= deadline:
                raise RuntimeError("virtual KWin did not start")
            time.sleep(0.05)
        time.sleep(0.5)  # Allow the synthetic window to map, outside the handoff deadline.
        if args.case == "bootstrap":
            time.sleep(16)
        else:
            nonce = secrets.token_hex(16).encode() if args.case in ("nonce", "revoke", "confirm-expired") else b""
            if args.case in ("nonce", "confirm-expired"):
                coordinator.send(b"ARM:default:" + nonce)
            elif args.case in ("scm", "rejected", "revoke", "confirm-expired"):
                image_fd = trusted_png(args.png)
                rights = array.array("i", [image_fd, image_fd] if args.case == "rejected" else [image_fd])
                coordinator.sendmsg([b"ARM:cover:0:" + nonce if args.case == "revoke" else b"ARM:contain"], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, rights)])
                os.close(image_fd)
            else:
                coordinator.send(b"ARM")
            coordinator.settimeout(3.5)
            answer = coordinator.recv(96)
            expected = b"REJECTED" if args.case == "rejected" else b"PRESENTED" + (b":" + nonce if nonce else b"")
            if answer != expected:
                raise RuntimeError(f"pure background was not presented: {answer!r}")
            print("malformed multi-FD packet rejected" if args.case == "rejected" else "all virtual outputs reported background presentation", flush=True)
            if args.case in ("nonce", "confirm-expired"):
                if args.case == "confirm-expired": time.sleep(2.1)
                coordinator.send(b"CONFIRM:" + nonce)
                expected_confirmation = (b"EXPIRED:" if args.case == "confirm-expired" else b"READY:") + nonce
                if coordinator.recv(96) != expected_confirmation:
                    raise RuntimeError("post-Prepare nonce confirmation gate failed")
            if args.case == "revoke":
                pathlib.Path("/var/lib/kos/greeter/display/0/manifest.json").unlink()
                time.sleep(1.2)
            if args.case == "timeout":
                answer = coordinator.recv(32)
                if answer != b"TIMEOUT":
                    raise RuntimeError(f"timeout recovery missing: {answer!r}")
            elif args.case == "cancel":
                coordinator.send(b"CANCEL")
                if coordinator.recv(96) != b"CANCELLED":
                    raise RuntimeError("explicit cancellation was not acknowledged")
        os.write(fifo_fd, b"X")
        code = child.wait(timeout=5)
        if code != 0:
            raise RuntimeError(f"KWin/session exited {code}")
        log.seek(0)
        output = log.read()
        if args.case == "revoke" and "KOS_DRM_HANDOFF BootstrapRevoked" not in output:
            raise RuntimeError("publication withdrawal did not revoke KWin's private background")
        if args.case == "bootstrap" and "KOS_DRM_HANDOFF BootstrapTimeout" not in output:
            raise RuntimeError("new-compositor bootstrap did not expire")
        preserved = "KOS_DRM_HANDOFF NormalSessionExit" in output
        if preserved != (args.case in ("normal", "nonce", "scm")):
            print(output, file=sys.stderr)
            raise RuntimeError("normal-exit retention gate had the wrong state")
        print(output, end="", flush=True)
        print(f"fixture {args.case}: PASS (virtual presentation only; no physical DRM/VT claim)", flush=True)
    finally:
        if child.poll() is not None:
            log.seek(0)
            if child.returncode:
                print(log.read(), file=sys.stderr)
        coordinator.close()
        os.close(fifo_fd)
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        fifo.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
