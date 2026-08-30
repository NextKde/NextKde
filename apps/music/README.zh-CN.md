# KOS 音乐

KOS 音乐是管理本地音乐库的独立 Qt Quick 播放器。它负责实际播放并发布符合
标准的 MPRIS 服务；现有 Quickshell Dock、控制中心和 DeskCenter 仍是普通的
MPRIS 客户端。

## 当前状态

第一阶段提供可独立构建的应用以及音乐库、播放器布局。在原生 GStreamer
引擎和持久化音乐库接入前，播放控件保持禁用。

## 构建

```bash
cmake --preset music-dev
cmake --build --preset music-dev
```

可执行文件位于 `.build/music-dev/apps/music/`。

## 架构

- 位于可测试接口后的 C++ GStreamer `playbin3` 引擎。
- 使用 TagLib 的元数据、内嵌封面后台任务。
- 带迁移的 SQLite 音乐库，保存目录、曲目、专辑、艺术家、播放列表、队列和历史。
- 名为 `org.mpris.MediaPlayer2.kosmusic` 的 Qt D-Bus MPRIS 服务。
- 使用 GStreamer `encodebin` 执行用户明确发起的格式转换和导出。

## 计划范围

本地目录、异步扫描、搜索、专辑/艺术家、播放列表、持久化队列、随机/循环、
进度、音量、无缝播放、ReplayGain、封面、错误恢复及系统提供的常见编解码器。

首版暂不包含 DRM 服务、在线账户、播客、CD 抓轨和音频编辑器；应用不会捆绑
第三方编解码器二进制文件。
