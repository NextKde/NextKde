#!/usr/bin/env python3
"""Exercise layout takeover and exact restoration with fake KDE executables."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("configure", ROOT / "shell/desktop/modules/switcher/configure.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ConfigureTests(unittest.TestCase):
    def test_roundtrip(self):
        for original in ["__kos_absent__", "thumbnail_grid", "org.kde.breeze.desktop"]:
            with self.subTest(original=original), tempfile.TemporaryDirectory() as directory:
                current = [original]
                calls = []
                def run(*args):
                    calls.append(args)
                    if args[0] == "kreadconfig6":
                        return current[0]
                    if args[0] == "kwriteconfig6":
                        current[0] = "__kos_absent__" if args[-1] == "--delete" else args[-1]
                    return ""
                state = Path(directory) / "native.json"
                with patch.object(module, "run", run), patch.dict(module.os.environ, {"XDG_DATA_HOME": directory}):
                    module.configure(False, directory, state)
                    self.assertEqual(current[0], original)
                    self.assertEqual(len(calls), 1, "default off must only read")
                    module.configure(True, directory, state)
                    module.configure(True, directory, state)
                    self.assertEqual(current[0], "kos-glass")
                    module.configure(False, directory, state)
                    self.assertEqual(current[0], original)
                    self.assertFalse(state.exists())
                    self.assertFalse(any("kglobal" in str(call) for call in calls))

    def test_respects_later_native_choice(self):
        with tempfile.TemporaryDirectory() as directory:
            state = Path(directory) / "native.json"
            state.write_text('{"layout":"compact"}')
            with patch.object(module, "run", return_value="sidebar") as run:
                module.configure(False, directory, state)
                self.assertEqual(run.call_count, 1)
                self.assertFalse(state.exists())


if __name__ == "__main__":
    unittest.main()
