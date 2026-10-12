# 交接降时与底层研究：独立审查

日期：2026-10-12。实施者：`/root/implement_login_handoff`。独立审查者：`/root/audit_login_handoff_fix`，未参与实现，全程只读。主代理保存本记录。

最终 [17 文件摘要](../evidence/handoff-latency-fix/SHA256SUMS)全部匹配；本增量取代历史交付中相应变化文件的摘要。详见 [实施报告](../evidence/handoff-latency-fix/REPORT.md)及 [三环底层方案](../evidence/handoff-latency-fix/DRM-HANDOFF.md)。

独立复跑资源降时5项、原资源12项、交接37拒绝场景及生命周期、安装36项fake systemd/logind事务、socket readiness与IPC协议，全部通过。审查另核对隔离图形证据及测试父树socket限制，不自行运行宿主图形测试。

确认metadata-only仅用于生产wrapper的build/write/consume；默认API和真实显示消费者完整验证。canonical缓存最多128项，只存已验证SHA256/类型/尺寸，不保存图片或授权；命中前仍读live manifest和实际文件，校验所有权、权限、预算及完整字节hash。撤销、过期、替换、内容/权限变化继续拒绝。首帧完整背景、质量、裁切及独立恢复期限保留；新增事件不等于scanout。

独立核对KWin v6.7.5四份原始源码摘要，trace-only patch再次git apply --check通过；未编译或运行。旧输出清理的异步边界、已有CloseFB、新KWin首帧候选覆盖，以及systemd v262控制器释放和vt_restore中的KD_TEXT源码依据准确。保帧行为、同seat/VT协调、有限超时及独立前缀恢复均为后续实验设计。

结论：未发现P0/P1/P2/P3。源码降时与隔离验证交付通过；底层研究交付通过。**没有完成底层保帧实现，黑屏没有被证明消除。**

约2.15秒收益仅为同公开图片的一次局部CPU路径测量，不能等同于实际登录黑屏缩短。未部署、未触碰真实TTY/PAM/KWin或重启会话；NVIDIA实机呈现、真实登录收益与零黑帧仍待受控实验和录像，不据此关闭缺实机证据的主项。
