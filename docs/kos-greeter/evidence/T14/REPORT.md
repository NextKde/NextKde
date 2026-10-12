# T14 故障矩阵与集成评审记录

状态：阻断（隔离故障矩阵/集成评审包已交付；完整依赖与实机验收缺证据）。执行者：Codex 主代理。
日期/时区：2026-10-12 Asia/Shanghai。分支：`codex/notification-center-stacks`。
基线：`54512887915152c514b9d08f3a45ca14779e1adc`。未提交工作区；冻结范围见 `../../reviews/T14.sha256`，既有用户改动保留。

已完整阅读两份 README、任务卡、AGENTS/agent、constraints、acceptance、research、REVIEW_POLICY、app-packaging 及 T11–T13/持久安装报告。任务卡仅授权测试与方案评审。本轮没有 sudo、安装、服务切换、PAM 改动或桌面重启。

## 环境与复现

`python3 docs/kos-greeter/evidence/T14/run.py`：顺序执行16组既有测试、独立构建和 diff-check，18项返回0；命令、耗时和日志路径见 `results.json`。输出位置改为 T14，避免覆盖 T10 旧证据；只改两份测试的可选 evidence 路径，没有改产品实现。

非 root 普通账户；真实 Quickshell + mock greetd Unix socket；两输出虚拟 KWin 1024×768、独立 D-Bus/配置，生产 Cover/SessionEntryService/静态壁纸层运行，完整 Shell/platform 仍为夹具。版本见 `environment.txt`。虚拟环境没有物理 seat/VT/DRM scanout，GPU 驱动验证和真实 output 240Hz/1.5 不属于本次运行。

宿主在本轮开始前已为 greetd active/enabled；services-before/after 相同。不能由历史 T01 推导现在 plasmalogin active，也不能声称本轮安装/恢复了原管理器。隔离套件里的“Installed/Restored”文本来自 fake systemd 临时 root，非宿主系统操作。

## 必需故障与恢复矩阵

| 场景 | 本轮证据/实测恢复 | 最终状态与实机限制 |
| --- | --- | --- |
| home 不可读 | resources.log 删除发布源文件后只读副本仍可消费；accounts.log 默认头像回退 | 临时目录清理；未实际 chmod home/以 greeter UID 跨权限运行，实机未测 |
| 图片失效/schema过期 | resources/wallpaper/fallback/handoff.log，损坏/丢失/未知版本/路径拒绝，默认背景 | 夹具完成并清理；三阶段真实画面未测 |
| 认证失败/取消/断连/launch拒绝 | ipc.log：真实 QML+mock IPC不启动目标，取消或重建认证；lifecycle.log 状态机 | 测试进程结束，无真实 PAM/登录服务交替；实机未测 |
| Greeter崩溃 | lifecycle 状态/断连不等于真实崩溃；历史 A14-P 用户已验收关闭 | 本轮完整 daemon仍活/UI崩溃恢复未测，不能写通过 |
| user session立即退出/启动失败 | handoff.log：子进程退出7/无可执行路径/SIGTERM，wrapper清理描述和子进程 | 临时 runtime 无 kos-handoff-*；实际 Plasma立即退出未测 |
| Cover超时 | supervisor.log独立0.2秒期限终止模拟卡死UI；cover/production-layer日志独立撤罩，gate缺ready不正常揭幕 | 虚拟KWin/夹具退出；实机快捷键/物理恢复未测 |
| Cover崩溃 | cover.log、cover/cover-crash.log：杀真实隔离Cover，测试受控结束 | 隔离进程组清理；不推导实际桌面可登录 |
| Shell延迟/崩溃 | production-layer delayed-essential/lost-output-ready；cover shell-never-ready，超时放行/撤罩 | 模拟Shell而非完整生产Shell崩溃，完整项未测 |
| 显示拔线/异常layout | display.log 与 cover/output-removal.log：虚拟输出disable/enable，认证item保留，负layout安全回退 | 两虚拟输出受控结束；物理拔线/合盖/不同缩放未测 |
| 原管理器备份恢复/升级失败 | install.log：23项临时文件树事务测试、fake systemd/logind；精确字节权限/链接恢复、active核验、失败重试和升级拒绝 | 临时root清理；真实原管理器可恢复未测 |
| 同UID第二图形会话 | handoff.log：现有共享Shell、logind第二会话、检查失败均拒绝；文件锁隔离 | 保持“不支持并发”边界，不把描述隔离写成桌面并发支持 |
| 发布撤销/GC/账户删除 | resources/fallback/handoff.log：revoke代表删除操作、过期、GC中断恢复；supervisor与production-layer验证消费降级 | 实际账户删除事件/全消费端生命周期未测，A18仍阻断 |

每项套件耗时见 results.json，不是故障恢复耗时。虚拟 KWin 终止后 supervisor 退出为0.215s/0.065s（supervisor.log）；真实 TTY/管理器恢复耗时未测。测试 finally 清理子进程、临时目录；没有要求宿主恢复服务，宿主前后状态相同。`privacy-cleanup.json`对39份合成日志的三个敏感标记检查无命中，有限命令模式ps快照无剩余匹配进程；不证明任意孙进程均清理，也不代替真实PAM审计。

P3延后：收集器run.py在父进程已退出时只向进程组发SIGTERM，忽略SIGTERM的孙进程可能残留；本轮18项均正常结束且有限残留检查无匹配，没有运行收集器的超时/异常故障注入。后续增强并测试进程组清理；独立审查确认不阻断本轮隔离评审包，不声称收集器异常恢复已验收。

## A01–A19 完整主项裁定

“阻断”表示有隔离或历史子项证据，但完整主项缺证据；既有 T01–T06 用户关闭不重新打开。

| ID | 状态 | 本轮/关联证据与缺口 |
| --- | --- | --- |
| A01 | 阻断 | 历史T02用户已关闭；本轮handoff子进程，不是完整真实登录/双KWin检查 |
| A02 | 阻断 | ipc/lifecycle隔离通过；真实PAM失败/重复输入录像未补采 |
| A03 | 阻断 | production-layer静态hash/fit/center与默认通过；Greeter-Cover-完整桌面三阶段未测 |
| A04 | 未测 | T06已由用户关闭；本轮不补造物理240Hz/1.5新录像 |
| A05 | 阻断 | display/cover虚拟拔除通过；物理多屏、合盖未测 |
| A06 | 阻断 | accounts/ipc身份选择通过；完整多用户实机录像未补采 |
| A07 | 阻断 | accounts/resources回退通过；真实greeter权限+home不可读未测 |
| A08 | 阻断 | ipc退出顺序/帧提交检查通过；实际跨会话呈现录像缺失 |
| A09 | 阻断 | cover/supervisor隔离独立期限通过；物理最早映射/呈现未测 |
| A10 | 阻断 | production-layer九场景通过；正式Shell冷/热启动录像缺失 |
| A11 | 阻断 | resources/handoff/wallpaper/fallback隔离拒绝和默认通过；完整集成故障未测 |
| A12 | 阻断 | fallback/production-layer静态接点通过；真实动态/空间完整会话未测 |
| A13 | 阻断 | 本轮合成证据人工检查无真实凭据；完整PAM日志、真实描述/截图隐私未测 |
| A14 | 阻断 | Cover/子会话/虚拟KWin/模拟Shell隔离故障通过；真实Greeter/Shell/TTY恢复未测 |
| A15 | 阻断 | T04研究来源可查；同状态Tahoe实机/动画参数未测，不宣称1:1 |
| A16 | 未测 | measurement.log合成分析通过；无外部录像，不填零黑帧 |
| A17 | 通过（本轮范围） | 独立只读审查及最终元数据复审见reviews/T14.md，不代替硬件验收 |
| A18 | 阻断 | 发布、撤销、GC、部分消费者隔离通过；真实账户删除与全消费端失效未测 |
| A19 | 阻断 | install.log与bundle清单通过；干净系统真实安装、缺依赖、卸载/升级恢复/合集未测 |

## G0–G4 与交付结论

G0通过当前文档/来源可追溯子范围；完整产品许可审计见 INTEGRATION.md 的缺口。
G1沿用T02用户关闭记录，本轮IPC/会话退出隔离回归通过；不扩大到本轮真实PAM/物理恢复。
G2合同隔离回归通过，完整实机身份/资源/输出与A18/A19阻断。
G3阻断：完整三阶段背景、正式Shell入场和冷热录像缺失，T11/T12完整依赖未满足。
G4阻断：真实Greeter/Shell崩溃、物理拔线、TTY/原管理器恢复未测。
因此不建议G5；完整T14不能标“完成”。已交付可复现隔离故障矩阵、主项裁定、风险表、安装/卸载/升级/恢复方案：`INTEGRATION.md`。

认证成功/退场/launch/登录KWin退出/用户KWin连接/实际Cover呈现/完整桌面揭幕：真实时间线全部未测。虚拟日志的Date.now/monotonic不跨时钟混减，frame提交不作为scanout。相机参数、黑帧数量/时长、Tahoe叠图误差：未测。

## 独立审查

被审范围与摘要：`../../reviews/T14.sha256`。最终代理ID、问题处置与结论保存于 `../../reviews/T14.md`。独立通过只能关闭本轮评审包问题，不能代替缺失的完整验收。
