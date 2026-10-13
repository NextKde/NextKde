# 登录退出崩溃与 Greeter 配置隔离修复

日期：2026-10-13。用户明确授权独立子代理修复。实现者：`/root/fix_bridge_lifecycle`、`/root/fix_greeter_isolation`；未参与实现的审查者：`/root/research_review`。最终审查见 [记录](../../reviews/exit-crash-fix.md)。本批没有安装、热加载插件、重启显示管理器、实际认证或修改 PAM/logind/显示模式。

## 问题与修复

本机 Greeter KWin 6.7.5 退出时重复 SIGSEGV。今天 PID836/UID962 的主线程栈为动画效果析构释放窗口 → windowDeleted → kos_bridge 恢复外观并删除场景节点 → 几何变化回调重新进入动画计算。昨晚两次相同关键栈已只读核验。原始阶段与脱敏栈见 baseline-events.log、baseline-crash-stack.txt；没有导出 core 内存，也没有确认具体失效对象。

LaunchRequested32.944538 → PlasmaStarting35.304702 → Cover SocketConnected37.513658 → Cover FrameSubmitted38.343904，共约5.399秒软件事件间隔，不是黑帧录像测量。退出/会话创建的2.36秒不能全部归因于 core 处理。

- bridge 已删除窗口清理只断开连接、去除跟踪并停止末窗口计时器，不恢复属性或同步删除场景节点；节点随真实 QObject 父树销毁。活窗口禁用/卸载仍恢复外观，但先取出容器记录、保护同步重入，并在 Bridge 成员仍存活时恢复。见 bridge-REPORT.md。
- Greeter 验证 UID/0700 runtime 和可信无symlink目录链，创建私有配置、缓存、data目录；显式关闭包括 kos_bridge、scale 在内的17个效果。专用环境只传给登录进程，认证后 Plasma wrapper 不变，失败exit70，不回退默认效果。见 greeter-isolation.md。
- 临时copy/正式bundle及安装required清单纳入新helper。入口测试更新实际execve mock，并增加未审核启动接口硬失败守卫。

## 最终验证

| 验证 | 结果 | 证据 |
|---|---|---|
| 实际 kos_bridge 插件编译 | 通过，仅/tmp产物，未安装 | bridge-build.log |
| CTest | 3/3通过，含生产manager/真实KWin Item回归 | bridge-ctest.log |
| ASAN/UBSAN离线fixture | 通过，外部库未插桩、泄漏检测关闭 | bridge-sanitizers.log |
| 修复前实现运行同一回归 | 退出1，捕获过早删除节点 | bridge-baseline.log |
| 配置/安装/输出/UI监督/恢复脚本 | 15+44+12+5+20，共96项通过 | greeter-tests.txt |
| 实际KConfig搜索 | 私有效果键false、桌面fixture保持true | greeter-config测试 |
| 独立app bundle构建 | helper与入口的源码/manifest哈希匹配，无壁纸同步 | bundle-build.log |

审查者独立重跑配置15项、输出12项、恢复脚本20项、安装44项及CTest3项。最终源码和说明冻结范围见 SHA256SUMS；已有无关未提交改动保留。

## 测试隔离事故

首次旧输出测试只mock execv，漏拦新execve，意外运行dbus-run-session/KWin。环境clear=True，仅非真实认证socket标记；缺失XDG_RUNTIME_DIR导致socket初始化失败退出139。此轮失败，不计通过。之后找到switch-scripts同类旧mock并在运行前修复；三处入口测试增加exec*/posix_spawn*/system/Popen守卫，经独立检查后才执行最终回归。首次失败与最终处理均保留于 greeter-test-isolation-incident.log。

父代理只读核验宿主greetd PID801、Plasma wrapper1640/KWin1647、会话3/4保持，两服务NRestarts=0，无fixture残留；未执行全局kill或系统恢复。不能把这次失败描述为已验证的安全图形实验。

## 部署与未测

现有独立Greeter更新入口可打包私有配置helper，已有安装默认更新不重启当前桌面。Greeter installer不编译/安装kos_bridge；插件源码修复需独立构建更新，本批没有部署。登录配置隔离可随Greeter app更新生效，不要求先替换当前桌面插件。

真实登录原崩溃消失、真实Window属性恢复/插件卸载、实际效果加载、多屏/DRM/VT/presentation和黑帧时长仍未实机验收。生命周期fixture以nullptr为跟踪key，不能替代完整动画栈复现；cache随logind UID runtime生命周期清理，其他同UID会话或linger可能延后回收。本批未实施背景预取、旧纯背景持帧或logind协调，没有声称零黑帧，也不关闭T11–T14缺失的实机验收。后续源码变化须更新摘要并复审。
