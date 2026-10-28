# Controls

Controls shared by multiple standalone applications.

## Compact liquid material and glass numbers

`LiquidCompactSurface` and `LiquidGlassNumber` are opt-in components imported
from nextkdeAppDemo. Their GLSL sources and matching QSB resources ship together.
Weather captures sibling background subtrees for its search/actions, floating
panels and temperature digits, excluding foreground controls to avoid feedback.
Reduced transparency or unavailable GPU sampling uses ordinary solid rendering.
No KWin liquid plugin is required; dimensions and application state remain app-owned.

`LiquidCompactSurface` 和 `LiquidGlassNumber` 是从 nextkdeAppDemo 引入的显式选用组件，
GLSL 源码与对应 QSB 一起提供。天气通过兄弟背景节点为搜索、操作、悬浮面板和温度
数字采样，排除前景控件以避免反馈。减少透明度或无法使用 GPU 采样时回退为普通
实色渲染。不依赖 KWin 液态插件，尺寸和业务状态由应用管理。
