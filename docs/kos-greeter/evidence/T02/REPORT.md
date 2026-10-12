> 当前状态（2026-10-11）：用户已明确验收关闭本任务。下文为历史执行快照，原阻断/不关闭结论已被用户验收取代；历史缺测不重新打开任务，不补造测量数据。

# T02 最小登录生命周期原型执行记录

状态：阻断（实现与有限测试已完成，真实隔离验收未执行）。执行者：Codex。日期：2026-10-11，Asia/Shanghai。
分支：codex/notification-center-stacks。源码基线：54512887915152c514b9d08f3a45ca14779e1adc。未提交文件摘要见 SHA256SUMS。

用户明确授权完成 T02，覆盖独立 app 原型实现；附带文档中的历史“仅研究”边界不代替当前用户请求，任务文档也不授权切换宿主服务。用户确认没有隔离 VM/seat。本机无 qemu-system-x86_64/virt-install/virsh、无已找到的 VM 镜像；/dev/kvm 可读并不代表现成可运行的隔离系统。没有安装虚拟化工具、创建真实登录测试账户或修改系统服务/PAM。

## 交付与实测

apps/greeter/ 提供源码运行入口、固定 Plasma 会话允许清单预检、默认渐变背景、最小表单、认证提示/取消/失败重试、退场后 launch、确认退出和超时。详情与 VM 实验方案见该 app 中英文 README。正式独立安装、CMake 包装、Cover、资源发布与桌面交接不在本卡实现。

| 检查 | 实测结论 | 证据 |
| --- | --- | --- |
| 组件 | greetd 0.10.3-2、Quickshell 0.3.2-1、KWin 6.7.5-3、Qt base/declarative 6.12.0 | environment.txt；内核/GPU/实际输出沿用 T01 快照，不视作本次 VM 参数 |
| 状态机 | 正常顺序、失败、取消等待后端确认、超时、拒绝无效事件通过 | lifecycle-tests.txt |
| 真实 Quickshell + 假 greetd IPC | 模拟认证成功/失败重试/取消/断连/launch 拒绝通过；允许清单和 env 断言通过 | ipc-tests.txt；不是 PAM/真实登录证据 |
| 断连处理 | 本机连接关闭没有即时 error 信号，生产由 60s watchdog 退出；测试缩短到 500ms | ipc-tests.txt、tests/ipc.test.py |
| 离线加载 | QML 加载成功，离线认证禁用；外部 timeout 停止测试 | offline-load.txt；该退出码 124 为预期实验终止，不是登录生命周期通过 |
| KWin 虚拟退出 | --virtual 独立 socket + 临时 D-Bus；测试 qs 1s 后 Qt.quit，KWin 退出码 0 | virtual-exit.log、virtual-exit.status；无 seat/VT/DRM/PAM/Plasma 交接 |
| 安全前置 | 当前已安装 Plasma Exec 与固定 argv 一致 | preflight.txt |
| 宿主最终状态 | display-manager active，greetd inactive；没有实验 KWin/fixture 残留 | final-state.txt |

官方 API 与本机 qmltypes 交叉核对：[Greetd](https://quickshell.org/docs/v0.3.0/types/Quickshell.Services.Greetd/Greetd/)。readyToLaunch 与 launched 均不视作桌面就绪。测试首次暴露 Quickshell.quit 不存在，已修正为 Qt.quit；初次虚拟实验被 timeout 结束并出现 KWin crash 输出，后续修复版本正常退出。此失败未涉及真实登录，恢复为停止独立实验进程；不冒充 TTY 恢复演练。无实际密码输入/采集，测试固定字符串只是虚构协议响应。独立审查发现 launch 阶段 authFailure 会停止 watchdog 并滞留 LaunchRequested；已改为非认证状态发生此错误时立即退出，新增 launch-rejected 真实 Quickshell/mock IPC 回归通过。

虚拟退出实验实际命令（宿主只使用 virtual backend，非 DRM）：

```sh
env -u DISPLAY -u WAYLAND_DISPLAY -u GREETD_SOCK timeout 10s dbus-run-session -- kwin_wayland --virtual --socket kos-t02-virtual --no-lockscreen --no-global-shortcuts --no-kactivities --exit-with-session /home/wwt/Downloads/NextKde/apps/greeter/tests/exit-fixture
```

## 验收、时间线与恢复边界

A01、A02、A14-P、G1：阻断。真实正确/错误 PAM 认证、前端异常退出后的 greetd 恢复、用户会话立即失败、人为延迟退出后的等待、完整进程树、真实录像和 TTY/旧管理器恢复均未测。自动测试只覆盖应用/协议，不关闭上述验收。A13 仅测试响应未出现在本次捕获日志的有限检查，全面真实隐私验收未测。

认证成功、退场、launch 请求/确认、登录 KWin 退出、用户 KWin 可连接的真实单调时间线均未测；无跨进程时间对齐。Cover、scanout、桌面揭幕不在本卡。无录像设备、帧率或黑帧统计，不能声明零黑帧。内置渐变不是用户壁纸，crop/scale 真实呈现未测。Tahoe 非本卡目标。

本次无宿主配置变更，不需要恢复宿主显示管理器。实验的失败和退出只触及独立进程，最终宿主原管理器保持 active。VM 恢复方案见 app README，恢复命令、耗时、最终 VM 服务/进程树仍须实测；没有证据前不得进入实机集成。

## 独立审查

本次实现及有限测试按独立审查规则冻结并审查，见 ../../reviews/T02.md。独立审查不能解除缺少隔离 VM 和真实验收证据的阻断。

## 后续实机阶段记录（2026-10-11）

上文是原隔离/离线阶段记录。后续用户确认真实登录与手动回滚成功，当前原管理器状态经只读复核；见 [新增阶段验收报告](host-smoke/REPORT.md)。完整 A01/A02/A14-P/G1 仍未通过，原“真实正确认证未测”描述仅代表此前阶段，不覆盖后续用户反馈。
