# 主题包格式(Theme Pack Format)

主题包是主题市场的分发单位:一个自包含的目录,含清单、入口 QML 和全部资源。
第三方包不 import shell 的任何模块,只依赖一份稳定的属性契约。

**内置主题与包同构**:`shared/qml/wallpapers/themes/<id>/` 下的 5 个内置主题
就是随壳发布的同结构目录(唯一区别是没有 `manifest.json`,id 由宿主
`sceneUrl()` 硬编码)。"内置"只是发布渠道不同,契约与布局完全一致。

## 目录结构

```
<pack-id>/
├── manifest.json     # 必需,清单
├── main.qml          # 必需,入口场景(可用 manifest.entry 改名)
├── preview.png       # 推荐,设置网格/市场卡片缩略图
├── shaders/          # 预编译 .qsb(相对 main.qml 解析)
└── assets/           # 图片等资源
```

## 安装位置

- 用户包:`~/.local/share/kos/wallpaper-themes/<pack-id>/`
- 环境变量 `KOS_WALLPAPER_PACKS` 可覆盖扫描目录(开发用)。
- 壳每 30 秒重扫一次;也可调用 `ThemePackService.rescan()` 立即刷新。
- 官方主题不再以包形式单独分发:内置主题随壳发布在 `themes/` 下,第三方
  主题包由用户自行安装。

## manifest.json

```json
{
  "id": "forest",
  "name": "萤火森林",
  "detail": "月光薄雾、层叠树影与近景萤火",
  "accent": "#B5CE75",
  "version": 1,
  "entry": "main.qml",
  "preview": "preview.png"
}
```

| 字段 | 必需 | 说明 |
|---|---|---|
| `id` | 否(缺省用目录名) | `[A-Za-z0-9_-]+`;与内置主题同 id 时覆盖内置渲染 |
| `name` / `detail` | 否 | UI 文案,缺省用 id |
| `accent` | 否 | `#RRGGBB`,喂给系统配色与 Plasma 占位图;缺省回退壳默认色 |
| `version` | 否 | 整数,缺省 1 |
| `entry` | 否 | 入口 QML 文件名,缺省 `main.qml`;不允许路径分隔符 |
| `preview` | 否 | 缩略图文件名,缺省无;不允许路径分隔符 |

清单解析失败的包会被静默跳过,不影响其他包。

## 根 Item 契约

`entry` 指向的 QML 的**根 Item** 必须声明:

```qml
Item {
    property var host: null      // 宿主由壳在加载后一次性注入,不换对象
    signal frameReady()          // 渲染出一帧可呈现画面时发出
}
```

其余输入一律从 `host.*` 读取(与内置场景的 ThemeSceneContract 相同):

| 属性 | 类型 | 含义 |
|---|---|---|
| `themeId` | string | 主题 id(包场景固定为自己) |
| `phase` | real | 全局动画时钟(秒) |
| `foreground` | bool | true = 前景遍(窗口上方的粒子/视差层),false = 背景遍 |
| `economical` | bool | 省电模式(降粒子数/降分辨率) |
| `particleCount` | int | 期望粒子数 |
| `widgetRects` | list | 桌面卡片矩形(x/y/width/height,表面坐标,最多 8 个) |
| `pointer` | vector4d | (x, y, inside, 0) — x/y 为 UV 坐标 |
| `clickPulse` | vector4d | (x, y, clickPhase, 0) — 点击脉冲,UV 坐标 |
| `weatherCode` | int | WMO 天气码,0 表示无天气数据 |
| `windStrength` / `windDirection` | real | 风(0-1 / 度) |
| `isDay` | bool | 白昼 |
| `weatherAvailable` | bool | 天气服务是否可用 |
| `temperature` | string | 温度文案 |
| `city` | string | 城市文案 |

行为约定:

- 主题切换 = 整个包组件重建(旧实例销毁),不要依赖跨切换的内部状态。
- 被遮挡/离屏/锁屏时壳停止推进 `phase`,场景保留最后一帧即可。
- 桌面空闲(无可见窗口)前壳不推进 `phase`,首帧仍应渲染。
- frameReady 主要供背景遍上报;前景遍不发也可以(与内置一致)。
- **不要在 `Component.onCompleted` 里同步 emit frameReady**——那会早于宿主
  建立信号连接而丢失;用 `Qt.callLater(() => root.frameReady())`。

## 最小示例

```qml
import QtQuick

Item {
    id: root
    property var host: null
    signal frameReady()

    Rectangle {
        anchors.fill: parent
        // 省电模式给纯色,正常模式做一点随时间的渐变。
        color: host && host.economical ? "#101820"
            : Qt.hsla(0.6, 0.4, 0.08 + 0.03 * Math.sin((host ? host.phase : 0)))
    }
    Component.onCompleted: Qt.callLater(() => root.frameReady())
}
```

## 解析优先级

已安装包 > 内置场景(同 id 时包覆盖内置,如官方 forest 包覆盖内置
`NatureScene`)> 兜底 `StarfieldScene`。壳侧校验
(`WallpaperService`/`ThemeWallpaperService`)同时接受内置 id 与已安装包 id。

## 已知限制(上架市场前的既定方向)

- 包内 QML 是任意代码:V1 只面向自建/侧载分发,公开市场需要审核或
  收紧为声明式格式后再开放。
- `.qsb` 按 Qt 版本烘焙;Qt 大版本升级后旧包可能失效,后续在 manifest
  加引擎版本要求。
