# KWin 有界背景交接：冻结实施与证据

日期：2026-10-13。**状态：已实现实验补丁并构建；行为验收未通过，待独立审查；不可宣称黑屏修复完成，不可部署生产。** 用户质疑耗时后，主代理决定停止扩展范围并冻结，没有继续新增设计或启动编译。

## 交付范围

`apps/greeter/experimental/drm-handoff/` 中的 KWin v6.7.5 行为补丁、原始来源摘要、只构建不安装脚本、双屏虚拟 Qt 夹具、native publication parser 测试、README。`systemd/` 子目录由主代理独立负责，不计入本 KWin 报告。

KWin 补丁覆盖可信 PNG/默认色 bootstrap、root 私有匿名控制端点、账户/nonce/SCM_RIGHTS 校验、每输出 PresentationFeedback、三秒有界 ARM、正常退出 gate、仅析构局部抑制最后 unused-object disable、新 wrapper 固定 UID/root 发布根消费、十五秒自动撤幕、公开版本/撤销 500ms 监控。不得以源码存在等同实机行为通过。

## 实际验证结果

| 项目 | 状态 | 证据与限制 |
|---|---|---|
| KWin 6.7.5 `kwin_wayland` / wrapper 真实编译链接 | 通过 | `KWIN-build.log`，最终 root-selection build 到 Linking kwin_wayland，产物摘要 `KWIN-artifacts.json`；最终 publication header 21:02:42 修改、scene object 21:03:36、wrapper object 21:03:54、主二进制 21:07:12，编译产物晚于最终根选择代码。 |
| 最终补丁对干净上游原始文件 apply --check | 通过 | 固定 archive 原始文件生成独立 patch-check 目录，再实际 `git apply --check`；原始摘要见 kwin-source-sha256.json。 |
| Native publication parser 14 场景 | 通过（较早版本） | `KWIN-publication-14.log`：valid cover/contain、UID/hash/尺寸/fit/期限/字段/权限/撤销/symlink/avatar 负例。**发生于最后“installed 根存在即仅用该根”变更前；最后根选择未行为复测。** |
| 第一次 virtual normal 场景 | 失败 | `KWIN-first-normal-failed.log`：双输出背景 PRESENTED 已到齐，但正常退出 retention gate 错误，测试非零退出。 |
| normal gate 修复 | 已改、已编译；未复测 | 原因：inline 状态跨 executable/libkwin 的 hidden visibility 各有副本；现改为唯一 `KWIN_EXPORT` 外部变量/函数。最终 libkwin dynsym 实际导出 armed/allPresented/normalExit/nonce/generation/retain/cancel/deadline；不能以此代替行为复测。 |
| timeout/cancel/bootstrap/nonce/SCM/拒绝多 FD virtual 场景 | 未执行 | 夹具代码已提供，冻结后没有把未运行场景补写通过。 |
| Live KWin publication 撤销 / installed 根优先 | 未执行 | 源码实现与 native 较早测试不等同最终真实场景通过。 |
| KWin/greetd/logind 三层真实集成 | 未执行 | 没有真实入口接线或系统部署；systemd 子目录证据另计。 |
| NVIDIA / 多 GPU / 真实 VT / 物理黑帧 | 未测 | 未录屏、未切 VT、未重启 compositor/显示管理器、未接真实 GREETD_SOCK。未承诺零黑帧。 |

重启后的宿主 KDE 依赖由 6.30 更新至 6.31；第一次最后增量因缓存引用已消失的 `libKF6ColorScheme.so.6.30.0` 失败，随后重新配置 CMake 并成功链接到当前库。Qt 仍 6.12.0；依赖来自宿主和私有协议前缀，没有修改宿主 package 数据库或 `/usr`。

初次 fixture 的 DBus portal 尝试均发生在私有 namespace：没有 `/dev/fuse` 与宿主图形 socket，不能连接系统 realtime/显示服务；日志保留。后续夹具增加禁用 portal 的环境，但尚未复测。

## 产物与回退

编译/源码缓存位于 `/home/wwt/.cache/nextkde-builds/drm-handoff/`；主产物为 `build/bin/kwin_wayland`、同目录 wrapper 与 libkwin。此目录没有安装替换宿主。当前无 ninja/cc1plus/cmake 后台编译进程；无需恢复宿主配置。

若继续实验，使用 README 的显式独立前缀/VM 方案，先复测 normal 修复及其它隔离场景，再完成 root 系统接线与生命周期审核。恢复方式为移除 VM 实验入口/override、恢复原包或快照。本报告不授权系统切换。

冻结清单为 `KWIN-SHA256SUMS`。审查由主代理后续另派未参与实现的独立子代理；本报告不替代审查，也不关闭 A16/A17 或原实机任务。
