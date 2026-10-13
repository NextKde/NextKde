# exit-crash-fix 独立审查

日期：2026-10-13，Asia/Shanghai。用户授权独立子代理修复登录退场崩溃。本批实现者：`/root/fix_bridge_lifecycle`、`/root/fix_greeter_isolation`；协调/证据整理：`/root`；未参与实现的独立审查者：`/root/research_review`。

## 冻结范围

审查范围为 [SHA256SUMS](../evidence/exit-crash-fix/SHA256SUMS) 中30文件，包含实现、测试、安装/交接说明和证据。最终30/30哈希一致；bridge摘要5/5、Greeter manifest12/12一致。未提交Git、未切分支，未覆盖前置无关修改。本记录不加入被审SHA以免自引用。审查者未修改被审源码或文档。

## 问题与处置

- P1，入口测试隔离：旧session-output测试只mock execv，在入口改用execve后漏拦启动，意外运行KWin；随后静态审查发现switch-scripts同类危险旧mock，在执行前修正。三处入口测试现捕获execve，并有外层守卫阻止未审核exec*/spawn*/system/Popen。首次失败及恢复完整保留，见 [事故记录](../evidence/exit-crash-fix/greeter-test-isolation-incident.log)。独立审查核验守卫后才执行最终纯隔离回归；配置15/15、输出12/12、恢复脚本20/20通过。P1关闭。
- P3，覆盖限制：生产manager/真实KWin Item fixture使用nullptr跟踪key，未复现完整动画SIGSEGV、真实Window属性恢复或完整Bridge析构/插件卸载。限制已写入证据，允许本批源码交付，实机验收继续保留。
- P3，缓存生命周期：私有目录依logind UID runtime回收，同UID其他会话或linger可能延迟清理；不保证立即删除或固定占用，已明确记录。
- P3，效果与黑帧：真实效果加载、登录正常退出、DRM/VT/presentation及黑帧时长未实机验收。源码和隔离验证不证明零黑帧，报告未作此承诺。

## 复审与证据

独立审查者运行配置15项、输出12项、恢复脚本20项、安装44项及CTest3项，全部通过。实现代理最终Greeter回归共96项；真实kos_bridge插件编译、ASAN/UBSAN离线fixture和修复前同回归失败证据已读核验。ASAN外部库未插桩、泄漏检测关闭。父代理独立打包新helper且禁用壁纸同步，未执行安装。

源码复核确认已删除窗口不再同步改场景/恢复属性；父树拥有附加节点；活窗口恢复先移记录、保护重入并在Bridge成员存活时执行。配置逐组件fd验证可信目录/UID/权限，显式效果键进入私有KConfig路径，仅传登录进程；失败exit70，--check不写配置；bundle清单完整。最终说明与证据边界一致，git diff --check通过。

## 最终结论

独立审查通过，无未关闭P0/P1/P2；上述P3处置经审查认可，不阻断本批源码修复与隔离验证交付。未安装、热加载插件、重启会话、修改PAM/logind或验收物理黑帧。后续被审源码变更须重新冻结并复审。
