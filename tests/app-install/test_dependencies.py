#!/usr/bin/env python3
"""Guard core cache migration and independent-app ownership. VM/CI only."""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DependencyMigrationTests(unittest.TestCase):
    def test_core_upgrade_configure_clears_retired_app_cache_and_invalidates_stamp(self):
        source = (ROOT / "tools/kosctl").read_text()
        functions = []
        for name in ("configure_if_needed", "configure_build"):
            match = re.search(r"^" + name + r"\(\) \{.*?^\}", source, re.M | re.S)
            self.assertIsNotNone(match)
            functions.append(match.group())
        temporary_root = ROOT / "tmp" / "app-cache-migration"
        temporary_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temporary_root) as directory:
            build = Path(directory)
            (build / "CMakeCache.txt").write_text("# Existing core cache\n")
            stamp = build / "kos-configure-inputs"
            stamp.write_text("old configure inputs without app migration\n")
            script = "\n".join(functions) + r'''
project_dir="$PROJECT"
build_dir="$BUILD"
kwin_system_prefix=/usr
spatial_forced() { return 1; }
spatial_requested() { return 1; }
prepare_cmake_build_dir() { :; }
cmake() { printf '%s\n' "$@" >> "$BUILD/configure-args"; }
configure_build
configure_build
'''
            result = subprocess.run(["bash", "-euc", script], capture_output=True, text=True,
                                    env={**os.environ, "PROJECT": str(ROOT), "BUILD": str(build)})
            self.assertEqual(result.returncode, 0, result.stderr)
            args = (build / "configure-args").read_text().splitlines()
            self.assertEqual(args.count("-S"), 1, "new inputs configure once, unchanged stamp skips next configure")
            for app in ("CALENDAR", "TODO", "WEATHER", "LISTENFREE", "CALCULATOR"):
                key = "KOS_BUILD_" + app
                self.assertIn(key, args)
                self.assertEqual(args[args.index(key) - 1], "-U")
                self.assertIn("-U " + key, stamp.read_text())
            self.assertIn("-DBUILD_TESTING=OFF", args)

    def test_test_runner_clears_the_same_retired_switches(self):
        source = (ROOT / "tools/run-tests.sh").read_text()
        configure = re.search(r"^cmake -S .*?(?=\n\n)", source, re.M | re.S).group()
        for app in ("CALENDAR", "TODO", "WEATHER", "LISTENFREE", "CALCULATOR"):
            self.assertIn("-U KOS_BUILD_" + app, configure)
        self.assertIn("-DBUILD_TESTING=ON", configure)

    def test_core_purge_preserves_independent_app_ownership(self):
        # Source contract only: never source/execute purge, even with --dry-run.
        source = (ROOT / "tools/maintenance/purge-kos.sh").read_text()
        for external in ("kos-calendar", "kos-todo", "kos-weather", "kos-pim-service",
                         "kos-music", "listenfree", "KOS_INSTALL_PREFIX", "KOS_APPS_BUILD_DIR"):
            self.assertNotIn(external, source)
        for unsafe_target in ('"$data_dir/kos"', '"$prefix/share/kos"',
                              '"$config_dir/NextKde/KosApplications.conf"\n    "$apps_prefix'):
            self.assertNotIn(unsafe_target, source)
        self.assertIn('kos-platform|kos-ai-worker|kos-data-service|kos-settings)', source)
        self.assertIn('protected_app_roots=("$data_dir/nextkde-apps" "$state_dir/nextkde-apps"', source)
        self.assertIn('"$data_dir/kos/pim" "$config_dir/NextKde/KosApplications.conf"', source)
        self.assertIn('resolved=$(realpath -m -- "$target")', source)
        self.assertIn('lexical=$(realpath -ms -- "$target")', source)
        self.assertIn('"$protected/" == "$candidate/"*', source)
        self.assertLess(source.index("protected_app_roots="), source.index("# --- scan what is actually present ---"))
        self.assertIn('"$unit_dir/kos-shell.service"', source)
        self.assertIn('"$unit_dir/kos-platform.service"', source)
        self.assertIn('"$unit_dir/kos-data.service"', source)


if __name__ == "__main__":
    unittest.main()
