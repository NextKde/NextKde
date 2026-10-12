# 持久安装/回滚脚本交付

2026-10-12，分支 `codex/notification-center-stacks`。用户要求代写编译安装、禁用原默认 Plasma 登录管理器并默认启用 KOS Greeter，以及完整撤回改动的脚本。本次未运行 sudo/系统安装、未切换服务，未改 PAM。

执行者：主代理。独立只读审查代理：`/root/review_persistent_install`。被审范围摘要见 `SHA256SUMS`。

交付：tools/install-greeter.sh、tools/rollback-installed-greeter.sh、tools/greeter-install.py；普通账户构建有限 QML/Python bundle，安装后默认下一次开机 greetd，--activate-now 明确从文字TTY立即切换；已装路径、入口和Shell Cover路径适配。独立 root 恢复副本不依赖源码 checkout。详细命令和真实限制见 apps/greeter/INSTALL.zh-CN.md。

## 执行证据

- 真实普通账户 `--build .build/greeter-install-test --no-wallpaper-sync` 打包通过，没有调用 install。构建仅编译检查Python语法，不启动认证、修改服务或运行测试。
- `install.test.py` 22项隔离测试通过。使用临时root文件树，模拟systemd/logind并阻止未预期命令调用；覆盖启用/别名及权限恢复、files-only、幂等、复制失败/enable失败、快照写失败/链接拒绝、umask077、failed会话及跨bootID、管理员修改保护、恢复失败重试、独立副本、非法bundle/FIFO、升级拒绝、锁、立即启动失败、壁纸24小时刷新/撤回、getty恢复、手动failed会话清理、临时测试冲突、用户管理器局部reload。
- handoff.test.py 与 wallpaper.test.py 原契约回归通过。
- switch-scripts.test.py 原临时流程回归：已装路径扩展后，原单等号路径替换夹具失配，首次出现一个前端超时；修正夹具匹配已装/临时双路径 predicate 后20项重新通过。它只改变测试位置/owner，不绕过 manifest/hash/image 校验。
- sh -n、Python py_compile、git diff --check通过。

## 初审修复

初审P1：umask077下安装目录不可读。改为作用域内umask022、公用app目录755，并在改变开机别名前以greeter身份检查已装入口及文件可读性；安装不继承root调用者私有目录权限。

初审P2：准备快照异常留下无state.json目录。改为临时0700目录完整生成备份、恢复代码及元数据后rename，fsync父目录，失败清理；系统变更只能在完整快照之后。

初审P2：OnFailure中greetd已failed时遗漏新会话。改为独立owned_sessions检测，active/failed和自动/手动路径均清理，仅保存同boot旧ID，跨boot不错误保护复用ID。

初审P2：壁纸默认TTL一天却没有刷新。显式新增当前同意的刷新/撤销命令，文档说明24小时到期、无自动刷新，不修改资源schema来无限延长期限。

P3快照目录rename未fsync父目录已修复。文件和开机链接receipt保护外部配置修改；恢复失败保留快照，可重试。

## 未测与状态

真实root安装、发行版systemd alias处理、物理TTY、PAM、开机登录、已装greeter读取、断电恢复未测。当前脚本已包含greeter身份预检，但本轮未以真实greeter权限运行安装后的宿主目录。OnFailure只涵盖greetd daemon失败，不涵盖daemon活着但UI失败。未声称完成T14/A19或T11缺失的完整A03/A10录像。

最终独立复审结论见 ../../reviews/persistent-install.md；不以作者自查替代。
