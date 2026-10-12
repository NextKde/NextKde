# 密码框玻璃与 KWallet 后续修复

日期：2026-10-12；分支 codex/notification-center-stacks；独立审查：/root/review_greeter_fixes（待最终复审）。被审文件见 SHA256SUMS。没有修改 T01–T14 状态或补造硬件验收。

密码框保留既有 GaussianBlur，移除两层蓝色染色并减弱焦点边框，背景改为主窗口实际绘制的同源静态壁纸。隔离测试增强为真实 WallpaperHost/共享 StaticWallpaperImage，而非简化 Image；真实 shell 夹具使用合成 data URL，检查玻璃像素及缩放/滚动坐标。Qt 软件渲染和缺效果模块仍验证圆角可读回退。

原隐藏背景也能通过正确绝对 URL 的隔离夹具，故不能断言隐藏祖先就是实机异常根因。首次增强测试的蓝底来自夹具相对 URL，已纠正；实机截图的确切渲染故障仍未定位。本轮改善采样路径与染色，不能宣称实机玻璃问题已经验收。

本机 journalctl 本次启动显示 pam_kwallet5(greetd:session): not a graphical session, skipping。已有 auth optional、session optional auto_start；脚本补充 auth/session force_run，注释内的 force_run 不被当作参数。KDE 官方源码在 auth 阶段解析并缓存该参数，session 阶段以其绕过图形会话判断：https://github.com/KDE/kwallet-pam/blob/master/pam_kwallet.c 。

验证：python3 apps/greeter/tests/glass.test.py 通过，Gaussian 合成采样红色均值129.19、标准差2.46；软件与模块缺失回退、实际 shell data URL、缩放及滚动检查通过。python3 apps/greeter/tests/kwallet.test.py 通过，覆盖新增/旧钩子、注释、0600 原配置备份及幂等性；全部文件操作位于临时目录。

未运行安装/系统 PAM 修改；sudo -n 不可用，需要用户交互输入管理员密码。当前系统配置及会话保持原状。安装说明给出更新、独立 PAM 修复与备份恢复命令。下一次真实密码登录自动解锁、Chrome 行为、物理 GPU/DPR 观感仍未测。钱包密码匹配登录密码是自动解锁的前提，未读取用户钱包或真实凭据。
