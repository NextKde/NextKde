# T07 独立壁纸宿主验收

状态：完成（隔离宿主验收；独立复审通过）。执行者：Codex 主代理。日期：2026-10-11，Asia/Shanghai。
分支：codex/notification-center-stacks；HEAD：54512887915152c514b9d08f3a45ca14779e1adc。仓库原有 T01–T06 未提交文件及无关 KWin 修改保留；本次范围用 SHA256SUMS 冻结，不擅自把全部历史工作纳入提交。

依赖：T03/T06 已由用户验收关闭，发布与输出证据原样保留。环境为普通 UID 1000 的独立 dbus-run-session + KWin --virtual，两路 1024×768 输出；未使用 DRM、真实登录 seat/VT 或用户 platform socket。版本见 environment.txt。恢复入口为结束测试进程组，临时资源由 TemporaryDirectory 清理；未切换系统登录管理器。

## 步骤与结果

| 验收 | 范围/结果 | 证据 |
| --- | --- | --- |
| A03-H | T03 发布 synthetic RGB 图，校验同 manifest hash；四种 fit × scale 1/1.5，实际 Qt 独立宿主与独立裸 Image 夹具逐像素完全相同 | manifest.json、source.png、composition.json、八组 *-host.png / *-offline.png、render-tests.txt |
| A03-H 分数缩放 | KScreen 有效 scale 与 Qt 实际 DPR 均断言；逻辑 683×457，实际 painted/crop/decode budget 与物理截图尺寸导出 | composition.json |
| A11 宿主 | 缺图、损坏、撤销、未知 schema/字段、UID 目录缺失/不可信所有权返回默认；缺 UID 完全只读不新增文件 | unit-tests.txt |
| A11 运行回退 | 缺图、未知主题、森林必需资源缺失、主题校验进程挂起，实际 Qt 画面为固定背景且正常退出 | faults.json、对应 fault PNG、render-tests.txt |
| 输出生命周期 | 两个 background layer 窗口；禁用第二输出销毁窗口/订阅，恢复后应用继续运行 | window-events.txt、render-tests.txt |
| 认证回归 | 实际 Quickshell + mock greetd 的成功、重试、取消、断连、launch拒绝、多轮提示、账户选择通过；不证明 PAM | ipc-tests.txt |

渲染夹具只画 synthetic 壁纸，不含认证字段或用户窗口。离线消费端独立使用 Qt Image 填充枚举和桌面现有解码预算，未导入 WallpaperHost。比较覆盖 crop/fit/stretch/center；center 保留原桌面预算行为（scale1 解码724×442，scale1.5 解码913×557），未承诺 center 跨scale构图不变。crop 中心主体跨 1/1.5 的采样/解码取整差值见 composition.json，门槛 <=1 个逻辑像素，不宣称跨 scale 零像素误差。

虚拟 KWin 的输出配置支持 1.5；Qt Wayland 在本环境未自动获得分数 DPR，因此测试另显式设置 QT_SCALE_FACTOR=1.5，并读取窗口实际 DPR 断言。它验证 Qt 分数坐标/取整，不能替代真实显示器分数 scale 协商验收。grabToImage 传逻辑尺寸，Qt 按 DPR 生成物理截图；没有二次乘 DPR。实际裁切值与理想原图几何分别记录，不把理论值当实测。

## 时间线与事件

测试断言独立 decoded、backing-window-visible、frameSwapped 事件。默认帧可早于图片 decoded；图片就绪会重置提交计数，下游应看资源 ready 后的帧。窗口可见是 Qt/Quickshell 标志，frameSwapped 是排队提交，均非 scanout；事件没有跨进程 monotonic 同步。本卡没有认证/退场/launch/用户 KWin/Cover/揭幕的生产时间线。

## 故障恢复与最终状态

缺图立即 Image.Error 回退，未知主题不实例化，缺森林 plate 在执行 QML 前被哈希预检拒绝，挂起校验进程由三秒 timer 停止；故障事件延时见 faults.json（Date.now 差值，仅本进程粗测，非跨会话性能）。恢复方法为重新提供合法发布 manifest/原版可信 bundle 并重新加载；无资源时继续固定背景，不停止认证。消费进程读取三秒超时，成功重新校验每秒一次，换 UID 立即清空，撤销后下一轮检查丢弃 data URL，Qt image cache 关闭。

每组虚拟测试结束后 KWin 随 --exit-with-session 子进程退出，测试 QML/helper 被终止，临时目录清理。输出禁用/启用仅作用于独立 virtual socket。系统状态见 final-state.txt。本卡未部署 root 资源目录或系统服务，未修改 PAM、home 权限、显示管理器配置。

## 结论与未测限制

只关闭 A03-H 和本卡 A11 宿主范围；完整 A03 三阶段仍留 T14。可信主题 bundle 预检与静态回退不是动态连续性/完整 GPU 渲染验收。真实跨 UID root 发布部署、物理拔线/合盖、240Hz、presentation-time、零黑帧、生产 Cover/桌面、T08 动画及独立安装全部未测，按各后续卡完成。本卡不宣称 Tahoe 1:1。

独立审查者 `/root/t07_review` 未参与实现；初审发现解码预算差异和主题缺依赖误 ready，已由主代理修复并补测试。最终被审摘要、问题处置与复审结论见 ../../reviews/T07.md。
