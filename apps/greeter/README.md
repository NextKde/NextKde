# KOS Greeter lifecycle prototype

Standalone Quickshell app for T02. Uses the trusted wallpaper host and an independently rendered authentication form. No desktop Shell imports, user themes, resource installation, PAM edits, or display-manager switching.

Dependencies: Python 3, greetd, Quickshell 0.3 Greetd API, KWin Wayland, Qt Quick Controls, installed Plasma Wayland. Node.js is needed for model tests. Run `apps/greeter/bin/kos-greeter-session --check` for the dependency and fixed session allowlist check.

Run `node apps/greeter/tests/lifecycle.test.cjs` and `python3 apps/greeter/tests/ipc.test.py`. The latter uses actual Quickshell with a mock protocol server, covering success, retry, cancellation, disconnect and launch rejection; not PAM. No build is required for this source prototype; packaging and dedicated installation are pending later tasks.

The isolated-seat wrapper refuses an existing graphical session and requires GREETD_SOCK. It is intended only for a disposable VM. It launches a separate KWin with --exit-with-session. Authentication responses are cleared, never explicitly logged, and prompts respect echoResponse. Cancellation waits for backend Inactive; timeout exits the frontend. Animation finishes before launch, and launch acknowledgment immediately exits. Qt/JS field clearing does not promise memory zeroization.

T02 is complete by explicit user acceptance on 2026-10-11; prior missing measurements remain historical records. See [Chinese experiment and recovery instructions](README.zh-CN.md) and [T02 evidence](../../docs/kos-greeter/evidence/T02/REPORT.md). Do not deploy this as the host's display manager.

## T05 身份与认证

AccountsService 只读列表使用 system bus 与 busctl，UID 关联、UserName 认证、RealName 展示；其他用户保留手工登录。仅安全的管理员头像副本可读取，home/缺图/损坏回退默认头像。Python 3 与 busctl 为列表依赖，Pillow 为可选头像依赖；缺失仍保留手工登录。支持多轮 secret/visible/info/error、取消返回列表和键盘焦点恢复。运行 `python3 apps/greeter/tests/accounts.test.py` 和原 IPC/model 测试。T05 已由用户验收完成，见 docs/kos-greeter/evidence/T05/REPORT.md。

用户明确要求的临时测试/回滚脚本已提供：`tools/test-greeter.py` 和 `tools/rollback-greeter.py`。它们使用独立 runtime 服务与定时回滚，不更改持久登录配置。本次没有实际切换。用法和完整回滚边界见 [临时测试说明](TEMPORARY-TEST.zh-CN.md)；该显式实验入口补充原隔离 VM 方案，用户已验收关闭 T01–T06，物理测量边界见各任务验收记录。

## T06 output controller

`companion/outputs.py` validates bounded machine display policy and plans startup/hotplug fallback without applying settings. Run `python3 apps/greeter/tests/outputs.test.py`. Contract and JSON Schema: `docs/kos-greeter/contracts/machine-outputs.md`. A read-only example:

```
python3 apps/greeter/companion/outputs.py docs/kos-greeter/evidence/T06/machine-output.example.json docs/kos-greeter/evidence/T06/inventory.json
```

T06 is complete by user acceptance on 2026-10-11. companion/display.py integrates KScreen atomic output requests, effective readback and one bounded fallback; shell.qml follows the active output and preserves authentication state. Isolated sessions enable application; ordinary previews observe only. Real virtual KWin tests cover output changes and window bounds. Physical black-frame/scanout measurements are not claimed.

## T07 standalone wallpaper host

Run `apps/greeter/bin/kos-greeter-wallpaper` only inside a disposable/nested Wayland session. It creates one background-layer window per enabled output without desktop services. Optional administrator-provided `KOS_GREETER_WALLPAPER_UID` chooses a published public copy from the fixed root-owned `/var/lib/kos/greeter/display`; absent/invalid resources use the built-in solid background. This does not install or enable a login manager. The authentication frontend uses the same source/host and adds backgrounds on secondary outputs.

Python 3 and Pillow are required for public image validation; missing helpers fail back to the default. Shared source assets are linked at `wallpapers`; packaging must preserve or copy this trusted bundle inside the app root. Five built-in themes are parameterized with neutral inputs and verified against `companion/theme-files.json` before execution; manifest-provided QML is never accepted. Theme upgrades require reviewing and regenerating that fixed hash list.

Tests: `python3 apps/greeter/tests/wallpaper.test.py` and `python3 apps/greeter/tests/wallpaper-render.test.py`. The latter launches its own virtual KWin, compares actual Qt renders against an independent offline Image fixture at scales 1 and 1.5, injects failures and exercises output disable/restore. It never switches the host compositor. Details and event semantics: [WallpaperHost contract](../../docs/kos-greeter/contracts/wallpaper-host.md) and [T07 evidence](../../docs/kos-greeter/evidence/T07/REPORT.md). Installation remains the T14 packaging scope.

Temporary test sessions now publish the calling account's explicitly authorized current KOS image and fit before switching. The ordinary `tools/test-greeter.py --start` command needs no image path for an opted-in account. The initial user list consumes the root-owned temporary T03 copy; other account selections remain UID scoped. See [automatic KOS wallpaper and revoke instructions](TEMPORARY-TEST.zh-CN.md). This is preparation for each temporary test, not installation of a persistent publication broker.

## T08 visual exit

Upper date/clock and lower identity forms use translucent rounded controls with a plain-text material fallback. `KOS_GREETER_EXIT_MS` clamps the suggested exit duration to 180–280ms (default 220); `KOS_GREETER_REDUCED_MOTION=1` requests a 1ms exit. Authentication success wipes inputs, disables controls, fades UI and shade, waits for a newly requested frame submission, then launches. A missing frame times out rather than bypassing the gate. Launch rejection cancels and recreates authentication; connection errors briefly show a diagnostic before the host restarts the frontend.

Run `python3 apps/greeter/tests/visual.test.py` for synthetic empty-input Qt storyboard/video captures and actual virtual-compositor mock IPC tests. No host display-manager switching occurs. Full Tahoe A15 reference matching and physical presentation remain unverified; see [T08 evidence](../../docs/kos-greeter/evidence/T08/REPORT.md).

### Direct password entry

A single account starts authentication automatically; selecting an account starts its PAM conversation immediately. The password field receives focus and Enter submits it. Debug and Continue buttons are removed. Authentication failure rebuilds the backend conversation after Inactive, allowing another password attempt; multi-user selection and Other user remain available. Escape returns to the account list. The updated empty-input storyboard and mock IPC evidence live in `docs/kos-greeter/evidence/T08/interaction-update/REPORT.md`; the original T08 evidence is a historical snapshot.

T09: `bin/kos-user-session` is the fixed authenticated Plasma wrapper. See [session handoff contract](../../docs/kos-greeter/contracts/session-handoff.md) and [isolated evidence](../../docs/kos-greeter/evidence/T09/REPORT.md). Run `python3 apps/greeter/tests/handoff.test.py` from the repository root. No persistent installation or manager switch is performed.

### Early desktop Cover (T10)

The authenticated wrapper now starts a bounded Cover supervisor alongside Plasma. It waits for the user KWin socket to accept connections and starts independent per-output static overlays without platform/data or Shell readiness dependencies. Cover exits after 15 seconds; the supervisor enforces a 25-second total deadline, without restart. T11 now connects matching `cover describe` / `cover reveal` IPC gates to formal wallpaper frame readiness and bar/Dock entry; `cover abort` provides manual recovery. Full production A03/A10 and cold/warm login recordings remain blocked; see [T11 evidence](../../docs/kos-greeter/evidence/T11/REPORT.md). See [contract](../../docs/kos-greeter/contracts/early-cover.md) and [isolated evidence](../../docs/kos-greeter/evidence/T10/REPORT.md). No system services were installed/enabled; physical presentation and cross-session black frames remain unmeasured.

### Persistent installation scripts

User-requested standalone install/rollback scripts are now available: `tools/install-greeter.sh` builds the QML/Python bundle and selects greetd for the next boot; `tools/rollback-installed-greeter.sh` restores the saved manager/configuration. Immediate switching requires a text TTY and `--activate-now`. See [installation, rollback and wallpaper expiry instructions](INSTALL.zh-CN.md). These scripts have isolated transaction tests; no host deployment was performed. They are separate from the temporary test rollback.
