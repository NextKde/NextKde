# T11 执行记录

日期：2026-10-12。分支：`codex/notification-center-stacks`。执行者：主代理。源码为未提交工作区，最终摘要见 `SHA256SUMS`，基线见 `BASELINE`。既有用户改动保留；未部署、未切换显示管理器/PAM/系统服务，现有桌面不重启。

## 实现及环境

就绪协议、正式静态字节核对、输出帧门控、活动屏 bar/Dock 门控、一次入场过渡抑制、accepted 回执、280ms 揭幕与独立超时已实现。详细边界见 `../../contracts/desktop-ready.md`。

双屏隔离 KWin：1024×768，两个虚拟输出，独立 D-Bus/配置目录。实际 Cover 与生产 SessionEntryService 运行；壁纸/配置与必要窗口状态用夹具注入，没有运行完整生产 Shell/platform。cold-fixture/warm-fixture 表示夹具新进程/第二次运行，**不是实机冷启动/热登录**。日志时间为 QML Date.now 毫秒，不和 Python monotonic 混减。版本见 `versions.txt`。

## 验证与恢复

- `python3 apps/greeter/tests/entry.test.py`：本地字节匹配、文件替换、拒绝网络/相对路径/目录/非法hash。
- `node shell/desktop/modules/wallpaper/test_wallpaper_handoff.mjs`：既有 resident-buffer/快速切换行为及一次入场 top 抑制、日常 top 恢复。
- `python3 apps/greeter/tests/entry-virtual.test.py`：实际虚拟 KWin/Cover/生产 gate；冷/热夹具、默认回退、晚到 Cover、必要组件延迟、丢失一个输出ready、hash不匹配。逐项日志保存于本目录。失配/丢失场景不得有 RevealStarted，12秒恢复元素，Cover仍独立15秒撤罩；测试finally终止隔离进程组，退出虚拟KWin。
- `python3 apps/greeter/tests/cover-supervisor.test.py`：资源撤销/版本替换、独立期限、PID校验、wrapper清理及真实虚拟KWin崩溃恢复原回归通过。
- `node apps/greeter/tests/entry-protocol.test.cjs`：旧/重复事件、会话/hash/fit/输出失配及非法 JSON 均拒绝，正常事件仅接受一次。
- `git diff --check`：无空白错误。

## 验收裁定

A03：完整三阶段未测。隔离静态字节/提交协议可验证，不推出 Greeter终帧相同或物理呈现。

A10：生产 gate/真实Cover隔离检查已执行；完整生产 bar/Dock、冷/热启动录像未测。没有录像产物，不以日志或夹具名替代录像。

A14：组件延迟/丢ready/hash失配的门控恢复由隔离夹具验证；真实TTY/DRM及完整Shell崩溃矩阵留T14。

T08 仍缺实机基准且认证终帧版本未传递。依据任务卡“证据缺失不得关闭任务”，T11 最终不能标完成；实现与隔离验证可评审，完整验收阻断。下一步需有恢复保障的真实会话测试，不能由普通实施任务附带切换登录管理器。

## 独立审查

独立代理 `/root/review_t11` 未参与实现，只读初审和复审；初审发现正式帧门控、渐显、回执、默认背景、构图/发现竞态等问题；修复后复审又发现 WallpaperService URL ready兼容、fit调整及默认主题覆盖问题，均由执行者修复。最终复审结论见 `../../reviews/T11.md`。最终独立复审通过当前实现与隔离交付范围，无剩余 P0/P1/P2；完整验收继续阻断。最后的同图选择不触发值变化问题通过明确用户选择信号及真实函数VM回归关闭。
