# Forma 应用接入

[English](FormaIntegration.md)

## 用户可见的边界

设置 → **接入状态** → **Forma 应用** 提供默认关闭的 **启用 Forma** 开关。
启用后，已安装的 Forma 应用接管受支持的文件/媒体默认关联和桌面入口；
不安装或卸载软件、不重启服务、不改变浏览器，**不替换 Kos 系统设置**。
**重新应用** 可纳入之后安装的应用。未安装的应用会列出并跳过。

固定角色包括 Finder、Terminal、Text、Photos、Video、Music、Calculator、
Task Manager、Screenshot、App Store、Mail。音频优先使用 Music，缺失时回退
Video。只改变明确支持的 MIME/协议关联，不把 PDF、压缩包指向不支持它们的
Forma 应用。计算器、任务管理器等是启动角色，不人为创建 MIME 关联。

目前 Forma Terminal 只接受工作目录，没有 KDE 所需的 `-e` 命令执行接口。
它可以由 Dock/应用入口直接启动，但开关保留 `TerminalApplication` 和
`TerminalService` 执行首选项，避免新设置破坏 `Terminal=true` 命令行应用。

## 所有权和恢复

`platform/src/daemon/FormaIntegration.*` 负责安装检测、配置修改，以及
`$XDG_STATE_HOME/quickshell/kos/forma-integration.json` 下有大小限制的
schema-1 所有权记录。

修改任何默认项之前，先持久保存该键的原值、原先是否存在、本次 Forma 写入值。
再次应用不会覆盖第一次的备份。用户 MIME 默认项写入 `mimeapps.list`；若用户已有
`kde-mimeapps.list`，也处理其相关键，避免高优先级关联静默覆盖选择。
保留无关键和系统默认项。

关闭时只恢复仍等于本次 Forma 写入值的键，不覆盖启用期间后来手动改选的应用。
原键不存在时删除本次覆盖，不写空 ID，也不猜测应该恢复成哪个 KDE 应用。
状态损坏或版本不支持时拒绝修改，不能当作“没有备份”。部分写入失败会保留恢复
信息；设置中的 **恢复之前的首选项** 可重试恢复，之后再接管。
失败或断连不会让开关乐观显示为已成功切换。

## 运行路径

- Settings → `SettingsBridge` → Shell 的 `forma-integration` IPC →
  `FormaIntegrationService` → 平台的 `integration.forma.get/set`。
  QML 不直接写系统关联文件，不执行系统接入命令。
- 系统菜单在启用且安装时优先打开 Forma App Store，并让 **强制退出** 打开
  Forma Task Manager。**系统设置** 仍激活 `kos-settings`；**关于本机** 保留信息中心。
- `DockModelService` 将既有 KDE 固定项呈现为已安装的 Forma 对应应用。
  单纯启用不改写持久化固定项 ID/顺序；关闭恢复原呈现。用户明确取消固定或拖动时，
  操作对应的原始记录。正在运行的 KDE 窗口和应用启动器中的明确选择不被冒充或劫持。
- `screenshot.capture` 在 Forma 模式下优先使用其 Screenshot 桌面入口，否则保留旧工具回退。
- Dock 回收站点击和右键 **打开** 都调用 `file.open-trash`。启用且已装 Finder，
  或者当前目录默认处理程序本来就是 Finder 时，平台将本地
  `$XDG_DATA_HOME/Trash/files` URL 交给 Finder 的 `%f` 桌面参数展开为本地路径。
  Finder 把该目录识别成包含还原/清空控件的原生回收站；不向它传 `trash:` 或 `file://` CLI 参数。
  空的用户回收站可创建目录，拒绝符号链接目标；其他配置仍保留 Dolphin `trash:` 回退。
  本次不扩展现有回收站状态/清空操作到其他挂载盘。

旧版或缺失的平台服务会显示不可用/错误状态，不应用首选项。验证前必须部署配套
平台、Shell 和 Settings；源码 QML 混用旧的已安装服务不能算接入完成。

## 验证边界

依[开发规范](Development.zh-CN.md)，构建与运行只在专用 VM 或托管 CI 执行。
`kos-platform.forma-integration` 使用隔离配置检查所有权和恢复；
`kos-platform.forma-trash` 使用假 desktop 入口、临时 XDG 根和真实 KIO 启动路径，
检查回收站本地 argv、截图首选及不安全路径拒绝。
设置页契约覆盖等待/确认/错误状态；Dock 模型测试覆盖可选角色替换和投影后的取消固定。
这些测试定义不代表当前修改已经通过测试。
真实 VM 还需验收开关、补装应用后重新应用、手动关联保留、相关文件格式及真实 Finder 回收站窗口。

权威通信定义见 [platform.v1](../shared/contracts/platform.v1.md)。
