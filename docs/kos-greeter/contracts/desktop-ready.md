# T11 桌面就绪协议

生产适配位于 `shell/desktop/modules/common/SessionEntryService.qml`。Cover 与桌面通过固定 Cover QML 路径的 Quickshell IPC 通信；不把 wrapper 环境导入 systemd/DBus，不依赖天气、音乐或应用索引。当前源树布局可运行；安装后的路径布局由 T14 打包核验。

`cover describe` 返回 session/hash/version/fit/outputs/revealing；outputs 是当前输出名排序列表。`cover reveal <JSON>` 只接受完全匹配的 session/hash/version/fit/outputs，返回 `accepted` 或 `rejected`。重复揭幕、旧会话、hash/输出不匹配不得开始动画。`cover abort` 保留人工恢复；旧 `cover ready` 仅作为 T10 手动恢复兼容口，不作为生产 ready 信号。

桌面每 200ms 有界发现 Cover，最多 12 秒。无 Cover 的普通桌面 progress 始终为 1；发现有效交接后才门控 bar/Dock 内容。bar/Dock 仍映射以取得几何，每 100ms 核对活动屏、映射、尺寸；配置 ready 必须满足。当前产品仅在活动屏有 bar/Dock，不宣称每输出都有这两个组件。独立 bar 禁用且集成到 Dock 时不等待独立 bar。

T12 更新：非默认静态图通过桌面侧 `entry.py` 读取当前 UID 的公开 store，校验当前版本、fit、SHA256（不再从桌面遗留原图路径取生产交接字节）。校验结果携带同一份图片字节，正式 WallpaperImageLayer 用其 data URI 渲染，避免校验/解码间文件被替换。保持同一 shared 静态 Image 的 DPR、decode budget、fit/居中算法。pending 的第一次正式过渡被消费为 none；后续日常切换保留原偏好。ready/settled 向 WallpaperService 上报已验证原 URL，以保持既有 Plasma takeover 协议。

每输出正式窗口的 `contentItem.Window.window.frameSwapped` 在当前图片 ready、过渡结束且 source/fit 匹配时登记 session/output/hash 事件；T12 使用独立静态接点层登记主题/空间回退帧，不把动态/空间状态冒充可恢复；该层留白底色与 Greeter/Cover 同为 #16283b。输出列表变更清空帧登记，当前全输出共同就绪才揭幕。默认正式窗口绘制固定 `#16283b` 后也可提交帧，不等待空图片解码。

收到明确 accepted 回执后，Cover opacity 从 1 到 0、bar/Dock opacity 从 0 到 1，各执行 620ms（reduced motion 为 1ms）；起点为 IPC 请求/回执，存在通信延迟，不宣称 compositor 原子同步。两边记录 RevealStarted/RevealComplete。正式静态字节在揭幕后保持，避免二次壁纸替换；用户改变图片、fit、mode、takeover、空间开关时解除交接覆盖，恢复日常配置。默认背景同样解除。

12 秒桌面期限无条件开放 bar/Dock；Cover 15 秒自身撤罩、25 秒 supervisor 总期限仍独立生效。输出或组件故障不无限等待。人工恢复为 `qs -p /绝对路径/apps/greeter/cover.qml ipc call cover abort`；卡死时相同路径 `kill`。未安装或切换任何系统服务。

frameSwapped 是帧提交，非 scanout。完整 A03/A10 仍需要真实三阶段截图、冷热启动录像、输出/缩放记录；虚拟窗口夹具不能替代。T08 的认证终帧版本未固定到 wrapper，仍不能证明三阶段整体版本一致。

## 2026-10-12 就绪门槛追加

揭幕还须等待 `WindowService.providerReady`（初始窗口集合完成，允许零窗口）。bar/Dock 在配置、窗口 provider、映射及几何有效后收到 frameSwapped 才上报 essential；映射、输出、尺寸或这些 ready 值变化时清除登记。pending 内容保留 0.001 opacity，让 Qt 提交内容而非跳过全透明子树；Cover 仍覆盖其上。此为内容初始化后的窗口提交门槛，不保证全部图标异步资源已完成、不代表真实屏幕呈现。12/15/25 秒故障期限本轮保留，慢于该期限按既有超时恢复，不承诺无限等待。
