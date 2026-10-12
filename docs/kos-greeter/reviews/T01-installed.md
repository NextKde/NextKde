# T01 安装后补充独立复审

日期：2026-10-11，Asia/Shanghai。执行者：Codex 主代理。
独立代理 ID：`/root/t01_review`；未参与补充编写，审查只读。

范围：[安装后补充](../evidence/T01/UPDATE-installed.md)、[命令证据](../evidence/T01/greetd-installed.txt)、[冻结摘要](../evidence/T01/SHA256SUMS.installed)。

结论：独立复审通过，两项 SHA256 校验通过，未发现 P0/P1/P2/P3。证据支持 greetd 包版本 0.10.3-2、程序所属包、服务 inactive/disabled，以及当前 plasmalogin 仍 active；明确区分包版本与不支持的运行时版本查询。历史快照、当前状态、链接和后续未测项一致。无问题修复或延后事项。

代理核准仅新增本记录如实保存结论，无须再次审查记录本身。真实认证、PAM/IPC、seat/VT、KWin 生命周期与恢复仍未验证；安装依赖解除不代表 T02 验收通过。
