# sudo 伪终端导致 tty3 误拒修复

日期：2026-10-11，Asia/Shanghai。执行者：Codex。分支：codex/notification-center-stacks。
状态：修复与模拟测试通过；用户机器 sudo/真实切换复测未执行。

用户照片显示已登录 tty3，但 sudo 启动测试脚本仍在 TTY 校验处失败。旧脚本只检查 os.ttyname(0)，没有处理 sudo use_pty 导致 stdin=/dev/pts/N；本机安装 sudo(8) 对 SUDO_TTY 的定义是调用 sudo 用户的终端，sudoers(5) 描述 use_pty 伪终端包装。此为与照片一致的原因推断，未采集用户失败当时的环境。旧检查在 lock/preflight/prepare/systemctl 之前返回，因此照片中的这次拒绝没有触发本脚本的系统变更。

修复 recovery_tty：始终要求交互 stdin；实际 stdin 是 pts 且 SUDO_UID 为数字时使用 sudo 的 SUDO_TTY 校验原始终端。仍拒绝来源图形 pts、测试相同 VT、DISPLAY/WAYLAND 环境、无sudo标记pts及管道。失败提示输出实际与 sudo 原始终端方便诊断。没有取消TTY保护、改 sudo 配置或引入新的系统切换步骤。SUDO_TTY 是 root 入口的操作校验，不承担权限授予。

tests.txt：14 个模拟测试通过，包括直接tty3、sudo pty源自tty3、图形pts、缺少sudo元数据、同VT、图形环境和管道；原回滚故障测试保持通过。systemd/logind 调用仍全部 fake，不执行真实服务切换。preflight.txt 本机只读检查通过。final-state.txt 默认 plasmalogin active/enabled，greetd inactive/disabled。

用法无需改变：TTY3 运行 sudo python3 /home/wwt/Downloads/NextKde/tools/test-greeter.py --start --timeout 600。用户复测需自行执行；本次没有 --start、sudo 或真实 rollback。没有真实凭据、屏幕录像或PAM操作，T02/T05及实机恢复验收仍未通过。

本次修复摘要见 SHA256SUMS，取代旧临时脚本清单中 tools/test-greeter.py、switch-scripts.test.py 和临时说明的版本；旧记录代表修复前审查，不冒充当前版本审查。独立只读代理 /root/review_switch_scripts，未参与编写。最终结论见 ../../../reviews/temporary-switch-tty-fix.md。
