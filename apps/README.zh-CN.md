# 独立桌面应用

**[English](README.md) | [中文](README.zh-CN.md)**

核心 `apps/` 源码树保留 `settings/`、`lockscreen/` 和 `sddm/` 主题（暂无支持的 SDDM 安装入口）。日历（含待办功能）、计算器、天气和
ListenFree 均独立于 core；前三款共用 kos-apps 仓库、版本和 Release，但分别安装／更新／卸载：

| 应用 | 源码、Release 与应用测试 |
| --- | --- |
| 日历（内置待办功能） | [NextKde/kos-apps](https://github.com/NextKde/kos-apps) |
| 计算器 | [NextKde/kos-apps](https://github.com/NextKde/kos-apps) |
| 天气 | [NextKde/kos-apps](https://github.com/NextKde/kos-apps) |
| ListenFree | [NextKde/ListenFree](https://github.com/NextKde/ListenFree) |

根构建不再编译这些应用、其私有运行时或 PIM 服务，应用 CMake preset 已移除。
启用原 `KOS_BUILD_CALENDAR`、`KOS_BUILD_TODO`、`KOS_BUILD_CALCULATOR`、
`KOS_BUILD_WEATHER` 或 `KOS_BUILD_LISTENFREE` 会明确报错并提示迁移。
请在对应独立仓库构建和贡献。切换期间保留的源码目录不是备用构建/安装路径，
独立验收门槛通过前不得删除。

前三款源码目录与应用 ID 为 `apps/org.nextks.calendar`、`apps/org.nextks.calculator`、
`apps/org.nextks.weather`（ID 去掉 `apps/`）。新远端尚未创建／推送，旧仓库保留历史。
旧 `org.nextkde.*` Flatpak 不自动改名、卸载或迁移数据。

## 安装与生命周期

```sh
./tools/kosctl install apps
./tools/kosctl install apps --app calendar
./tools/kosctl install apps --with-listenfree
./tools/kosctl install apps check-update --app weather
./tools/kosctl install apps update --app weather
./tools/kosctl install apps status --app calendar
./tools/kosctl install apps uninstall --app calculator
```

`tools/install-apps.sh` 是相同命令的兼容分发入口。默认选择日历（含待办）、
计算器和天气，ListenFree 必须显式选择。`--app todo` 是日历的别名；
`--update`、`--uninstall` 是对应生命周期动作的别名。
修改操作要求终端确认或 `--yes`。默认经 `kos-apps` 使用与 Settings 相同的用户级 Flatpak 后端，
应用包通过 GitHub Releases 发布，签名目录由 [appCatalog](https://github.com/NextKde/appCatalog) 提供。SHA-256 必须校验，开发者签名可选，但已固定发布者的条目必须验签。明确安装/更新时可为缺失依赖准备已批准的 Flathub runtime 源；不要求应用上架 Flathub，不允许目录添加任意运行库源。实际可用性取决于对应正式 Release，不静默回退源码构建。
历史兼容／开发源码入口必须显式 `--backend=source`；`--app APP --version X.Y.Z` 及构建依赖 `check` 仅用于源码模式。
`--with-listenfree-video` 会明确拒绝；自定义视频功能请按独立 ListenFree
仓库指南构建，不能覆盖稳定 Release 清单的功能选择。

Flatpak 管理安装记录，外部 Flatpak 工具可卸载同一 ref。GitHub 包更新由 Settings／CLI 发现，
无在线 origin 时不承诺 Discover／`flatpak update` 自动发现新版。libflatpak 可能留下本地 origin／公钥记录，
即便随后拒绝事务；runtime 使用独立批准的固定来源。唯一用户级 Flatpak
状态查询／卸载不要求发布者认可；普通卸载保留个人数据，不自动迁移旧安装。

显式源码模式从固定 NextKde 仓库下载稳定 **源码** Release，在本地编译；其私有所有权记录
不是 Discover 软件包。两种模式均不回退本仓库源码或开发分支；批量操作遇错即停，保留已完成项。
上架、第三方源、自动更新和 Qt runtime 打包见[签名目录指南](../docs/app-store/SignedCatalog.zh-CN.md)。
完整边界见[生命周期与信任契约](../docs/app-store/IndependentApps.zh-CN.md)。

核心 `services/data-service` 仍是 Shell 依赖，保留共享天气能力和 Go 测试。
日历 PIM 与应用专有测试由独立仓库负责。核心 CI 检查独立安装器和发布契约，
不再构建过时的单仓库应用目录。剩余核心门槛见[开发指南](../docs/Development.zh-CN.md)。
