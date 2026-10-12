# 临时测试脚本 T07 接入独立审查

日期：2026-10-11，Asia/Shanghai。执行者 `/root`，独立审查者 `/root/t07_review`，未参与本增量实现，仅只读检查及运行隔离测试。

范围：tools/test-greeter.py、apps/greeter/tests/switch-scripts.test.py、apps/greeter/TEMPORARY-TEST.zh-CN.md 和 evidence/temporary-switch/T07-update 下报告、测试输出。原T07生产宿主/契约/历史冻结不改。

初审无P0/P1/P2；P3建议root+SUDO_UID降权参数断言。作者补user、group、extra_groups=[]断言，并明确图片/缺Pillow错误拒绝。最终17项测试通过，包含临时普通文件bundle、严格umask、真实offscreen Quickshell副本加载、图片拒绝及模拟恢复；不运行真实切换。

最终独立复审通过，无未关闭P0/P1/P2/P3。被审摘要 `366cd961ee43b828dc5a9e6d46be66ecd5d8644a570ec21a80efa5bec6e87d23`，逐项核验通过，归档为 T07-script-update-reviewed-SHA256SUMS。公开范围与实际root降权/PAM/TTY/物理显示未测边界准确。准予完成，仅再更新REPORT状态和此审查记录。

状态差量后的摘要 `7bd231664223fd90841b09178cf8376b75834b7477624d9a5921e5963490b276`；只改变REPORT状态，代码、测试和原始日志不变。状态差量确认：同一独立代理确认通过，最终摘要逐项校验通过，仅REPORT状态变化；本增量正式完成，无未关闭P0–P3。审查记录不纳入自身摘要，避免自引用。
