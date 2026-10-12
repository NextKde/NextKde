# KOS 当前选图自动接入临时 Greeter

状态：完成（临时脚本自动选图增量；真实系统切换仍未测）。日期：2026-10-11，Asia/Shanghai。执行者：/root。分支：codex/notification-center-stacks。
用户明确要求自动使用自己的 KOS 选图。本次在 UID1000 私有 state 下保存明确公开选择（0600、UID、notice、enabled），不为其他账户默认授权。该账户文件不进入仓库，仅记录其schema/权限，用户可通过 --revoke-wallpaper 撤销。本次未执行真实登录切换，未修改系统服务/PAM/持久登录配置。

## 实现

companion/kos_wallpaper.py 在调用者UID子进程中读取私有授权与实际 Wallpaper.ini；私有选择必须本人所有、无其他用户权限、regular、单硬链接、有限schema且UID匹配。读取 image/fit/mode/takeover，支持纯路径/file URL及百分号/中文空格，不以themeId残留覆盖image模式；不读取Plasma占位。主题、空图、接管关闭或格式错误在切换前拒绝。

root准备端接收有界标准化PNG，通过T03 Store原子发布到本次root临时app/public-display，携带原fit/crop/hash、UID与期限；config仅指定授权初始UID。WallpaperSource的-1请求让初始列表消费公开初始图，实际选择UID后按UID独立消费。helper只在固定 `/run/kos-greeter-test/app` 路径启用临时目录，正式消费目录不变。

撤销先删除本账户manifest/旧版本，消费者一秒reload、读故障三秒超时后清空旧图；之后以调用者身份禁用私有选择。无发布或另一账户发布时仍能禁用本账户选择，不删他人副本。回滚全删runtime发布，不改变KOS选图。旧的显式--wallpaper覆盖方式保留，但普通命令不再需要重复指定当前图路径。

## 验证

- switch-scripts.test.py：20项通过；实际文件准备/权限/原子发布/删除/恢复、fake systemd/logind，原staged认证QML与真实helper实际运行并记录图片decoded；读原图后删除源图，副本仍有效；另一UID默认；禁用与revoke删除版本；授权宽权限/多硬链接拒绝。
- kos-wallpaper.test.py：中文/空格/百分号file URL、四fit、未授权/禁用、theme与接管关闭拒绝通过。
- ipc.test.py：9个真实Quickshell + mock greetd场景通过；凭据不记录，无真实PAM。
- 本机当前设置实际读取：image/crop，2160×1212，规范化2395056字节；经过T03发布与初始消费后hash一致，见 current-selection.json。未把用户实际图片复制到仓库、未截图认证界面。

实际临时目录测试由当前UID所有，消费身份适配仅替换固定运行路径/root-owner验证为测试UID；schema/hash/权限/实际PNG解码逻辑保留。真实root部署/TTY切换、物理画面、完整三阶段/scanout/零黑帧仍未测。版本基线与T07环境一致；本次使用Quickshell0.3.2、Qt6.12.0、Python3.14/Pillow12.3，无新KWin/seat。

## 独立复审

审查者 /root/t07_review 未参与实现。初审P2指出私有授权文件缺owner/mode检查和无发布/其他UID状态阻断撤销；主代理修复并增加故障测试。TTY拒绝顺序回归已修复，在读私有图前先拒绝不合法start。冻结范围见SHA256SUMS；最终审查记录见 ../../../reviews/kos-wallpaper.md。

最终独立复审通过，无未关闭P0/P1/P2/P3；独立重跑20项脚本测试及选图测试通过。只读实机 `python3 tools/test-greeter.py --check` 因原显示管理器inactive拒绝，未执行系统切换；自动选图与发布/解码链路已有上述隔离证据。
