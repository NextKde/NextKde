# Development and review for AI contributors

[简体中文](Development.zh-CN.md)

[Documentation](README.md) · [Contribution rules](../CONTRIBUTING.md)

All commands that build, test, launch or diagnose the project below run **inside a dedicated VM
or hosted CI**. Never run them on the maintainer workstation. Host source edits and Git are allowed.

## Choose the correct runtime

From the repository root in the VM:

```sh
./tools/kosctl install
./tools/kosctl start
./tools/kosctl dev
```

`install` deploys the current checkout and enables units; `start` restarts installed services.
KWin binaries require logout/login or reboot. Do not hot-reload plugins.
`dev` runs source Shell QML using installed platform/data services; it does not rebuild those
daemons. Reinstall and restart after native/service changes. `run` previews the source UI.
For Settings development use `./tools/kosctl dev settings`; verify the printed executable, QML,
Shell and module paths. A desktop-menu Settings launch normally serves the installed session.
Do not combine mutually exclusive Quickshell `-c` and `-p` arguments.
Both `QML_IMPORT_PATH` and `QML2_IMPORT_PATH` must select the matching native modules when
launching manually. Never report a source Shell with stale native services as final acceptance.

## Verification gates

In the VM/CI:

```sh
python3 platform/tests/test_contract.py
python3 tools/check-docs.py
./tools/run-tests.sh                 # data layer only by default
./tools/run-tests.sh --layer platform
./tools/run-tests.sh --layer logic
./tools/run-tests.sh --layer headless
./tools/run-tests.sh --all           # includes graphical UI; real VM session
```

Check whitespace with `git diff --check`. CI uses the same CTest registrations but builds once
and runs data/platform/logic/headless groups separately. `.github/ci-tests.json` guards required
registration and complete result reporting. Headless UI runs offscreen in CI; compositor flows
still need a VM. Read [.github/workflows/tests.yml](../.github/workflows/tests.yml) for exact gates.

Three full SDK jobs build/link plugins and Glass for KWin 6.6, 6.7 and 6.8, run offline regressions,
and check official API headers. Missing GL contexts can skip GPU readback in containers; run those
checks in the VM and record the result. Build compatibility is separate from real desktop loading.
Record actual test counts instead of copying a historical count from an old report.

## Optional apps

Core installation excludes the independent apps. In the VM, test the **actual default entry point**:

```sh
./tools/kosctl install apps
cmake --preset apps-dev
cmake --build --preset apps-dev
ctest --preset apps-dev
```

The bundle selects Calendar, Calculator, Todo and Weather, with ListenFree OFF even if an old
CMake cache enabled it. Verify no audio SDK creation or MIME/legacy-player migration and no
partial replacement of core Settings. Also check an app-only prefix without core Settings.
Qt 6.5+, compatible KF6 and Go 1.26+ are the standard bundle baseline.
`./tools/kosctl install apps --with-listenfree` explicitly enables the audio SDK and additional
[ListenFree dependencies](../apps/listenfree/packaging/linux/README.md), including Qt 6.10+.
See [apps](../apps/README.md) for individual presets and registration.

## Review checklist

1. Confirm source ownership, protocol/config compatibility, bounded retries, cancellation and
   disconnected-service behavior in the relevant architecture document.
2. Check QML uses service adapters and portable apps never import Quickshell modules.
3. Check new runtime assets, qmldir entries, install/packaging paths and state migrations.
4. Run relevant automated coverage in VM/CI; use a real VM Shell for changed visual interactions.
   Confirm `Configuration Loaded`, exercise changed flows and inspect QML/runtime errors.
   Stop only the instance you started and restore normal services.
5. Review the staged tree including new files, documentation links/translations, licenses,
   and evidence claims. Keep temporary logs/screenshots outside the committed documentation.

For a release, additionally follow [exact-commit VM acceptance](Releasing.md).
