# 安装可读性预检误拒绝：修复记录

2026-10-12。用户实际运行安装入口，发布壁纸后，installed_check错误要求greeter读取publisher专用0600锁public-display/1000/.lock，导致误拒绝。脚本随后自动回滚。执行者只读查询确认display-manager.service仍为plasmalogin.service、active/enabled，安装app与私有snapshot目录不存在。本轮未运行sudo或重新安装。

修复：runtime_files仅排除public-display/<decimal uid>/.lock，保持发布锁0600；QML、helper、manifest、图片及其他文件仍执行greeter身份可读性检查。失败诊断只报告不可读资源，而不展开完整命令/全部文件列表。没有放宽目录、home或发布锁权限。

测试：23项隔离安装事务检查通过；新增回归直接调用真实installed_check函数，模拟另一账户仅有公共读取位，验证0600私锁不阻断，0600 manifest依然拒绝，私锁仍0600。测试使用mode模拟，不宣称本轮执行真实setuid或成功root安装；用户下一次运行安装时才执行真实greeter身份预检。

独立只读代理/root/review_install_lock未参与实现；核验Reader消费路径无需获取Store发布锁，独立重跑23项通过；无P0/P1/P2。被审SHA256见SHA256SUMS。本轮增量摘要取代原持久安装冻结清单中这两个文件的版本，其他范围沿用此前审查。
