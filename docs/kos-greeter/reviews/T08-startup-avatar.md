# T08 壁纸首显与头像回归独立审查

2026-10-11（Asia/Shanghai）。执行者/root；独立只读审查代理/root/t08_review，未参与本轮编写或修改。范围：shell.qml、qml/WallpaperSource.qml、companion/accounts.py及accounts/startup测试、evidence/T08/startup-avatar-fix报告与结果。未提交文件按该目录SHA256SUMS冻结，原清单摘要43a70aa53151ffc569dbe309af0475e03472a02fe51945e39272b9459ba4ed06。

审查结论：通过，无P0/P1/P2。身份就绪门控、UID切换ready=false、generation旧结果过滤、readerBusy直到退出再重读避免旧默认背景提前开门；冻结/取消与超时边界保持。固定root:root目录groupwrite兼容可接受，非root/otherwrite/symlink仍拒绝，文件依旧nofollow/rootowner/无groupwrite。没有修改系统权限。

代理独立运行账户三项、延迟单账户首显一项通过。最终清单全部核验成功，六项startup、三项accounts、两项freeze及十二项IPC日志与报告一致；当前资源version/单账户UID断言有效。批准仅更新报告独立审查状态、保存本记录及刷新摘要，未再修改实现。

未测：真实系统切换、scanout、完整A15仍未测，完整T08任务阻断保持。初轮与交互修订记录是历史版本，本次批准仅覆盖新清单。
