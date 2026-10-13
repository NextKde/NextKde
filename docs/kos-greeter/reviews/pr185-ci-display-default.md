# PR185：CI 夹具与通用显示默认静态审查

日期：2026-10-13。执行者：`/root`。独立只读审查代理：`/root/review_ci_display`。
基线：`60934dc82e52b554d60595426397b8b6232e874d`。工作分支：`codex/pr185-ci-display-fix`。

## 范围与结论

以下九个文件：补齐 WallpaperService 新信号的 Node 夹具；默认输出策略移除个人机器覆盖，validator/schema 接受空清单，故障策略使用相同空清单；原高刷测试改用既有机器样例，新增通用策略用例，并同步配置说明。

独立审查未发现 P0/P1/P2 阻断问题。信号计数与产品调用一致；默认配置、validator、schema 一致；空策略沿用推荐/当前模式和有界回退；原高刷测试覆盖保留。未修改认证、PAM、服务切换或回滚实现。

审查覆盖最终差异、输出规划/控制器、T06 夹具、WallpaperService、打包清单及上下游约束。没有发现待修复问题，故没有问题驱动的实现修订。VM证据补齐后，同一独立代理复审安装说明更新、此记录及实际测试/复制日志：结论与证据一致，未发现P0/P1/P2问题，复审通过。该结论不代表完整CI、真实模式切换或登录恢复验收通过。

## 验证边界

遵循用户要求，本机只读取源码与差异，没有执行测试、编译、verify 或启动 Quickshell/KWin。用户确认虚拟机已打开后，通过 QEMU Guest Agent 在运行中的 `kubuntu` 虚拟机执行以下回归；虚拟机为 Ubuntu 26.10 开发版本，Python 3.14.4，Node v24.19.0（本轮在虚拟机安装）。

被测源码与三个 T06 夹具复制到虚拟机临时目录 `/tmp/nextkde-pr185-kzhms25a`，在客体内计算的源码 SHA256 与下列被审实现摘要一致，没有导入或执行宿主项目代码。

| 虚拟机执行命令 | 结果 |
| --- | --- |
| `node shell/desktop/modules/wallpaper/test_theme_wallpaper_state.mjs` | exit 0，原有主题选择/恢复与新增信号断言通过 |
| `python3 apps/greeter/tests/outputs.test.py` | 9项，OK，exit 0 |
| `python3 apps/greeter/tests/display.test.py` | 10项，OK，exit 0 |

本批代码及上述回归已完成；远端 PR 尚未更新，完整 CI 尚未重新验证，不能宣称 CI 全绿。控制器测试采用假 KScreen，未执行实际模式切换、登录恢复或物理显示器验收。

## 被审文件 SHA256

```text
79619fbdde4c20ad4a3cde24d33cd066acf253dc5097118d689a3f78d16f1100  apps/greeter/INSTALL.zh-CN.md
960d903697d4e27a0f0a16521eae9eb89f8c51d9a282f21576dbda8308828749  apps/greeter/companion/display.py
7f698ed3799c7ab6fa6e5b3cf752caebe15710e32aafe452c8758bb791c74f4c  apps/greeter/companion/outputs.py
ac0422ad7a1db2a11834f8e3033e18aafa89648571d3ccb63805591be5bfa367  apps/greeter/config/outputs.json
57e48bd7a4c6a976b519b3939462c44dbf8adbdc4a14a735aaf36331cc611829  apps/greeter/tests/display.test.py
23794f538681e30969711111bdd55f4aa9454c94efb035150d1f487cf47f2a91  apps/greeter/tests/outputs.test.py
c915c0559e1ac0126a9a90a636d9fb5a7e2abe13d6df2f6693c148c3f5f006ad  docs/kos-greeter/contracts/machine-outputs.md
a9c6def14055a0486e1df729635c6f74ac54a204aac9038a503f65c0d6b3be5a  docs/kos-greeter/contracts/machine-outputs.schema.json
f99c3503b5dc75236829ec429b52c8121fc73a72526191925795b10605fb8e2c  shell/desktop/modules/wallpaper/test_theme_wallpaper_state.mjs
```
