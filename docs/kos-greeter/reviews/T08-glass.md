# T08 圆形头像与磨砂材质独立审查

日期2026-10-12（Asia/Shanghai）；执行者/root；独立只读代理/root/t08_review，未参与实现和编辑。范围以 ../evidence/T08/glass-update/SHA256SUMS 为准；被审清单摘要7255864a9e1efa2732222fabfb6530d6d5b8b20b81ba61c6887177d5f882f7ce，全部核验成功。

初审P2：mapToItem未观察布局祖先与滚动，resize/scroll可能继续旧采样点。执行者增加wallpaperPosition显式观察字段/viewport/背景几何与Flickable偏移。完整shell布局变化/滚动检查通过，采样值变化并等于当前mapToItem，最终复审关闭P2。

最终结论：通过，无未关闭P0/P1/P2。头像CPU alpha圆裁、可信背景唯一采样源、有界高斯纹理、Loader缺模块/软件回退以及临时FILES复制均符合范围。实际渲染截图/纹理方差、角透明与坐标跟随证据和实现一致；账户3、IPC12、模拟切换20通过。审查代理独立运行账户测试通过。

批准仅更新报告独立审查状态、保存本记录、刷新清单；未改实现。不声明完整Tahoe液态折射或scanout。完整A15缺实机基准，完整T08阻断不变。
