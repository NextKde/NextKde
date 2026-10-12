# 临时测试脚本 T07 接入增量

日期：2026-10-11，Asia/Shanghai。分支：codex/notification-center-stacks。执行者：主代理 `/root`。状态：完成（脚本隔离验证与独立复审通过）。用户授权更新脚本，未授权/未执行真实切换。

改动范围：tools/test-greeter.py、apps/greeter/tests/switch-scripts.test.py、apps/greeter/TEMPORARY-TEST.zh-CN.md。本次不改已关闭 T07 的宿主或生产消费逻辑；原 T07 证据保持历史冻结。

1. 临时 app 复制清单补齐 WallpaperHost/Source/Windows、静态图片消费与主题校验 helper、独立入口。共享 QML/图片/QSB 根据固定主题清单校验后复制为独立普通文件，拒绝资源路径越界、非预期链接、缺失或主题哈希不符；二进制写入支持 PNG/QSB。严格 umask 下目录0755、资源0644、入口0755、私有恢复0600仍成立。
2. `--wallpaper IMAGE` 是明确的临时公开选择：图片将在认证前对本测试的所有账户可见。sudo 下用调用者UID/主组及空附加组子进程读取有界普通文件，拒绝末级symlink，Pillow校验/重编码去元数据；不放宽home权限，也不自动读取桌面选图。只有复制的 shell.qml 将资源状态改为固定临时 `config/preview-wallpaper.png`，没有将用户路径/命令拼进QML。
3. 源图不可读、损坏、非静态PNG/JPEG、超预算或缺Pillow均在准备/切换前拒绝。副本仅在本次 `/run` app/config 中，回滚现有STATE整体清理包括图片。未传参数时保持已有公开副本/默认纯色行为，没有持久发布或改写 `/var/lib`。

验证：`python3 apps/greeter/tests/switch-scripts.test.py`，17项通过，见 tests.txt。systemd/logind仅模拟，实际临时目录、文件模式、二进制bundle写入和幂等回滚运行；实际 Quickshell offscreen 加载已复制认证前端及共享资源（无 greetd 连接），固定预览状态存在并正常退出，未出现加载/类型错误。root+SUDO_UID分支增加 subprocess user/group/extra_groups 参数断言；本次没有实际root降权执行测试、真实PAM、TTY切换或物理显示验收。

系统服务、持久配置、当前桌面未改；测试临时目录结束后清理。此增量证明脚本准备的T07 app可加载，不替代真实临时切换验收。关闭后的T07原验收矩阵边界不变。

独立审查代理 `/root/t07_review` 未参与实现，初审未发现P0/P1/P2；P3提出的sudo降权参数断言已补充。最终摘要、复审记录见 ../../../reviews/T07-script-update.md。
