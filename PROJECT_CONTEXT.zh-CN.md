# 面向 AI 贡献者的 NextKDE 上下文

[English](PROJECT_CONTEXT.md)

KDE Plasma 6 **Wayland**、Quickshell 0.3.x。先读本文件，再读[文档索引](docs/README.zh-CN.md)、
[架构](docs/ProjectArchitecture.md)、[开发](docs/Development.zh-CN.md)和[贡献规范](CONTRIBUTING.zh-CN.md)。

## 必须保留的边界

- `shell/` 负责呈现，`platform/` 负责 C++/Qt 桌面接入，`services/data-service/` 负责 Go 指标、历史、桌面快照和共享天气。
- Settings 是独立 Qt Quick 进程；通过 Shell `IpcHandler` 通信，不导入 Shell 模块。
- QML 不执行 `nmcli`、`wpctl`、`qdbus6`、`systemctl`、`gio` 等系统接入命令，也不绕过服务。
  新能力增加到[版本化平台契约](shared/contracts/platform.v1.md)，检查断连和错误路径。
- 已有模块自身状态的原子持久化是有限的历史例外；新接入放服务层。保留状态根目录、协议封装及迁移。
- 日历（含待办功能）、计算器、天气合用独立 NextKde/kos-apps 仓库
  （`apps/org.nextks.<app>`），ListenFree 保持 NextKde/ListenFree 独立仓库，包含私有 PIM/运行时代码。
  前三款统一版本／Release，分别安装卸载；源码已公开，包的可用性取决于对应正式 Release。
  根应用 preset/目标及已拆出的应用源码已移除，旧开关 ON 明确报错。
- 核心安装负责完整 Settings/运行 QML 树；兼容应用入口默认使用 GitHub Release Flatpak 包，
  源码须显式 --backend=source；无认可 Release/runtime 策略则不可用。默认选择日历（含待办功能）、计算器和天气；ListenFree 显式选择。
  生命周期操作不启停服务、不改 MIME 默认关联、不移除旧播放器、不覆盖核心 Settings。
  核心 data-service 仍是 Shell 依赖。
- 不在运行中的合成器热替换/重载 KWin 插件；安装后注销登录或重启。
- 项目验证只在 VM 或托管 CI 执行，保留工作树中无关改动。

## 特权安装边界

`tools/kosctl` 在用户构建目录暂存后安装系统插件。保留所有权/权限检查及目标文件 root 所有权
（`--no-preserve=ownership`），已检查的暂存树不能在使用前变成用户可改写。

SELinux 启用时，`cp -a` 可能把家目录的 `user_home_t` 标签带进 `/usr`，破坏提权程序。
保留有条件的 `cp -Z` 目标重标记；仅 `--no-preserve=context` 不足以阻止全部 xattr 复制。
不向不支持 SELinux 的 `cp` 传 `-Z`。标签在合适的 VM 验证，Ubuntu 验收不能证明 SELinux 路径。

## 外观边界

Shell 外观存于固定状态目录；独立应用经 `ApplicationPreferences` 读取
`QSettings("NextKde", "KosApplications")`。两者尚未自动同步。
`KOS_APPEARANCE` / `KOS_MATERIAL` / `KOS_ACCENT` 环境覆盖是可用桥接点，不代表同步已实现。
可移植应用使用 `KosTextField` 与 `AppTheme`。

## 发布边界

只维护最新正式版。`main` 开发，`release/X.Y` 收补丁及发布准备；Tag 不可变，公开 RC 可选。
选源码、部署、启动服务分开执行。按[发布流程](docs/Releasing.zh-CN.md)操作，取得明确发布授权，
对精确发行提交保留证据，不从旧审计笔记推断运行验证已经完成。

应用目录、第三方源和更新提示的当前契约见[签名目录架构](docs/app-store/SignedCatalog.zh-CN.md)：目录签名和包 SHA-256 必须校验；开发者签名可选，但条目指定发布者时不能降级。应用包来自 GitHub Releases，运行库沿用独立批准的来源策略。
