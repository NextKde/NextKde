# Shell 图标管理

Shell 的“功能使用哪个图标”集中在
[`ShellIconMap.mjs`](../shell/desktop/modules/common/ShellIconMap.mjs)。
页面只选择功能名、尺寸、颜色和位置，不直接选择字体字形。

## 更换某个功能的图标

修改 `icons` 中对应功能的值，例如：

```js
"controlCenter.nightLight": "sun_haze_fill",
"controlCenter.doNotDisturb": "moon_fill",
"bar.collection.expand": "chevron_left_2",
"bar.collection.collapse": "chevron_right_2",
"notification.dismiss": "xmark",
```

值可以是 `shared/Icons/IconMap.js` 中的字形名、兼容别名，或
`BundledIcons.qml` 中的图片资源名。无需修改页面，也无需重新生成字体。

QML 使用功能名：

```qml
import qs.desktop.modules.common

BundledIcon {
    name: "controlCenter.nightLight"
    size: 18
    color: ThemeService.foregroundColor
}
```

`BundledIcon`、`BundledIcons.has()`、`BundledIcons.source()` 均会先解析功能名。
`AppIcon` 也支持通过 `BundledIcons.source()` 提供的字体图标引用。
旧的直接字形名及 `BundledIcons.roleName(role, state)` 保持兼容；新增界面使用功能名。

| 功能名分组 | 用途 |
| --- | --- |
| `bar.*`、`controlCenter.*` | Bar 入口、控制中心快捷操作 |
| `notification.*` | 通知关闭、删除、展开与收起 |
| `network.*`、`bluetooth.*`、`audio.*`、`battery.*` | 网络、蓝牙、音量和电量状态 |
| `desktop.widget.*`、`dock.widget.*` | 组件编辑器及桌面控件 |
| `desktop.file.*` | 文件类型的字体后备图标 |
| `desktop.menu.*`、`dock.menu.*` | 右键菜单图标及留空策略 |
| `launcher.*`、`search.*`、`overview.*` | 启动器、搜索及窗口总览 |
| `media.*`、`wallpaper.*`、`session.*` | 播放、壁纸及会话操作 |
| `application.*` | 项目自有应用图片及通用后备图标 |

## 菜单留空与尺寸

将某个菜单功能的值设为空字符串，表示不显示图标：

```js
"desktop.menu.rename": "",
"desktop.menu.copy": "edit-copy",
```

桌面和 Dock 菜单通过 `reserveIconSpace: true` 保留统一的图标列，
空白项目的文字仍与其他项目对齐。勾选标记和子菜单箭头分别由
`menu.trailing.checked`、`menu.trailing.submenu` 控制。

功能映射不控制点击范围或排版。`size` 决定字形大小，调用方的
`width`、`height`、`anchors` 决定布局。更换字形时不要用点击区域的大小代替字号。
电量的连续填充依赖当前字体中成对的电池轮廓和填充区域；更换整套电池图案时，
同时调整 `ShellBatteryIcon.qml` 的填充几何。

## 字体与 SVG

单色界面图标使用 `shared/Icons/NextKdeIcons.ttf`。`IconMap.js` 管理
“字形名 → 字符”，`ShellIconMap.mjs` 管理“功能 → 字形名”，两层分别维护。

新增库里没有的单色 SVG 图案时，在 `nextkdeAppDemo/tools/icons` 的规范源中维护，
转换路径并生成字体字形，再一起同步字体、字形映射和 provenance。
不要手改生成的 `IconMap.js`，或只替换字体文件。字形源与许可说明见
[`shared/Icons/README.md`](../shared/Icons/README.md)。

应用品牌图、封面、缩略图和用户图片保留图片渲染。自定义桌面文件夹使用
`DesktopFolderIcon.qml`，组合可变色 SVG 底图与 Emoji，保留文件夹轮廓及自定义图案。
它们无需为了统一调用而转换成普通单色字体。项目自有应用资源的功能选择在
`appArtwork` 中维护，独立文件资源路径在 `artworkSources` 中维护。

系统主题候选名也在同一映射文件的 `themeCandidates()`、`networkCandidates()` 中维护；
`SystemIconResolver.qml` 只负责查询当前系统主题。应用自行提供的图标仍来自
其 `.desktop` 数据，用户覆盖图标仍按用户设置加载。

## 安装与验证

正常安装流程会将目录、字形库及 QML 一起部署到
`~/.config/quickshell/kos/`。安装副本禁用了文件监听，编辑源码后需要重新部署并重启 Shell。

图标运行检查仅在虚拟机中执行：

```sh
python3 tests/icons/run.py
node tests/notification-history/run-icons.mjs
```

字体场景检查功能名解析、刻意留空、品牌图片，以及 Wi-Fi、音量、电池状态。
本机只安装代码，由用户自行检查界面。
