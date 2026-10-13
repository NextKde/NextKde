# KOS 独立登录界面：研究与实施任务包

日期：2026-10-11。研究基线：`54512887915152c514b9d08f3a45ca14779e1adc`。

2026-10-13 最新交接见 [HANDOFF.md](HANDOFF.md)：KWin/greetd/logind 三层显示交接实验及专用文件安装器已通过限定范围的独立复审；未由助手安装或启用，真实 PAM/三守护进程共同登录/NVIDIA DRM 和物理黑帧仍未验收。安装命令为 `./tools/install-greeter-handoff.sh`，仅安装 `/opt/kos-handoff` 文件，不启用服务；详见 [安装说明](../../apps/greeter/experimental/drm-handoff/systemd/INSTALL.md)。下文研究包定位和待实现命令描述属于早期基线，当前进度以最新交接为准。

本包是可评审的研究、约束和任务分解，不代表登录管理器已经实现。新增内容只位于本目录，不修改项目实现或系统登录配置。候选架构为 greetd + 独立 KWin 登录会话 + Quickshell Greeter。

## 阅读顺序

1. [研究报告](research.md)：证据、建议与待验证项。
2. [参考图与视觉来源](references.md)：官方锁屏图、实机多用户参考与用户当前设置。
3. [硬约束](constraints.md)：后续实施不可绕过的边界。
4. [代理工作规范](AGENTS.md)及用户指定的[agent.md入口](agent.md)。
5. [验收矩阵](acceptance.md)：证据要求、故障恢复和阻断条件。
6. [独立任务卡与依赖图](tasks/README.md)。
7. [交接契约](contracts/README.md)和[示例数据](contracts/handoff.example.json)。
8. [测试证据模板](evidence/TEMPLATE.md)。

## 视觉资产

- [架构与交接时序 SVG](assets/handoff.svg)
- [离线可切换分镜 HTML](assets/storyboard.html)：单用户、多用户、失败、退场、桌面入场；概念示意，非 Tahoe 实測。
- [当前 KOS 设置截图](assets/kos-current-settings.png)

## 评审结论边界

第一版目标是背景一致、登录元素退场、隐藏桌面初始化并统一揭幕。跨两个 KWin 的零黑帧、动态壁纸逐帧连续和 Tahoe 精确动画参数都尚未证实，不得用静态截图宣称通过。方案进入实施前须完成任务 T01–T04 的事实核验与原型门槛。

[源码与证据边界复核](SOURCE_VERIFICATION.md)。

[详细视觉与动画规格草案](visual-spec.md)。

[文档包检查结果](VALIDATION.md)：文档与资产检查已完成；实现和硬件验收尚未执行。

[每次完成后的独立子代理审查规则](REVIEW_POLICY.md)：适用于文档维护和全部任务卡，是关闭任务的必要条件。

产品定位：这是本项目的独立 app，与天气等同属 apps 体系，并提供自己的安装命令。详见 [App 与独立安装方案](app-packaging.md)；命令仍为待实现设计。

当前任务状态：T01–T06 已由用户验收关闭（2026-10-11）；T02 按用户明确要求标记完成。以 tasks/README.md 的当前状态为准，历史报告的阻断结论不重新打开任务。

T07 独立壁纸宿主已完成实现、隔离 A03-H/宿主 A11 验收及独立复审（2026-10-11）；见 [宿主契约](contracts/wallpaper-host.md)、[证据](evidence/T07/REPORT.md) 和 [审查记录](reviews/T07.md)。生产三阶段、真实分数缩放协商和 scanout 仍留后续任务。

T09 会话 wrapper 已完成实现、隔离 A11/A13 子项及独立复审（2026-10-12）；见 [契约](contracts/session-handoff.md)、[证据](evidence/T09/REPORT.md) 和 [审查记录](reviews/T09.md)。真实 Cover/桌面集成及持久安装仍由 T10/T11/T14 验证。

T10 早期桌面 Cover 已实现 wrapper 并行启动、每输出 overlay、资源版本校验、独立超时及模拟 Shell 故障恢复；已通过隔离 A09/A14-C 及独立复审（2026-10-12）。见 [契约](contracts/early-cover.md)、[隔离证据](evidence/T10/REPORT.md)和[审查记录](reviews/T10.md)。真实 Shell 就绪集成、物理 TTY/DRM/presentation 与黑帧测量仍由 T11/T14 等后续任务验证。

T11 已加入 ready 协议、正式静态字节与输出提交帧门控、bar/Dock入场和超时恢复；双屏隔离夹具通过。完整 A03/A10、实机冷热启动录像及 T08 终帧版本仍缺失，状态保留阻断。见 [协议](contracts/desktop-ready.md)、[证据](evidence/T11/REPORT.md)与[独立审查](reviews/T11.md)。

T12 已交付预生成主题图、空间二维原图与未知主题固定色的安全静态接点，独立复审通过（2026-10-12）。完整 T11 依赖及实机 A12/A13 仍阻断；见 [契约](contracts/wallpaper-fallback.md)、[证据](evidence/T12/REPORT.md)及[审查](reviews/T12.md)。

T13 已交付外部录像采集规范及逐帧分类离线分析器，合成数据测试与独立审查通过（2026-10-12）。真实录像、性能统计和完整 T11 依赖缺失，A16 未测、任务保持阻断。见 [测量证据与限制](evidence/T13/REPORT.md) 和 [独立审查](reviews/T13.md)。

T14 已交付隔离故障回归、完整主项裁定及集成/安装/升级恢复评审包并通过独立审查（2026-10-12）。完整 T11–T13 与实机故障恢复、A18/A19 仍阻断，不建议 G5；见 [验收报告](evidence/T14/REPORT.md)和[集成/恢复方案](evidence/T14/INTEGRATION.md)。
