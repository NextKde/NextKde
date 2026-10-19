# 壁纸与会话交接契约

[JSON 示例](handoff.example.json) 是待实现契约草案，不是当前程序支持的配置。

## 发布与消费

桌面侧将选定 KOS 背景发布为系统范围只读的资源副本与版本 manifest。具体安装目录、所有权和发布服务需 T03 安全审查；不能默认让普通用户任意写登录前可执行代码。登录只读副本，无副本时使用内置背景。

登录前只传最小展示描述；会话 wrapper验证后落到用户本会话运行时目录，模式0600、原子写入、消费后清理。运行时路径用真实XDG_RUNTIME_DIR而非硬编码 UID。session ID必须按会话生成，拒绝旧会话复用。

## 字段约束

- schemaVersion：已支持正整数；不兼容版本回退，不猜测。
- issuedAt/expiresAt/sessionId：防止旧数据影响新会话；时间仅用于展示数据过期，不认证。
- resource.sha256：固定内容版本；路径为已发布资源的允许路径，禁止`..`/任意home路径。
- wallpaper.kind：image/theme/spatial；主题ID来自内置白名单，禁止代码字符串。
- output：硬件标识、px、精确Hz、scale、rotation、位置、crop；crop归一化0–1且有界。
- phase：只用于可复现主题；粒子要求snapshot fallback，不承诺恢复GPU内部状态。
- transition：suppressInitialWallpaperTransition=true；UI建议时长允许可访问性覆盖。

所有字段设置长度/数量上限，限制图片尺寸和总解码预算；未知输出重新匹配安全模式。描述不允许password、token、command、dbus address等字段。

## 就绪事件建议

BackgroundResourceReady → BackgroundWindowMapped → FrameSubmitted →（可用时）FramePresented → EssentialDesktopReady → RevealComplete。每事件含sessionId、outputId、resourceHash、monotonic timestamp。资源事件不能代替呈现事件。日志只记事件与非敏感标识。

## 公开资源生命周期

发布接口须检查每账户显式同步选择并说明认证前可见范围；该选择独立于桌面壁纸设置。资源版本记录所属 UID、同步状态及引用关系；展示描述不能自行赋予发布权限。撤销或账户删除后拒绝新消费、撤回 manifest，并使登录端缓存及桥接快照失效；版本替换清理无人引用旧资源，使用中引用结束后清理。发布/清理中断须可恢复，未授权或已撤销一律回退内置背景。路径和哈希校验不能替代同步授权检查。

T06 的独立机器显示策略见 [机器级输出契约](machine-outputs.md) 与 [输出 schema](machine-outputs.schema.json)。规划器是离线配套，尚未接入登录 KWin/表单；不把 handoff 示例当已应用的显示配置。

T09 当前可运行静态子集见 [用户会话交接契约](session-handoff.md)。历史JSON示例不是输入；运行时采用Unix整秒、resource版本ID与hash，不接受资源path。
