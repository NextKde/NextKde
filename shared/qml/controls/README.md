# Controls

Reusable controls for the Shell and Settings. Independent applications maintain
their own shared-control dependencies in their owning repositories.

## Compact liquid material and glass numbers

`LiquidCompactSurface` and `LiquidGlassNumber` are opt-in components imported
from nextkdeAppDemo. Their GLSL sources and matching QSB resources ship together.
Consumers capture sibling background subtrees, excluding foreground controls to
avoid feedback. Core retains the compact material and number controls for its
interaction regression fixtures; Weather is maintained externally.
Reduced transparency or unavailable GPU sampling uses ordinary solid rendering.
No KWin liquid plugin is required; dimensions and application state remain app-owned.

`LiquidCompactSurface` 和 `LiquidGlassNumber` 是从 nextkdeAppDemo 引入的显式选用组件，
GLSL 源码与对应 QSB 一起提供。调用方通过兄弟背景节点采样，排除前景控件以避免
反馈；核心保留这些控件供交互回归夹具使用，天气应用在独立仓库维护。
减少透明度或无法使用 GPU 采样时回退为普通
实色渲染。不依赖 KWin 液态插件，尺寸和业务状态由应用管理。
