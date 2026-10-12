# T03 展示副本发布契约 v1

实现：`apps/greeter/companion/resources.py`，Python 3 + Pillow。当前为可运行的隔离发布端库与离线消费夹具，不是已部署的 root 服务。不会自动发布当前私人壁纸。专属安装、认证 IPC、设置页及真实消费端接入由后续集成交付。

桌面适配器必须读取 WallpaperService 实际 `mode`、`fitMode`、`wallpaperUrl`；配置源是 `wallpaper.ini` 的 Wallpaper 组，不读取 Plasma 占位。`wallpaperUrl` 可能由 WallpaperColorSource 回退，因此仅解析 ini.image 不等于获取实际资源。当前入口接受已解析的 mode/fit 与资源字节；调用方在请求账户权限下读取原图，不让特权进程打开用户提交路径。动态/空间模式不执行 QML；本版拒绝非 image，消费侧回退内置渐变及默认头像。fit 允许 crop/fit/stretch/center，crop 固定归一化整图 [0,0,1,1]，输出缩放由 T06/T07 契约补充。

每账户独立调用：`publish(uid, image_bytes, consent=True, notice=NOTICE, mode='image', fit='crop', avatar=None)`。NOTICE 的完整内容是“所选图片和头像将在认证前向这台机器的其他使用者展示。”未明确选择拒绝发布；桌面选图不是授权。这个参数只能由可信适配器从账户选择生成，不能将客户端自报 UID 当身份。生产 broker 必须从经过认证的本地连接获取 UID，并以请求者凭据读取/接收有限字节；授权其他 UID 的账户删除操作只给管理员。库本身不是鉴权边界，禁止把它直接暴露为无鉴权服务。

| 对象 | 生产所有者/权限 | 隔离测试 |
| --- | --- | --- |
| 原图、头像源 | 请求者 UID，保持原权限；特权端不打开源路径 | 生成夹具，由 UID 1000 读取字节 |
| /var/lib/kos-greeter/display（拟议）及父目录 | root；父路径无可写或符号链接祖先；目录 0755 | 临时目录，当前 UID 0755 |
| 每 UID 目录、版本目录 | root 0755，普通账户不可写 | 当前 UID，拒绝 group/other 可写 |
| manifest、处理过 PNG | root 0644，无源路径、EXIF、文本元数据 | 当前 UID，检查所有权、写权限、hash |
| .lock | root 0600 | 当前 UID 0600 |
| 登录前 QML、代码 | 独立只读安装目录，不在展示目录 | 不产生/执行代码 |

系统目录由管理员预置，库不递归创建父目录。测试临时目录不冒充系统所有权验收。消费者应通过受信任只读 broker 或以固定 root 所有权校验的消费端读取；不能以 Greeter UID 初始化当前写入 Store。真正 Greeter/Cover 读端留 T07/T10/T14。

输入 PNG/JPEG，最大 16 MiB，最大 8192 边长、1600 万像素、单帧。完整解码后重新编码 RGB PNG，清除元数据；头像最大 512×512。限制输入和输出大小，拒绝脚本、SVG、路径、代码与任意主题。生产 broker 还应隔离解码进程并限时/限内存，当前库在同步调用进程中解码。

每账户 flock 串行发布/消费/撤销。临时版本→完整解码/hash/尺寸校验→fsync→rename 版本→临时 manifest fsync→原子 replace manifest→目录 fsync。manifest replace 是可见提交点；此前发布失败保留上一个有效 manifest。提交点之后 fsync/清理中断可能已使新版本可见，调用方不能假设异常代表回滚，应 consume/recover 重新确定状态；不回滚新 manifest，避免覆盖并发更新。manifest 仅含 schemaVersion/uid/version/issuedAt/expiresAt/mode/fit/crop/resources；仅允许 wallpaper.png/avatar.png 固定相对文件名。有效期最长七日，默认一天；过期、未知字段、错误版本、路径、hash、尺寸、权限或缺图返回 None。None 表示调用方显示内置渐变/默认头像，不显示上次缓存。

hash 标识处理后副本，不宣称等于带元数据原图的 hash。三阶段最终必须使用同一发布副本。不会把路径/密码写入 manifest 或日志。

撤销同步、撤销图片和账户删除均调用 revoke(uid)：先撤回 manifest 并 fsync，再删除旧版本和临时副本。recover(uid) 可重复执行：校验当前 manifest，仅保留有效引用版本，否则撤回并清空。发布切图后立即清理旧版本；消费夹具在锁内取得整份校验字节，未保留文件引用，不存在磁盘 cache/snapshot。真实消费者须在 reload/撤销事件丢弃内存字节，不能从旧路径重新加载，若保留引用须加入受限引用生命周期和撤销通知；该消费端验收属于 T14，当前不宣称已实现。

恢复操作：发布/清理异常后调用 recover(uid)，然后 consume(uid)；无有效副本返回 None。缺图、外盘移走或 home 未解密在成功发布后不影响副本；再次读取源失败则不调用发布、保留前版，若用户选择撤销必须显式 revoke，不能把读失败当撤销。撤销中断后 manifest 已消失，因此不能新消费；恢复继续清理余留版本。
