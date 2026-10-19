# T06 机器级显示契约 v1

通用安装默认 `apps/greeter/config/outputs.json` 为 `{"schemaVersion":1,"outputs":[]}`，表示没有机器专属覆盖，允许 0–16 条输出配置。按设备报告的受支持推荐模式选择，推荐模式不可用时采用受支持当前模式；已有有效缩放、位置和旋转保留。没有任何可用模式则返回 unavailable，不伪造显示模式。个人 EDID、高刷与缩放仅留在测试样例中，不作为安装默认。

管理员可在 `/etc/kos/greeter/outputs.json` 设置明确的机器覆盖策略，该文件优先于随应用安装的默认配置，须满足下述 schema 和权限校验。缺失或损坏策略降级为无机器覆盖，沿用相同推荐/当前模式规划及有界失败回退。HDR off、VRR never 和主屏优先级归一化仍是首版行为；空覆盖不代表所有显示设置完全不变。物理显示器兼容性仍需独立验收。

[JSON Schema](machine-outputs.schema.json)；测试样例与归一化 inventory 位于 `apps/greeter/tests/fixtures/outputs/`。这是独立机器策略，不是用户展示 manifest，也不替代既有 handoff schema。规划实现为 `apps/greeter/companion/outputs.py`；`display.py` 已接入 KScreen 控制、实际读回和有界回退，shell.qml 已接入活动屏与表单迁移。T02 和 T06 已由用户验收关闭；T09 消费同一机器策略，不根据头像修改输出。

字段仅允许 schema 声明的字段，版本固定 1，最多 16 输出，输入最多 64 KiB。拒绝未知字段、重复 JSON key、重复 hardwareId+connector、非有限数值、布尔伪整数。位置为全局逻辑坐标（可负），模式尺寸为物理像素，旋转为角度；KScreen rotation=1/2/4/8 需适配为 0/90/180/270，不能直接复制。crop 属于壁纸交接而非显示策略。首版策略 HDR off、VRR never；当前规划器输出意图，不证明当前状态已符合意图。

硬件标识采用有效完整 EDID 的 SHA256（`edid-sha256:` 前缀）。相同硬件只出现一次时跨 connector 匹配；重复 EDID 时仅在硬件 ID 相同候选中以 connector 消歧。无 EDID、候选不唯一、同 connector 但 EDID 不同均安全回退，绝不只凭 connector 信任。EDID hash 是显示身份提示，不是安全认证或跨固件永恒 ID。读取适配器必须校验 EDID 头、128 字节块、扩展数量与每块 checksum，并将 DRM connector 与 KScreen connector 唯一关联；归档 inventory 是人工核对的测试输入；display.py 的实际采集适配器已实现上述校验。

启动计划：匹配尺寸与刷新率（≤0.001 Hz 容差，适应后端浮点误差，不将 239.998 舍入为 240），不复用另一 KWin 的 mode ID。无目标模式采用当前受支持 preferred mode，再使用受支持 current mode；两者都无则不产生该输出计划。未知屏保留已有有效 scale/位置/旋转，无有效当前状态用 scale=1、rotation=0、position=[0,0]。priority 为正且较小者优先，最后按 connector 稳定排序；运行时不强制激活已知且被禁用的既有屏；新连接硬件允许按启动策略进行一次配置，合盖屏仍排除。

运行时 hotplug：仅选择 connected、enabled、未合盖的输出，保留有效当前模式、scale 和位置，不反复恢复机器目标。最后活动输出丢失返回 unavailable，不伪造画面；内屏重新活动后可再次选为主屏。user-selection 返回 unchanged 和空请求。仅控制器启动/拓扑事件可计算计划；新连接硬件按启动策略配置一次，已知硬件保留当前配置，头像路径不能连接到控制器。

计划 `modeRequests` 记录需要改变模式的 connector；控制器按 connector 解析当前支持的 mode ID，一次原子提交完整配置，超时后只进行一次安全回退；读回实际模式/scale/布局，不把提交成功当生效。相同拓扑/失败代次不得无限重试，单次事件串行合并，恢复不能唤醒已知合盖内屏。以上控制器要求已实现，并有故障注入和真实虚拟 KWin 读回验证；物理 modeset/scanout 仍不由这些测试证明。

`form_rect` 返回主屏内的全局逻辑安全矩形；小屏缩小可滚动 viewport，过小屏返回不可用。QML 已绑定实际活动屏、使用局部坐标、可滚动容器，换屏保持认证状态且不复制响应；实际 FloatingWindow 已绑定活动屏并使用可滚动 viewport；虚拟 KWin 测试检查换屏、缩放和小屏边界，物理画面仍以用户验收为准。

只读复核：`kscreen-doctor -j`、`/sys/class/drm/*/{status,edid}`，参考本机已安装 `kscreen-doctor --help`。实际 KWin 模式两阶段对照、HDR/VRR读回、模式事件、链路无信号和 scanout 均需隔离真实验收，不能从本机用户会话快照推导。
