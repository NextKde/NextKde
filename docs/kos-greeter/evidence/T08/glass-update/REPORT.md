# T08 圆形头像与磨砂输入框

2026-10-12（Asia/Shanghai）；执行者/root；分支codex/notification-center-stacks。状态：独立审查通过。

按用户实机反馈修复：AccountsService头像输出96×96 RGBA，中心裁剪后以4倍尺寸圆形遮罩抗锯齿，并与原alpha相乘；图片四角透明，软件渲染也保持圆形。文件权限与有界读取策略保持。

输入框背景使用GlassFieldBackground，带高光渐变、双边缘和焦点边框。可选GaussianGlass只采样可信primaryWallpaper同位置区域；ShaderEffectSource纹理大小为输入框尺寸加每边20逻辑像素，不包含表单或响应。GaussianBlur radius16、samples25、deviation8，再以圆角遮罩裁切。只声明高斯磨砂与玻璃高光，不声明完整Tahoe液态折射或1:1材质通过。软件渲染、显式KOS_GREETER_DISABLE_EFFECTS=1及缺效果模块时保留普通底色，认证不依赖效果成功。

临时测试FILES已纳入两个新组件，新启动会复制它们。未实际切换管理器、修改PAM或系统权限。

独立审查初审P2：mapToItem绑定未观察祖先布局和滚动，可能采旧坐标。已用wallpaperPosition显式读取字段/viewport/背景几何及Flickable content偏移；完整shell布局宽度变更与滚动夹具验证采样点变化并等于当前mapToItem。不是物理输出模式测量。

验证：accounts三项包含角alpha0/中心255；IPC十二场景回归通过；临时切换模拟二十项通过；独立虚拟KWin实际渲染验证隐藏壁纸采样、高频条纹模糊、圆角透明，以及软件/缺模块回退。模糊后局部红通道标准差2.27，原条纹约115；均值116.58排除仅画暗色底的伪模糊。日志与合成背景截图在本目录，没有真实密码或用户图像捕获。

当前文件以SHA256SUMS冻结；完整A15实机基准仍缺，完整T08阻断保持。独立审查记录见 ../../../reviews/T08-glass.md。
