# KOS Bridge 重构方案

## 目标

将所有 KWin Effect 功能合并到一个统一的 `kos-bridge` 插件中，除了窗口装饰（`kos-decoration`，KDecoration3 插件）保持独立。

## 当前插件结构

```
kwin/
├── context-menu-input/        # KWin Effect: 上下文菜单输入
├── dock-window-animation/     # KWin Effect: 停靠窗口动画
├── kos-bridge/                # KWin Effect: 窗口按钮面板
└── kos-decoration/            # KDecoration3: 标题栏，不画按钮
```

## 目标插件结构

```
kwin/
├── kos-decoration/            # 保持独立（KDecoration3：只画标题栏和标题，按钮由 kos-bridge 画）
└── kos-bridge/                # 新的统一 Effect 插件
    ├── CMakeLists.txt
    ├── metadata.json
    ├── main.cpp
    ├── bridge.h/cpp           # 主入口，管理子效果
    ├── contextmenu/           # 上下文菜单模块
    ├── dockanimation/         # 停靠窗口动画模块
    └── windowbuttons/         # 新的按钮覆盖模块
```

## 重构步骤

### 阶段 1: 创建 kos-bridge 框架

1. ✅ 创建 `kos-bridge/` 目录结构
2. ✅ 创建 `CMakeLists.txt`
3. ✅ 创建 `metadata.json`
4. ✅ 创建 `main.cpp` 入口
5. ✅ 创建 `bridge.h/cpp` 主桥接类

### 阶段 2: 迁移上下文菜单功能

1. 创建 `contextmenu/contextmenueffect.h`
2. 从 `context-menu-input/contextmenuinputeffect.cpp` 迁移代码
3. 调整命名空间和类名
4. 更新 D-Bus 接口

**关键迁移点：**
- 原 `ContextMenuInputEffect` → `ContextMenuEffect`
- 原 `ContextMenuPointerSpy` 保持不变
- D-Bus 路径从 `/KOSContextMenuInput` 改为 `/KOSBridge`

### 阶段 3: 迁移停靠窗口动画功能

1. 创建 `dockanimation/dockanimationeffect.h`
2. 从 `dock-window-animation/dockwindowanimationeffect.cpp` 迁移代码
3. 调整命名空间和类名
4. 更新 D-Bus 接口

**关键迁移点：**
- 原 `DockWindowAnimationEffect` → `DockAnimationEffect`
- 继承自 `KWin::OffscreenEffect`
- 保留动画状态机逻辑

### 阶段 4: 实现窗口按钮覆盖功能

1. ✅ 创建 `windowbuttons/windowbuttonoverlay.h/cpp`
2. ✅ 创建 `windowbuttons/windowbuttonrenderer.h/cpp`
3. 实现鼠标事件处理
4. 实现按钮渲染
5. 实现窗口操作（关闭/最小化/最大化）

**关键实现点：**
- 使用 `KWin::input()` 获取鼠标事件
- 使用 `QPainter` 绘制按钮
- 支持 SSD 和 CSD 窗口

### 阶段 5: 更新构建配置

1. ✅ 创建 `packaging/nix/kwin-kos-bridge.nix`
2. 更新 `flake.nix` 添加新的包
3. 移除旧的 nix 配置（可选）

### 阶段 6: 测试和验证

1. 编译测试
2. 功能测试
3. 性能测试
4. 文档更新

## 代码迁移指南

### 上下文菜单迁移

**原文件：** `context-menu-input/contextmenuinputeffect.cpp`

**新文件：** `kos-bridge/contextmenu/contextmenueffect.cpp`

**主要变化：**
```cpp
// 原代码
namespace KWin {
class ContextMenuInputEffect final : public Effect {
    // ...
};
}

// 新代码
namespace KOS {
class ContextMenuEffect final : public QObject {
    // ...
};
}
```

### 停靠窗口动画迁移

**原文件：** `dock-window-animation/dockwindowanimationeffect.cpp`

**新文件：** `kos-bridge/dockanimation/dockanimationeffect.cpp`

**主要变化：**
```cpp
// 原代码
namespace KWin {
class DockWindowAnimationEffect final : public OffscreenEffect {
    // ...
};
}

// 新代码
namespace KOS {
class DockAnimationEffect final : public KWin::OffscreenEffect {
    // ...
};
}
```

## D-Bus 接口更新

### 原接口

```
/KOSContextMenuInput (org.kos.KWin.ContextMenuInput)
- activeApplicationMenu() -> QVariantMap
- paste()

/KWin/DockWindowAnimation (org.kos.KWin.DockWindowAnimation)
- updateTargets(QString)
- prepareLaunch(QString) -> bool
- status() -> QString
```

### 新接口

```
/KOSBridge (org.kos.KWin.Bridge)
- activeApplicationMenu() -> QVariantMap
- paste()
- updateDockTargets(QString)
- prepareDockLaunch(QString) -> bool
- dockStatus() -> QString
- setWindowButtonStyle(QString)
- setWindowButtonVisibility(QString, bool)
```

## 注意事项

1. **命名空间统一**：所有代码统一使用 `KOS` 命名空间

2. **头文件包含**：注意 KWin 头文件的包含方式可能因版本不同而变化

3. **D-Bus 路径**：更新后需要同步更新 Quickshell 端的 D-Bus 调用

4. **兼容性**：保留旧插件一段时间，确保平滑迁移

5. **测试覆盖**：每个模块需要独立测试，然后测试集成

## 下一步行动

1. 完成窗口按钮覆盖的渲染实现
2. 测试编译
3. 集成到现有 Quickshell 配置
4. 性能优化
5. 文档完善
