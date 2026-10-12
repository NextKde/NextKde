# 交接降时与前接管研究

日期：2026-10-12。状态：实现/隔离验证已交付，待独立审查。未部署/重启实际会话，未修改显示管理器/PAM/实际VT或KWin二进制。最终范围见 SHA256SUMS；用户前置修改保留。

## 真实阶段与目标

主代理本次已安装实机日志：LaunchRequested16.157s；wrapper ready18.008；PlasmaStarting19.340；KWin服务启动19.559；Cover SocketConnected21.692；默认空source ResourceReady21.778；真正壁纸 ResourceReady23.334、WindowMapped23.335、FrameSubmitted23.444；Reveal26.259、完成26.880。

launch→Cover提交7.287s，其中wrapper ready→PlasmaStarting1.332s、socket→实际壁纸提交1.752s。空source ResourceReady不是壁纸第一帧，不应把21.778作为可见加载画面开始。这些日志不是scanout/黑屏录像。

## 确定瓶颈、实测与实施

Store每次consume都会image_copy整图解码/PNG重编码；wrapper build/write/consume三次，Cover read_reference/validate/consume三次。对当前已明确发布的同一2.3MiB静态PNG（不读私有原图、不采集屏幕），旧路径profile如下：wrapper三段0.514+0.437+0.433=1.384s，Cover读取引用+构建state0.430+0.865=1.295s，共6次重编码。该量级与真实阶段相符，不能仅从相符推导它是所有黑屏的唯一原因。

本批修改：

- wrapper仅生成/校验root可信live manifest的引用元数据，不在Plasma启动前读/重编整图。默认build/validate/Runtime及read_reference仍完整验证，只有生产wrapper明确选择metadata-only；描述不是显示授权/资源ready证据。
- Store使用有界128项“已通过canonical验证的内容SHA256+avatar→尺寸”缓存。只存hash/尺寸，不存图片/授权/URL；每次重新读取live manifest、权限/owner/link/预算和完整文件SHA256。撤销、替换、过期、内容/权限/尺寸变化仍拒绝；首次消费仍严格image_copy并比较canonical字节，缓存不改变最终图片。
- 增加SessionPreflight/HandoffReference阶段、SocketDiscoveryStarted/SocketPeerMatched（可信peer，尚非protocol ready）、FeedReference/InitialState、QML FeedReceived/ImageDecoded事件，下一次真实登录能分辨进程等待、PNG验证、全图解码。socket等待本轮只增强定位，未假造“更早可绘制”。

优化后同图测量wrapper总0.00056s（0次重编码），Cover0.519+0.0087=0.527s（首次1次）；这两个CPU路径合计约省2.15s。optimized-profile.json是一次perf_counter局部测量，非实机开机总时长、非用户黑屏时长/均值；baseline-profile.json是在修改前实际运行保存，profile.py --baseline可用旧重编码策略复现，不装/启动任何服务。

没有使用低清模糊图、没有改source/fit/crop/颜色、没有抢先显示蓝底；feed有效+图片settled门控与正式桌面完整背景验证保留。初次完整canonical验证仍约0.5s，Qt解码以及KWin接管仍有独立成本。没有让Greeter等待桌面而延迟launch。

## 验证

- resource-latency.test.py 5项：重复消费只重编一次；命中缓存仍拒绝权限/bytes/hash/manifest尺寸/撤销；wrapper零重编但实际read_reference拒绝损坏PNG；metadata拒绝symlink/过期。resource-latency-tests.txt。
- resources.test.py 12项；handoff.test.py 37拒绝/权限/原子引用/锁/故障/信号恢复；install.test.py 36fake-systemd事务通过，日志留本目录。
- cover-supervisor.test.py：实际virtual直接KWin与KWin wrapper双输出通过；KWin终止后恢复0.115/0.065s，無重启。夹具只接受测试进程子树，固定宿主service fallback被硬禁用，不发现宿主socket。
- entry-virtual.test.py 7项双屏交接通过；默认、冷/热、晚Cover、延迟必要组件、hash失败/丢输出超时均保持。virtual.log及场景log。
- startup-background.test.py 3项双屏第一帧验证通过：壁纸/Feed延迟及超时不回归提前蓝底；本轮增加可选证据输出目录，避免覆盖历史证据。
- socket可信peer/真实sync回归、IPC协议回归通过；QML声明/语法检查通过。所有图形夹具使用私有D-Bus和显式virtual WAYLAND_DISPLAY，只有supervisor会发现socket，其范围被测试父树硬限制。
- 离线KWin trace-only patch对冻结upstream v6.7.5源码git apply --check通过；未编译/运行。

## 完全消除前段黑屏还需要什么

CPU优化是可验证的降时，不是“黑屏已经解决”。旧壁纸销毁/旧KWin退出到新协议ready仍约5.53s，图片优化只覆盖其中一部分。完整具体研究见 DRM-HANDOFF.md：旧KWin cleanup/CloseFB、logind KD_TEXT/fbcon、新KWin空场景首帧三个独立覆盖点；提供四文件trace-only patch、源码摘要、已有DRM debug可观察范围、正常Greeter授权handoff保scanout的最小行为设计、同seat/VT有界协调和新KWin首帧门控的实施边界与VM部署恢复步骤。

该底层产物明确NVIDIA实际驱动/双GPU条件，并区分“源存在清理路径”与“本机该commit实际执行”。不直接跳过全局清理，不影响热拔线，不持DRM master阻塞接手，不改PAM/全局fbcon/输出模式。现阶段app层无法覆盖没有可绘制compositor的时间段，后续必须用实机外部录像/受控诊断确认覆盖点，再批准具体系统级实验。

## 更新与恢复

本批仅Greeter bundle有变更，普通用户执行现有独立安装更新入口可部署（需要原sudo权限，当前未执行）；当前Shell兼容版本无需重复同步。现有原子app升级和rollback保留。新增resource cache只在进程内，退出即消失，无需清理公开缓存或新资源版本。下一次真实登录用新增journal事件核对收益；不承诺CPU局部省时按同样数值线性转化成黑屏缩短。
