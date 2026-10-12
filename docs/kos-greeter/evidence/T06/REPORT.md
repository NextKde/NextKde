# T06 执行与验收记录

状态：完成（2026-10-11 用户明确确认验收完成）。分支：codex/notification-center-stacks。T01–T05 已由用户验收关闭，历史缺测不重新打开前置任务。

## 实现

outputs.py 实现机器策略校验与匹配；display.py 采集 KScreen/DRM EDID/logind 合盖状态，按实际 connector 和受支持 mode ID 原子提交，读回模式、scale、布局、HDR/VRR，一次安全回退，同一拓扑失败不循环提交。独立登录会话明确启用 --apply，普通预览默认只读。shell.qml 跟随实际活动屏并保留认证状态，小屏使用可滚动表单。临时测试脚本已包含控制器与策略文件。

## 运行证据

- tests.txt：策略测试 8 项通过。
- controller-tests.txt：控制器测试 9 项通过，包括失败、无效应用、读回失败、有界回退、合盖、热插拔和同 connector 硬件替换。
- virtual-tests.txt：真实独立虚拟 KWin 5 项通过，覆盖实际缩放读回、优先级、输出关闭/恢复、小屏表单与认证状态保留；虚拟后端拒绝负坐标时检测无效应用并回退。
- ipc-tests.txt：真实 Quickshell mock greetd IPC 9 场景通过；switch-tests.txt：临时切换 mock 14 项通过。
- user-kwin-effective.json：宿主实际读回 2560×1600 @239.9980010986328 Hz、scale 1.5，HDR off、VRR never；already-effective，requestCount=0，无宿主模式更改。
- schema-tests.txt：独立 JSON Schema 库缺失，未运行；运行期校验通过，不冒充正式 schema 校验。

## 测量边界

虚拟后端不是物理 240 Hz 屏幕。无物理 scanout/黑帧统计、跨进程交接时钟或所有实体多屏合盖录像，不声明零黑帧。归档 outputs.json/hardware.json/inventory.json/plan.json 是早期采集与规划快照。用户实机体验与本次明确验收是关闭依据，不补造缺测数据。

## 独立审查

早期离线范围审查见 ../../reviews/T06.md；本次最终实现与状态修订另作独立只读审查，记录追加于该文件。未提交文件摘要见 SHA256SUMS。
