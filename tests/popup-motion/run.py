import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


REPO = Path(__file__).resolve().parents[2]


def run():
    with tempfile.TemporaryDirectory(prefix="kos-popup-motion-") as directory:
        root = Path(directory)
        runtime = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
        wayland = os.environ.get("WAYLAND_DISPLAY", "wayland-0")
        for name in ["config", "state", "runtime"]:
            (root / name).mkdir(mode=0o700)
        (root / "runtime" / wayland).symlink_to(runtime / wayland)
        for name in ["desktop", "Kos", "shared"]:
            (root / name).symlink_to(REPO / "shell" / name, target_is_directory=True)
        shutil.copy(Path(__file__).with_name("shell.qml"), root / "shell.qml")
        env = dict(os.environ, XDG_CONFIG_HOME=str(root / "config"),
                   XDG_STATE_HOME=str(root / "state"), XDG_RUNTIME_DIR=str(root / "runtime"),
                   KOS_PLATFORM_SOCKET=str(root / "no-platform.sock"),
                   KOS_DATA_SOCKET=str(root / "no-data.sock"), QT_QPA_PLATFORM="wayland")
        try:
            result = subprocess.run(["quickshell", "--path", str(root), "--no-color"],
                                    env=env, capture_output=True, text=True, timeout=30)
        except subprocess.TimeoutExpired as error:
            raise AssertionError((error.stdout or b"").decode(errors="replace")
                                 + (error.stderr or b"").decode(errors="replace")) from error
        output = result.stdout + result.stderr
        assert result.returncode == 0 and "POPUP_MOTION_PASS" in output, output
        assert not re.search(
            r"POPUP_MOTION_FAIL|ReferenceError|TypeError|Cannot assign|Unable to assign|"
            r"is not a type|Binding loop|is not a function", output), output
        print("PASS: Control Center navigation, confirmation, close/reopen; popup input lifetime; "
              "menu navigation; launcher exit; transformed blur geometry; stable navigation glass; "
              "Dock info backdrop; card content routing; launcher panel geometry in six presentations")


if __name__ == "__main__":
    run()
