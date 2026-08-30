# KOS 音乐

**[English](README.md) | [中文](README.zh-CN.md)**

KOS 音乐是管理本地音乐库的独立 Qt Quick 播放器。它负责实际解码与播放，
并发布 MPRIS；Quickshell Dock、控制中心和 DeskCenter 仍是相互独立的
MPRIS 客户端。

## 当前状态

第 1 版本地播放器已经可用：

- 添加、移除并异步扫描音乐目录；支持搜索，以及最近添加、歌曲、专辑和
  艺术家视图。
- 使用 TagLib 读取常见元数据与内嵌封面，以带迁移的 SQLite 音乐库持久化，
  不修改源文件。
- 通过 GStreamer `playbin3` 播放，支持暂停、跳转、音量、持久队列、下一首
  播放、随机，以及单曲/队列循环。
- 新建、重命名、删除和播放播放列表。
- 调用系统已安装的 GStreamer 编码器导出音频。只有对应元素可用时，界面
  才会显示 FLAC、Vorbis、Opus、WAV 或 MP3。
- 发布 `org.mpris.MediaPlayer2.kosmusic`，供媒体键和桌面组件读取元数据、
  位置，并控制跳转、音量、随机、循环、`OpenUri` 和 `Raise`。

## 构建与安装

在仓库根目录执行：

```bash
cmake --preset music-dev
cmake --build --preset music-dev
ctest --test-dir .build/music-dev -R kos-music --output-on-failure
cmake --install .build/music-dev --prefix "$HOME/.local"
```

未安装的可执行文件位于 `.build/music-dev/apps/music/`。安装步骤还会添加
`kos-music.desktop`；若启动器没有立即出现，可刷新桌面数据库或重新登录。

## 依赖

- Qt 6 Core、Gui、QML/Quick、Quick Controls、Quick Dialogs、Concurrent、
  D-Bus、SQL，以及 SQLite 驱动。
- GStreamer 1.x 开发文件：`gstreamer-1.0`、`gstreamer-audio-1.0` 和
  `gstreamer-pbutils-1.0`。
- TagLib 1.12 或更高版本。
- 与所需格式、音频输出相匹配的 GStreamer 运行时插件包。KOS 音乐不会
  捆绑编解码器二进制文件。

扫描器能识别较多 TagLib 支持的扩展名，但只有系统安装了对应 GStreamer
解码器/编码器时，文件才可播放或导出。转换对话框只展示运行时实际探测到的
编码器。

## 数据与集成

数据库默认位于 `$XDG_DATA_HOME/kos/music/library.sqlite`（通常是
`~/.local/share/kos/music/library.sqlite`），提取的封面缓存在
`$XDG_CACHE_HOME/kos/music/artwork`。测试可通过 `KOS_MUSIC_DATA_DIR` 和
`KOS_MUSIC_CACHE_DIR` 覆盖这些路径。

第 1 版只接受本地 `file:` URI。MPRIS 注册依赖桌面会话 D-Bus；若服务名
冲突，播放器仍能运行，但当前实例无法被外部 MPRIS 客户端控制。

## 第一版边界

已包含：本地目录/文件、增量元数据扫描、内嵌封面、专辑/艺术家、播放列表、
持久队列与设置、常用播放控制、MPRIS，以及采用原子覆盖的显式音频转换。

暂缓：流媒体/DRM 账号、播客、CD 抓轨、标签编辑、把元数据复制到转换结果、
ReplayGain、无缝预加载、淡入淡出、均衡器、波形编辑、云同步和远程音乐库。
这些能力应在现有引擎/音乐库边界后扩展，不应让应用反向依赖桌面 Shell。

组件模型、数据库与线程规则、开源软件调研、许可证边界、MPRIS 行为和验证
矩阵见[音乐架构](../../docs/MusicArchitecture.md)。
