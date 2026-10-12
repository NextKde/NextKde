# T07 WallpaperHost 边界（实现）

`apps/greeter/qml/WallpaperHost.qml` 是纯渲染 Item。`WallpaperWindows.qml` 用 Quickshell 的输出列表按屏创建 background layer 窗口，关闭输出会销毁该窗口、Item、Connections 和 Timer；不导入 shell/desktop、天气、window 服务、platform/data 或用户 socket。`wallpaper.qml` 是可独立运行的入口；认证 app 复用相同窗口组件和单一资源状态。

## 输入与资源

- 图片 `source` 仅由可信调用方提供：生产 `WallpaperSource.qml` → `companion/wallpaper.py` 每秒校验固定 `/var/lib/kos/greeter/display` 下 T03 manifest，检查 root 所有权、目录/文件权限、有限 schema、UID、期限、资源 hash 和标准化图像。返回校验后的 data URL，不把用户路径给 Qt 打开。消费端完全只读；缺 UID 不创建目录或锁文件。
- 未配置授权初始UID且尚未选择用户、撤销、过期、损坏、版本错误均清空状态，使用固定 `#16283b`。换用户立即清空，旧 UID 的迟到响应不能替换新状态；读取进程三秒超时停止。图片禁用 Qt cache；正常重新校验最多一秒，读取故障最多三秒后丢弃状态。跨 UID root 存储部署仍归 T14。
- `fitMode`: crop / fit / stretch / center；T03 crop 仅支持 `[0,0,1,1]`，不新引入额外 crop schema。
- `trustedTheme` 仅用于应用管理员编写的可信宿主，不来自发布 manifest。白名单为仓库五种内置主题；`theme.py` 用固定 `theme-files.json` 的 QML/PNG/SVG/QSB 哈希验证完整 bundle，校验成功前不实例化主题。任何文件缺失/损坏、未知主题或三秒未就绪均回退图片/固定背景。版本升级需重新审查主题并更新哈希清单，不能运行时自动信任新文件。
- ThemeWallpaperScene 注入固定 phase=0、foreground=false、economical=true、particleCount=0、空 widgetRects、离屏 pointer/clickPulse，以及中性天气默认值；packResolver=null。主题内部 frameReady 只表示组件的场景资源信号，不能取代 bundle 校验，也不证明 GPU shader 成功或 scanout。动态连续性与主题效果验收留 T12/T14。

## 静态构图

提取 `shared/qml/wallpapers/StaticWallpaperImage.qml`，桌面 WallpaperBuffer 与独立宿主共同使用。保持现有桌面 fillMode、居中、autoTransform、异步及平滑策略；桌面原有过渡与双缓冲不改。解码预算一致为 `ceil(logicalSize * devicePixelRatio * 1.06)`。用逻辑坐标居中，不将逻辑尺寸先舍入到物理尺寸再计算偏移。截图夹具给 grabToImage 传逻辑尺寸，由 Qt 按实际 DPR 转为物理尺寸；不重复乘 DPR。`WallpaperHost.composition` 导出实际 paintedWidth/Height、offset、decodeBudget、decodedSize、dpr。center 保留原桌面的解码预算语义：低 DPR 可能按预算缩小图像，高 DPR 则保留原尺寸，不承诺 center 跨 DPR 构图不变；本卡跨缩放主体稳定性检查只针对 crop。

Quickshell 限制配置根外的相对 QML 导入，因此 `apps/greeter/wallpapers` 是指向共享可信组件的仓库符号链接。隔离测试复制解引用后的资源；后续打包必须把相同资源及 theme 哈希清单安装在配置根内，不依赖用户 home。

## 事件

| 事件 | 意义 | 不能推导 |
| --- | --- | --- |
| decoded / resourceReady | Qt Image.Ready，图片解码完成 | 窗口已映射、已提交或 scanout |
| themeResourceReady | bundle 预检后场景 frameReady | 完整 GPU 状态、实际呈现 |
| windowVisible / KOS_WALLPAPER_WINDOW | Qt/Quickshell backing window 的可见状态 | compositor presentation acknowledgment |
| frameSubmitted / KOS_WALLPAPER_FRAME_SUBMITTED | QQuickWindow.frameSwapped，帧已排队呈现；每次 source/资源就绪后重新计一次 | 显示器实际 scanout、零黑帧 |
| fallback(reason) | 缺图/解码失败、超时、主题拒绝或缺依赖 | 系统登录失败 |
| KOS_WALLPAPER_DESTROYED | 输出实例释放，订阅由 QML 生命周期解除 | 真实物理拔线已测试 |

默认背景的首个 frameSubmitted 可能早于 decoded；decoded 会重置计数，随后再次产生提交事件。下游必须按资源就绪后的提交辨认资源帧，不能取进程启动后的第一条提交事件替代。

本卡不启用系统服务、不切换显示管理器；Cover 和桌面三阶段、presentation-time 和物理拔线仍留后续任务。

## 临时测试的 KOS 发布适配

用户授权的当前账户由 tools/test-greeter.py 在切换前用该账户凭据读取 KOS 的 image/fit 与私有展示选择；T03 Store 发布 root管理临时 app/public-display。只有 helper 所在 app 恰为 `/run/kos-greeter-test/app` 时消费其 config/wallpaper.json 指定的公开初始UID；普通安装仍使用固定 `/var/lib/kos/greeter/display`，不接受环境变量/用户描述切换目录。UID=-1 表示初始选择，实际发布UID只来自root校验配置；选其他账户仍按其UID独立消费，不能复用初始账户图像当作另一账户的资源。公开选择撤销/测试回滚使相应副本失效。最新实现证据见 [KOS自动接入](../evidence/temporary-switch/kos-wallpaper/REPORT.md)，此前T07冻结摘要保留为历史版本。

## 构图与首显修复

真实认证入口仅由 WallpaperWindows 全输出背景层绘图；认证 FloatingWindow 透明，其初始尺寸为 screen 逻辑尺寸，内部 host 仅预载。内部预载 DPR 明确取目标 screen；offscreen 测试与七秒启动兜底仍可在认证窗口绘制。WallpaperSource 初次立即读取，ready 表示已解析当前 UID 的资源或明确回退；以后保持每秒校验。WallpaperHost.resourceSettled 表示空图、Ready、解码错误或三秒超时。首显等待活动屏背景与主预载实例 settled，之后锁存；七秒总门槛兜底避免缺 Loader/就绪事件导致认证永久隐藏。decoded/settled 不代表 compositor presentation 或 scanout。

修复证据见 [构图和首显](../evidence/temporary-switch/wallpaper-startup/REPORT.md)。历史冻结均保留；本增量摘要独立存档。
