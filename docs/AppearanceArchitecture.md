# 全局外观系统架构

> 状态：阶段 1、Dock 形态、Bar 融合与 Dock 窗口动画已实现（2026-08-28）。本文是后续开发和 AI 接续工作的规范来源。

## 1. 当前能力与边界

外观设置分为彼此正交的三个维度：

- **系统外观**：`kos-settings > 显示 > 色彩模式` 调用 KDE 的 `LayanLight / Layan` 色彩方案。目前不写入本项目配置。
- **玻璃材质**：`blurStrength` 与 `liquidStrength`，范围均为 `0.0...1.0`。它们由现有液态玻璃表面消费，并同步给自定义 KWin `glass` effect；不会修改 KDE 自带的 `Effect-blur`。
- **Shell 形态**：`shellStyle`，值为 `windows12 | macos | material`。设置页已可选择并持久化；Dock 已接入形态 Token，DeskCenter 尚未接入。Bar 不随形态分叉。
- **Bar 布局**：`barIntegratedWithDock` 是独立布尔配置。仅当 Dock 位于底部时生效；开启后顶部 Bar 将 `exclusiveZone`、启动器顶部边距和 DeskCenter 顶部安全区归零/收缩，再将时间与系统状态内容装入 Dock。
- **Dock 窗口动画**：`dockWindowAnimationStyle`，值为 `scale | genie`，默认 `scale`。由 `DockWindowAnimationTargetService` 向 KWin dock-window-animation effect 发布图标矩形，设置页可选择并持久化。

主题选择会立即更新 Dock 的几何、间距、状态背景、运行指示器和动效。Bar 始终保持统一视觉；是否融入 Dock 完全由独立开关决定。后续只需继续接入 DeskCenter。

## 2. 所有权和依赖方向

```text
kos-settings Theme/Display page
        │ SettingsBridge（C++，启动 qs ipc call）
        ▼
DesktopEnvironment.qml / appearance-settings
        │
        ▼
AppearanceConfigService ──────► state/appearance/config.json
        │                         custom KWin glass effect
        ▼
AppearanceTokens
   ├── dock
   ├── bar
   ├── widget
   ├── glass
   └── motion
        │
        ▼
Dock（已接入，可托管 Bar 内容） / Bar（统一视觉） / DeskCenter（后续接入）
```

职责约束：

1. `AppearanceConfigService` 是校验、默认值、迁移和持久化的唯一所有者。
2. `AppearanceTokens` 只把配置映射成语义值，不执行 IO，也不拥有业务数据。
3. 消费组件读取 Token，不应散落 `shellStyle === ...` 分支。
4. Dock 的固定项、尺寸、位置、图标模式和显示策略仍归 `DockConfigService` 所有；切换形态不得覆盖这些用户设置。
5. 独立进程 `apps/settings` 不允许 import `desktop/`，只通过 IPC 读写。

## 3. 文件索引

| 文件 | 责任 |
| --- | --- |
| `desktop/modules/common/AppearanceConfigService.qml` | schema、校验、迁移、保存、Glass effect 同步 |
| `desktop/modules/common/AppearanceTokens.qml` | 五组只读语义 Token |
| `desktop/modules/common/qmldir` | 注册公共组件与 singleton |
| `desktop/modules/common/SystemIconResolver.qml` | 将语义角色、状态和回退候选解析为当前系统主题图标 |
| `desktop/modules/common/SystemIcon.qml` | 统一的小型状态/菜单图标渲染组件 |
| `desktop/DesktopEnvironment.qml` | `appearance-settings` IPC target |
| `apps/settings/src/main.cpp` | Settings 到 Quickshell IPC 的进程桥 |
| `apps/settings/main.qml` | “显示”和“主题”页面，包括 Bar 融合开关 |
| `desktop/modules/bar/BarDateStatus.qml` | 独立顶部 Bar 的时间日期内容 |
| `desktop/modules/bar/BarStatusArea.qml` | 可复用的托盘、网络、电池与控制中心内容；向 Dock 提供稳定的单行最大宽度预算 |
| `desktop/modules/bar/SysTray.qml` | 系统托盘宿主；原生托盘项与 Wi‑Fi、电池、设置、控制中心共用连续 Grid，融合 Dock 高度达到 48px 时自动折为两行 |
| `desktop/modules/bar/DockStatusSvgIcon.qml` | Wi‑Fi、设置、控制中心的项目 SVG 遮罩渲染器；彩色模式输出白色，黑白模式叠加统一透明度，染色模式使用公共 tonal 色与阴影 |
| `desktop/modules/bar/BarWindow.qml` | 独立顶栏的 layer-shell 几何宿主 |
| `desktop/modules/dock/DockInfoCarousel.qml` | Dock 音乐、天气、融合时钟、常驻温度的固定宽度轮播宿主 |
| `desktop/modules/dock/DockSideInfoCarousel.qml` | 左/右 Dock 的单行信息轮播；父 Row 旋转 90°，面板反向旋转保持文字正立，沿边占两个图标位 |
| `desktop/modules/dock/DockMetricGlyph.qml` | Dock 信息卡的主题无关高对比度字形（温度/时钟），Canvas/仓库 SVG 绘制纯白像素 |
| `desktop/modules/dock/DockClockWidget.qml` | 左侧为液态时间与日期，右侧为带图标的日落/日出时间；使用与天气/音乐同规格的壁纸环境色卡片 |
| `desktop/modules/dock/DockTemperatureWidget.qml` | 常驻 Dock 温度页；左侧用白色加粗的系统主题温度图标、蓝/红状态点和紧凑上下行显示平均/最高温度，右侧复用 DeskCenter 的 CPU/内存/存储三环语义与配色；只消费公共 `MetricsService` 快照 |
| `desktop/modules/dock/DockContainer.qml` | Token 驱动的 Dock 自适应比例和圆角 |
| `desktop/modules/dock/DockWindow.qml` | Token 驱动的贴边距离与玻璃环境系数 |
| `desktop/modules/dock/DockIcon.qml` | Token 驱动的状态背景、指示器、放大与位移 |
| `desktop/modules/dock/DockAnimation.qml` | 将 motion Token 投影到 Dock 动效语义 |
| `desktop/modules/dock/DockWindowAnimationTargetService.qml` | 向 KWin dock-window-animation effect 发布合成器全局坐标下的 Dock 图标矩形（采样自渲染后的 AppIcon），驱动 `dockWindowAnimationStyle` |

### 3.1 系统图标契约

Shell 小图标不得引用某个图标包的绝对路径，也不得把 Font Awesome/Nerd Font 字符作为长期业务接口。消费者只声明稳定的语义角色：

```qml
SystemIcon { role: "settings" }
SystemIcon { role: "controlCenter" }
```

`SystemIconResolver` 集中维护角色到 freedesktop/KDE 图标名称候选的映射，并依次使用 `Quickshell.hasThemeIcon()` 与 `Quickshell.iconPath()` 从当前系统主题及其继承主题解析。动态网络状态统一调用 `networkCandidates(connectionType, deviceState, signalStrength, limited)`，业务组件不得重复信号等级映射。

当前消费者包括 Bar 的 CPU 温度等系统语义图标。Dock 状态区的 Wi‑Fi、设置和控制中心属于项目视觉标识例外，固定使用仓库 SVG 并由 `DockStatusSvgIcon` 着色；电池继续保留能够表达电量和充电状态的专用 QML 绘制。右键菜单仍应将字体字符字段迁移为 `iconRole`，由 `MenuItemRow` 使用 `SystemIcon` 渲染。应用自身图标、媒体封面和文件缩略图不属于这一语义图标契约。

`shellStyle` 暂时不会改写 KDE 图标主题。未来三套 Shell 形态接入系统图标包切换后，仍只需更新系统主题；`IconThemeReloadService` 检测 `kdeglobals` 后软重载，所有 `SystemIcon` 消费者自动重新解析，不需要修改业务组件。

## 4. 持久化契约

运行时路径：

```text
Quickshell.stateDir + "/appearance/config.json"
```

schema 4：

```json
{
  "version": 4,
  "blurStrength": 0.42,
  "liquidStrength": 1.0,
  "shellStyle": "macos",
  "barIntegratedWithDock": false,
  "dockWindowAnimationStyle": "scale"
}
```

- 默认 `shellStyle` 为 `macos`，因为它最接近引入主题前的现有 Shell 形态，升级不会突然重排界面。
- schema 1 只有两个强度字段，schema 2 新增 `shellStyle`，schema 3 新增 `barIntegratedWithDock`，schema 4 新增 `dockWindowAnimationStyle`。升级时保留原值，补入缺失字段的默认值，并防抖写回最新 schema。
- 非法或缺失的 `shellStyle` 回退为 `macos` 并写回；非法或缺失的 `dockWindowAnimationStyle` 回退为 `scale`；非法强度不会覆盖内存默认值。
- 强度输入会裁剪到 `0...1`；未知形态输入被拒绝。
- 保存采用 350ms 防抖，并通过临时文件后 `mv` 原子替换。
- `resetStrengths()` 只恢复 `0.42 / 1.0`，不重置主题形态或 Dock 数据。

## 5. IPC 契约

target：`appearance-settings`。所有更新都返回完整 JSON snapshot。

| 调用 | 参数 | 作用 |
| --- | --- | --- |
| `snapshot` | 无 | 读取完整外观状态 |
| `updateBlurStrength` | real | 更新模糊强度 |
| `updateLiquidStrength` | real | 更新液态强度 |
| `updateShellStyle` | string | 更新 Shell 形态 |
| `updateBarIntegratedWithDock` | bool | 更新 Bar/Dock 宿主策略 |
| `updateDockWindowAnimationStyle` | string | 更新 Dock 窗口动画风格（`scale`/`genie`） |
| `resetStrengths` | 无 | 只重置两项玻璃强度 |

snapshot 示例：

```json
{
  "blurStrength": 0.42,
  "liquidStrength": 1,
  "shellStyle": "macos",
  "barIntegratedWithDock": false,
  "dockWindowAnimationStyle": "scale",
  "tokenVersion": 4
}
```

手动检查：

```bash
quickshell --path /home/amao/OneDrive/quickshell ipc call appearance-settings snapshot
quickshell --path /home/amao/OneDrive/quickshell ipc call appearance-settings updateShellStyle material
```

`SettingsBridge` 会拒绝缺少任一核心字段的响应，并用 `lastError` 告知 QML。增加 snapshot 字段时应保持向后兼容；删除或重命名字段需要同时升级桥接层。

## 6. AppearanceTokens v3

数值单位：`height/radius/gap` 与 duration 分别为逻辑像素和毫秒；以 `Ratio` 结尾的值乘以消费组件的 `iconSize` 或基准高度。字符串用于选择布局策略或视觉 delegate。

### Dock

| Token | Windows 12 | macOS | Material |
| --- | --- | --- | --- |
| `form` | `taskbar` | `floatingDock` | `navigationDock` |
| `position` | `bottom` | `bottom` | `bottom` |
| `radiusRatio` | 0.20 | 0.45 | 0.34 |
| `horizontalPaddingRatio` | 0.24 | 0.40 | 0.32 |
| `verticalPaddingRatio` | 0.12 | 0.20 | 0.16 |
| `itemSpacingRatio` | 0.07 | 0.09 | 0.08 |
| `dividerMarginRatio` | 0.16 | 0.20 | 0.18 |
| `edgeMargin` | 0 | 5 | 8 |
| `workspaceGap` | 0 | 5 | 8 |
| `indicatorStyle` | `underline` | `dot` | `tonal` |
| `indicatorLengthRatio` | 0.42 | 0.13 | 0.34 |
| `indicatorThicknessRatio` | 0.07 | 0.13 | 0.07 |
| `activeRadiusRatio` | 0.18 | 0.30 | 0.28 |
| `activeBackgroundMode` | `subtle` | `glass` | `tonal` |
| `magnificationEnabled` | false | true | false |
| `hoverScale` | 1.00 | 1.20 | 1.00 |
| `hoverLiftRatio` | 0.00 | 0.08 | 0.00 |

### Bar 与桌面组件

| Token | Windows 12 | macOS | Material |
| --- | --- | --- | --- |
| `bar.placement` | top | top | top |
| `bar.height` | 35 | 35 | 35 |
| `bar.radius` | 0 | 0 | 0 |
| `bar.surfaceMode` | transparent | transparent | transparent |
| `bar.unifiedWithDock` | 独立配置 | 独立配置 | 独立配置 |
| `widget.radius` | 12 | 26 | 20 |
| `widget.gap` | 8 | 10 | 12 |
| `widget.elevation` | 2 | 1 | 3 |
| `widget.surfaceMode` | acrylic | glass | tonal |

### Glass 与 motion

`glass.blurStrength` 和 `glass.liquidStrength` 直接投影配置。局部表面可以乘以下列系数，但不得重新定义全局强度。

| Token | Windows 12 | macOS | Material |
| --- | --- | --- | --- |
| `glass.highlightMultiplier` | 0.72 | 1.00 | 0.55 |
| `glass.ambientMultiplier` | 0.85 | 1.00 | 0.70 |
| `motion.fastDuration` | 120 | 135 | 100 |
| `motion.normalDuration` | 180 | 200 | 220 |
| `motion.slowDuration` | 260 | 360 | 300 |
| `motion.standardEasing` | OutCubic | OutCubic | OutQuart |
| `motion.springEnabled` | false | true | false |

Token schema 版本为 `AppearanceTokens.version === 4`。v2 新增 Dock 状态、边缘和指示器 Token；v3 将 Bar 统一为单一视觉契约，并把 `unifiedWithDock` 改为独立配置投影；v4 随 Bar/Dock 融合宿主实现提升版本号，Token 表语义未变。修改现有 Token 语义或删除字段时必须升版本。

## 7. 消费规则

推荐写法：

```qml
radius: iconSize * AppearanceTokens.dock.radiusRatio
spacing: iconSize * AppearanceTokens.dock.itemSpacingRatio
Behavior on opacity {
    NumberAnimation { duration: AppearanceTokens.motion.fastDuration }
}
```

不要在 surface 内复制这类逻辑：

```qml
// 禁止：会形成第二套主题映射。
radius: AppearanceConfigService.shellStyle === "macos" ? 24 : 12
```

接入时还要遵守：

- Token 决定视觉形态，现有业务 service 决定数据和行为。
- 主题热切换不能重建应用模型、改变 pinned 顺序或清除窗口状态。
- `bar.unifiedWithDock` 是独立布局要求，不是把两个 layer-shell 窗口简单叠在底部。开启后无论 Dock 位于底部、左侧还是右侧，顶部 Bar surface 都把排斥区设为零并隐藏。底部 Dock 把时间放入信息轮播、状态区作为右侧附件；左/右 Dock 使用 `DockSideInfoCarousel` 单行轮播（父 Row 旋转 90°、内容反向旋转保持文字正立，沿边占两个图标位），状态序列沿侧边排列。
- 融合宿主必须按 Dock 边缘决定弹窗方向：底部向上、左侧向右、右侧向左，包括托盘菜单/提示、网络、蓝牙和电池；控制中心卡片组在左侧 Dock 时镜像到屏幕左侧。恢复独立顶部 Bar 后仍向下展开。
- Bar 状态区的 CPU 等通用语义图标通过 `SystemIcon`/`SystemIconResolver` 消费当前系统图标主题。Wi‑Fi、设置、控制中心使用项目自绘 SVG：独立 Bar 与 Dock `color` 模式输出白色，`grayscale` 叠加与应用图标相同的 `iconOpacity`，`tint` 将 72% 基准亮度投影到 `iconTintColor` 后再叠加轻微暗影，避免纯色 SVG 比其他图标突兀。电池保留电量绘制，但在 Dock `tint` 模式下使用同一 tonal 色、透明度和阴影。快捷状态组只保留布局 padding，不绘制整组白色蒙层。
- Dock 的 `iconMode` 同时约束 Dock 内的应用图标、原生 SystemTray 图标、自绘 Wi‑Fi/设置/控制中心图标，以及天气/时间/温度卡片背景。`color` 保留内容原色；`grayscale` 按亮度去色；`tint` 先保留亮度层级再投影到 `iconTintColor`。该规则只在状态区被 Dock 承载时作用于 Bar 组件，独立顶部 Bar 仍使用系统主题原色。电池是状态相关的专用绘制，明确排除在此投影之外。
- 融合模式的状态托盘把原生 SystemTray 项与 Wi‑Fi、电池、设置、控制中心组成一条连续序列，以 `48px` 可用高度为两行阈值：至少两个项目且达到阈值时按列连续填入两行，否则保持单行；独立顶部 Bar 永远单行。Dock 温度页在融合与非融合模式下都保留；融合后状态附件隐藏重复的 CPU 摘要，恢复独立 Bar 后摘要重新显示。Dock 高度求解使用 `BarStatusArea.layoutMaximumWidth` 的单行最大宽度，最终宽度才采用折行后的实际宽度，禁止让行数反向参与高度求解形成 binding loop。
- Dock 温度页、独立 Bar 温度摘要和 DeskCenter 温度区必须只读取公共 `MetricsService`。该 singleton 从 `shell-data-service` 的原子快照取值；任何 surface 都不得另外读取 `/proc`、`/sys` 或启动新的采样进程。快照尚未就绪时 Dock 页仍占位并显示 `--`，不能从轮播中消失。
- Material 的 `tonal` 需要从系统 palette/壁纸 palette 派生，不得在组件里硬编码紫色。设置页紫色仅用于预览识别。
- 可读性遮罩和最小对比度优先于透明度；局部 multiplier 只允许弱化或增强材质细节。

## 8. 设置页行为

- 侧栏顺序为：显示 → 主题 → Dock。
- “显示”保留系统明暗与玻璃强度；“主题”只选择 Shell 形态，避免把配色与形态耦合。
- 三张卡片展示 Bar、Dock 和桌面卡片的形态缩略图；点击后同步调用 IPC，成功响应决定最终选中态。
- 桌面 Shell 未运行、IPC 超时或响应不完整时，页面显示 `SettingsBridge.lastError`，不得伪造保存成功。
- 当前提示明确说明 Dock 和 Bar 已接入，DeskCenter 仍待后续阶段接入。

## 9. 后续实施顺序

1. **Dock（已完成第一轮）**：圆角、padding、spacing、indicator、状态背景和 motion 已接入；位置、尺寸、显示策略及模型保持用户所有。
2. **Bar 融合（已实现）**：Bar 保持统一视觉；底部 Dock 将时间作为音乐/天气轮播的一页，并托管系统状态；侧边 Dock 自动回退顶部 Bar。
3. **DeskCenter**：只替换卡片容器、gap、surface/elevation，不触碰天气、文件、活动等数据逻辑。
4. **Dock 收口**：完成三风格 × 独立/融合 Bar 的视觉回归。
5. **全局收口**：搜索并移除已被 Token 取代的散落常量，增加三风格 × 明暗模式视觉回归。

每完成一个 surface，更新本文的“当前能力与边界”和 Token 消费清单，再开放下一 surface。

## 10. 验证清单

```bash
qmllint apps/settings/main.qml
qmllint desktop/modules/common/AppearanceConfigService.qml \
  desktop/modules/common/AppearanceTokens.qml desktop/DesktopEnvironment.qml
cmake --build apps/settings/build
node desktop/modules/dock/test_adaptive.mjs
node desktop/modules/dock/test_autohide.mjs
git diff --check
```

运行验证需按 `.agents/skills/verify/SKILL.md` 启动独立 Quickshell 实例，确认 `Configuration Loaded`，检查新错误后只停止该验证实例。IPC 测试切换三个枚举后必须恢复测试前的 `shellStyle`，不得改动用户玻璃强度。

## 11. AI 接续检查表

开始后续外观工作前，AI 应依次：

1. 阅读本文。
2. 检查工作区未提交修改，避免覆盖用户正在开发的 Dock/Bar/桌面文件。
3. 读取当前运行时 snapshot，不猜测用户选择。
4. 一次只让一个主要 surface 消费 Token，并保留原业务行为。
5. 运行静态、构建、单元和独立 Quickshell 验证。
6. 更新本文的状态、Token 表和已接入组件列表。
