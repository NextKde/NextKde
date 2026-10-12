# T13 外部交接测量规范

此规范及离线分析器是测量准备交付。A16 尚未执行，不能替代原始录像。

## 采集矩阵

每输出分别记录 cold（真实冷启动后认证）、warm（系统已运行后的再次登录）、logout（注销返回 Greeter）；每格至少三次，异常样本保留。交叉比较实际 59.999/239.998 Hz、登录与桌面相同/不同 mode，以及静态图/动态静态回退。记录实际模式、分辨率、scale、VRR、输出标识，不能只记录目标值；无法提供某配置时注明未测。跨屏分别标注，不平均掩盖单屏异常。

外部相机固定位置/曝光/焦距，记录设备型号、固件、真实采样率、曝光时长、滚动快门、时间戳来源、采样时长、丢帧情况。240fps 拍 239.998Hz 无法保证捕获每次显示更新，60fps 尤其不足；报告采样上限。禁止将播放速度或插值帧率当采样率。只拍清除密码后的认证成功交接；logout 使用没有私人窗口的受控会话。先检查隐私再保留录像，不采集凭据或用户窗口。

每次目录包含 original 原始视频（SHA256）、metadata.json、frames.csv、events.csv、summary.json、恢复记录。metadata 记录基线提交和工作区摘要、greetd/Qt/Quickshell/KWin/内核/GPU驱动版本、机器/seat/VT、输出配置、背景资源hash/crop/fit/scale、启动类别、重复编号、曝光、真实采样率、录像设备及录像/系统时钟对齐误差。无录像的格子不生成数值统计。

## 分类与抽帧

使用本机 ffprobe 逐帧导出原始 PTS 和 duration，保留命令和输出；按解码顺序从0编号，VFR逐帧使用实际时长。不以平均fps替代时间戳。保留抽帧索引与人工标注依据。分析区间截取后重新编号，PTS允许非零；每一帧必须有一行。

frames.csv 列为 `frame,pts_ms,duration_ms,class`。class 必选：background（预期背景/正常揭幕）、no_signal（由屏幕OSD/外部状态佐证无信号）、black_content（有链路佐证的黑色内容）、wrong_placeholder（错误背景）、frozen_old_frame（本应变化却持续旧帧，有动画/时序参照）、unknown（无法判别，含部分黑区/滚动快门混合帧）。正常静态背景不能判冻结。光学纯黑无法区分链路状态时标 unknown；不得按亮度自动推断 no_signal。

运行：

```bash
python3 apps/greeter/companion/measurement.py /绝对路径/frames.csv --exposure-ms 1 --display-hz 239.998 > /绝对路径/summary.json
```

分析器拒绝空输入、不连续PTS、丢失索引、非法分类/时长。分别输出每类帧数、连续段、累计采样时长、最大/中位段；没有该类的段统计为null。统计的是采样覆盖时长，并非显示器scanout时长。边界保守误差为两端各一个最大采样周期加曝光，即 `2*(max_period+exposure)`；不包含未量化滚动快门和时钟误差，因此不能当完整物理置信区间。短于采样周期的异常可能完全漏检。零观察不能证明零黑帧。

汇总表按配置/启动类别/输出分组，填写实际样本数、每样本分类统计、跨样本最大值和中位数（按每样本最大连续段计算），异常与缺测分列；不混用连续段中位数和跨样本中位数。

## 事件对齐与归因

事件至少覆盖 authentication_completed、exit_completed、old_kwin_released、new_kwin_connected、cover_submitted、desktop_revealed。events.csv 保留 `event,clock_domain,timestamp_ns,source,uncertainty_ns`，缺事件填未测。同一机器同一boot的CLOCK_MONOTONIC事件可相减；跨boot、相机PTS、QML Date.now和Python monotonic不能直接混减。现有T11日志为墙钟毫秒，不能冒充monotonic证据。

采集时以不含私人内容的可见同步标记建立相机PTS与系统monotonic锚点，区间前后各一锚点并记录残差/漂移；未建立锚点时只分析视频内部时长，系统日志另列，不做因果对齐。frameSwapped仅为提交/排队证据，cover_submitted不能命名实际呈现。真实呈现需要带时钟域的presentation反馈或外部录像。

DRM归因需单独保留脱敏KWin/内核输出事件、VT接管、模式切换或链路训练证据，与已对齐时间线关联。无证据只标原因未知；纯黑图像、socket可连或窗口映射均不足以归因DRM。不得为测量修改内核/KWin核心。

## 恢复

采集前确认可用TTY及安装时保存的原管理器恢复路径，使用 apps/greeter/INSTALL.zh-CN.md 中适用于实际安装的恢复操作；本规范不授权执行切换。遇无信号/登录失败立即停止重复样本并按既有恢复路径处理，记录触发条件、操作、实际耗时、最终服务/进程状态。未执行恢复演练标未测，不能填零耗时。本轮仅离线工具，无系统状态变更。
