# T11 启动蓝底回归：独立复审

日期：2026-10-12。执行者：主代理。独立只读代理：`/root/review_startup_background`，未参与编写或实现。被审范围与最终摘要见 `../evidence/T11/startup-background/SHA256SUMS`，此增量摘要取代原 T11 冻结摘要中对应已变动文件；未变动范围仍沿用原审查。

初审未发现P0/P1/P2；提出两个P3：映射configure导致resourceReady binding loop；首提交回调里的异步grabToImage不等于compositor首buffer/物理呈现，且失败场景应有耗时上界断言。

执行者进一步修复：WallpaperHost支持独立解码尺寸，Cover/WallpaperWindows用screen尺寸/DPR预解码；初次映射通过Qt.callLater再次检查，避免绑定重入。新增测试拒绝Binding loop，并断言feed卡住回退1.8到4秒。证据报告明确异步抓图及非scanout边界。

最终增量复审通过：无剩余P0/P1/P2，两个P3已关闭；摘要全部匹配，三个最新双屏启动日志通过且没有Binding loop。六项wallpaper-startup最终重新执行通过，包括1536×960、scale1.5；原Cover故障矩阵、七项T11门控及协议回归也通过。

本轮修复有效图片启动前蓝色占位的提前映射；资源真实失败仍遵守原有固定回退/期限契约。完整A03/A10、真实冷热启动录像仍未测，不由本轮用户反馈或背景层截图补造通过。未部署、修改PAM、切换系统服务或重启实际用户桌面。
