# T12 动态与空间壁纸静态接点

当前实现选择静态回退，不传输 phase/GPU 状态、不声称逐帧连续。既有 T09 schema 保持 `kind=image, phase=null`。用户授权发布后，Greeter、Cover 和正式桌面使用 T03 的同一版本图片、SHA256、fit、居中裁剪及共享 StaticWallpaperImage。未授权时仍用 `#16283b`。发布不是桌面选图的自动副作用。

## 支持表与源码证据

| 内置主题/模式 | 时间与随机性 | 完整状态恢复 | 本次接点 |
| --- | --- | --- | --- |
| starfield | PhysicalSceneBackdrop 使用 phase；FlowParticleField 的递归 RGBA32F 纹理依赖上一帧、delta、障碍和指针，无外部 seed API | phase 不够；没有多次 GPU 重启帧比较，未测 | app 自带 assets/preview.png |
| weather | 与 starfield 同类模拟，另依赖天气、风、昼夜参数 | phase 不够，天气状态也未纳入协议 | app 自带 assets/preview.png |
| blackhole | CinematicBlackHole 使用固定 plate/noise 与 phase、pointer；其他分支仍有输入 | 时间函数候选；完整同输出重启帧比较未测，不启用恢复 | app 自带 assets/preview.png |
| forest | NatureWallpaper/ForestFireflies 使用固定 hash(i)、phase、pointer/clickPulse | 固定索引 hash 不等于可配置随机 seed；同输入函数可分析，GPU帧比较未测 | app 自带 assets/preview.png |
| underwater | NatureWallpaper 的 time/camera/shader；共享代码包含森林分支 | GPU帧比较未测 | app 自带 assets/preview.png |
| 空间 image | 桌面现有深度/分层/mesh与鼠标视角 | 不传送 GPU/相机状态 | 已授权原始二维图片，中性视角；不需要深度素材 |
| 第三方/未知 themeId | 不可信 packResolver/QML | 不执行、不导入 | 1×1 固定色 PNG，stretch |

源码位于 `shared/qml/wallpapers/themes/<id>/`。以上是源码分类，不是新采集的 GPU 重放实验。所有主题均明确降级；T12 不创建未验证的 phase 连续路径。未来如启用恢复，必须固定输出、时间、种子、天气和交互输入，比较多次进程重启的背景帧；递归 GPU 模拟须保存完整状态或仍静态化。

## 资产与隐私

`companion/kos_wallpaper.py` 在账户权限下先校验每账户明确同意，再读取当前模式。主题只在五个固定 ID 中选已存在的预生成 preview PNG，并与 `theme-files.json` 的 SHA256 比较。它不加载主题 QML，不调用屏幕截图 API、不创建模型/推理进程、不接收任意主题资源路径。已有 preview 是预生成展示图，不冒充动画终帧截图。空间模式直接规范化二维原图；不从已含用户窗口的屏幕采集，不读取或生成深度模型。

没有背景离屏 snapshot 的生产采集功能；本次采用无需捕获的安全静态资产。如果未来实现 snapshot，必须只对背景专用离屏 Item `grabToImage`，不得对屏幕/桌面根窗口操作，按同 crop 发布并重新取得公开展示授权。

发布仍由已有安装/显式同步流程执行，manifest 保持 image，不新增命令字段。撤销/替换/损坏/过期由 T03 Reader 安全拒绝；安装时内置 fallback 缺失或 hash 不匹配明确报错，既有版本不被冒充为新版本。不要通过修改资源 hash 清单来掩盖损坏。

## 桌面消费与恢复

SessionEntryService 的生产 verifier 读取当前 UID 的公开 store；同时核对版本、hash、fit，只返回同一份已校验字节。不会因动态模式遗留 image 路径而超时等待错误原图。静态接点在 SpatialWallpaperWindow 内用独立 WallpaperImageLayer（transition=none）绘制，只有 Image.Ready、过渡结束且该输出 frameSwapped 后登记；主题/空间层和其前景在静态接点期间不绘制。全输出与 bar/Dock 就绪后沿用 T11 揭幕。frameSwapped 仍只是提交。

揭幕后保持接点，直到用户选择壁纸/主题、修改 fit/mode/takeover 或空间开关，恢复原日常偏好。揭幕后打开常规壁纸预览也解除接点，随后由已有预览提交/取消流程恢复配置。这避免静态接点在揭幕后立即跳到动态画面。默认固定色也抑制前景。发布失效且桌面尚未校验成功时不发 ready，沿用桌面 12 秒和 Cover 15 秒撤罩；不能用失败图片宣称一致背景。已驻留纹理在揭幕后即时撤销清理的完整 A18 仍属 T14 消费端生命周期验收，本卡不宣称通过。

人工撤罩：`qs -p /绝对安装路径/apps/greeter/cover.qml ipc call cover abort`；进程卡死使用相同路径的 `qs -p ... kill`。未执行系统安装、服务切换或真实认证。

## 预算

沿用 T03：输入/编码 PNG ≤16 MiB、≤1600万像素、单边≤8192；不接受动画输入。五个实际预生成资产规范化后为 0.27–2.72 MiB、最大 1620×1080 或1672×941，尺寸/耗时见 T12 fallback.log。测量包含 prepare/publish/多次consume与负例，不能当作首帧延迟。

上界估算：单张1600万像素 RGB约45.8 MiB，RGBA约61 MiB；base64≤21.34 MiB，规范化解码/编码可同时持有多份缓冲。该上界是限制与估算，不是内存峰值实测。桌面共享静态解码按每输出逻辑尺寸×DPR×1.06；2560×1600 输出一个 RGBA buffer约17.6 MiB，双缓冲约35.1 MiB/输出，实际 GPU 分配未测。登录不运行模拟/深度推理，本次不新增 GPU 状态纹理。性能和物理显示验证留 T13/T14，不将上述估算作为其通过证据。
