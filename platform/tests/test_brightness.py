#!/usr/bin/env python3
"""Integration tests for kos-platform brightness IPC endpoints."""

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def find_bin() -> Path:
    env_bin = os.environ.get("KOS_PLATFORM_BIN")
    if env_bin and Path(env_bin).is_file():
        return Path(env_bin)
    for candidate in [
        ROOT / "build/platform/kos-platform",
        ROOT / ".build/platform/kos-platform",
        Path.home() / ".local/libexec/kos-platform",
    ]:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return ROOT / "build/platform/kos-platform"


BIN_PATH = find_bin()


def wait_for_socket(sock_path: Path, timeout: float = 5.0) -> None:
    start = time.monotonic()
    while time.monotonic() - start < timeout:
        if sock_path.exists():
            try:
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
                    s.connect(str(sock_path))
                    return
            except (ConnectionRefusedError, FileNotFoundError):
                pass
        time.sleep(0.05)
    raise TimeoutError(f"Socket {sock_path} did not become ready within {timeout}s")


def send_ipc(sock_path: Path, req: dict) -> dict:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(str(sock_path))
        payload = (json.dumps(req) + "\n").encode("utf-8")
        s.sendall(payload)
        data = bytearray()
        while b"\n" not in data:
            chunk = s.recv(4096)
            if not chunk:
                break
            data.extend(chunk)
        return json.loads(data.decode("utf-8").strip())


def test_brightness_ipc() -> None:
    if not BIN_PATH.is_file():
        # Try building if in dev tree
        build_dir = ROOT / "build"
        if (build_dir / "CMakeCache.txt").exists():
            subprocess.run(["cmake", "--build", str(build_dir), "--target", "kos-platform", "-j4"], check=True)
        elif not BIN_PATH.exists():
            print("kos-platform binary not found, skipping IPC test")
            return

    temp_dir = Path(tempfile.mkdtemp(prefix="kos-brightness-test-"))
    sock_path = temp_dir / "test-platform.sock"

    env = os.environ.copy()
    env["KOS_PLATFORM_SOCKET"] = str(sock_path)
    env["KOS_PLATFORM_NO_TRAY"] = "1"

    proc = subprocess.Popen(
        [str(BIN_PATH), "daemon"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    try:
        wait_for_socket(sock_path)

        # 1. Test display.brightness.get
        get_req = {
            "version": 1,
            "requestId": "req-bright-get-1",
            "operation": "display.brightness.get",
            "payload": {},
        }
        res_get = send_ipc(sock_path, get_req)
        assert res_get.get("ok") is True, f"display.brightness.get failed: {res_get}"
        assert res_get.get("requestId") == "req-bright-get-1"
        result = res_get.get("result", {})
        assert "available" in result, f"Expected 'available' key in result: {result}"
        print(f"display.brightness.get result: {result}")

        if result.get("available"):
            assert "percent" in result
            assert 0 <= result["percent"] <= 100
            assert "device" in result
            orig_percent = result["percent"]

            # 2. Test display.brightness.set via payload
            target_percent = 85 if orig_percent != 85 else 90
            set_req = {
                "version": 1,
                "requestId": "req-bright-set-1",
                "operation": "display.brightness.set",
                "payload": {"percent": target_percent},
            }
            res_set = send_ipc(sock_path, set_req)
            assert res_set.get("ok") is True, f"display.brightness.set failed: {res_set}"
            assert res_set.get("result", {}).get("percent") == target_percent

            # 3. Test display.brightness.set top-level fallback parameter
            restore_req = {
                "version": 1,
                "requestId": "req-bright-set-2",
                "operation": "display.brightness.set",
                "percent": orig_percent,
            }
            res_restore = send_ipc(sock_path, restore_req)
            assert res_restore.get("ok") is True, f"display.brightness.set restore failed: {res_restore}"
            assert res_restore.get("result", {}).get("percent") == orig_percent
            print(f"display.brightness.set verified and restored to {orig_percent}%")

            # 4. Test bounds clamping (<0 and >100)
            clamp_low_req = {
                "version": 1,
                "requestId": "req-clamp-low",
                "operation": "display.brightness.set",
                "payload": {"percent": -20},
            }
            res_low = send_ipc(sock_path, clamp_low_req)
            assert res_low.get("ok") is True
            assert res_low.get("result", {}).get("percent") == 0

            clamp_high_req = {
                "version": 1,
                "requestId": "req-clamp-high",
                "operation": "display.brightness.set",
                "payload": {"percent": 150},
            }
            res_high = send_ipc(sock_path, clamp_high_req)
            assert res_high.get("ok") is True
            assert res_high.get("result", {}).get("percent") == 100

            # Restore original
            send_ipc(sock_path, {"version": 1, "requestId": "req-restore-final", "operation": "display.brightness.set", "payload": {"percent": orig_percent}})
            print("bounds clamping verified")

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        shutil.rmtree(temp_dir, ignore_errors=True)


def test_seat1_ipc() -> None:
    if not BIN_PATH.is_file():
        return

    temp_dir = Path(tempfile.mkdtemp(prefix="kos-brightness-seat1-"))
    sock_path = temp_dir / "test-platform-seat1.sock"

    env = os.environ.copy()
    env["KOS_PLATFORM_SOCKET"] = str(sock_path)
    env["KOS_PLATFORM_NO_TRAY"] = "1"
    env["XDG_SEAT"] = "seat1"

    proc = subprocess.Popen(
        [str(BIN_PATH), "daemon"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    try:
        wait_for_socket(sock_path)
        get_req = {
            "version": 1,
            "requestId": "req-seat1-get",
            "operation": "display.brightness.get",
            "payload": {},
        }
        res_get = send_ipc(sock_path, get_req)
        assert res_get.get("ok") is True
        result = res_get.get("result", {})
        assert "available" in result
        print(f"seat1 display.brightness.get result: {result}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    test_brightness_ipc()
    test_seat1_ipc()
    print("all brightness ipc tests passed successfully")
