# Windows 原生性能复测

这是隔离诊断入口，不是产品版本。沿用正常 Release 的应用/QML 对象，只替换入口以执行固定场景并观察原生对象。使用 Qt 6.11.2 私有头文件统计已有 layer；不会为了统计给每个 Item 创建 layer。工具链路径对应当前 Windows 开发机的 `F:/QT`。

## 构建与运行

先按项目正常方式配置 `build/portable` 并准备 `dist/ListenFree-Portable` 运行库。以下命令在仓库根目录执行，后续编译独立使用 `build/performance-verify`，避免其他开发任务写入相同对象文件：

```powershell
python tools/performance/configure_isolated.py
$env:PATH='F:\QT\Tools\mingw1310_64\bin;F:\QT\6.11.2\mingw_64\bin;'+$env:PATH
& 'F:\QT\Tools\CMake_64\bin\cmake.exe' --build build/performance-verify --target listenfree -j 6
python tools/performance/build_probe.py
python tools/performance/prepare_cases.py --track 'E:/Music/new/AIZO - King Gnu.flac'
python tools/performance/measure.py build/performance-optimization/cases/acceptance-1.json
```

`prepare_cases.py` 支持 `--profile`、`--video`、`--output`、`--results`。首次准备时只读备份 SQLite，后续轮次共享该固定副本；新一组对照使用新的 output 目录。歌词反事实截图用例的固定时间位置针对 AIZO，其他曲目需调整 `freezeLyric` 和 `expectedLyricLines`。模板不包含用户资料库、音乐、登录信息或网络缓存。

`build_probe.py --link-only` 仅适用于入口和探针头文件均未改变、只重建了 QML/应用对象的情况。诊断 EXE 位于 `build/performance-optimization/runtime`，正常产品 EXE 位于 `build/performance-verify`；不要将诊断 EXE 用作便携交付。

旧的 `dist/ListenFree-Portable` 不存在时，可用 `--runtime-source dist/releases/<批次>/<运行目录>` 指定匹配的已有运行库；`--runtime` 仍是诊断输出目录。详情生命周期场景支持 `collectionFixture`（`count` 控制临时行数）和 `closeCollection`；快照的 `collectionDetailRows` / `collectionDetailBusy` 记录真正的后端持有量。该夹具模拟已加载详情，不保存歌单、不发真实在线分页请求；网络取消由原生 CollectionTests 单独验证。

## 场景与口径

- `acceptance-1/2/3`：各自冷启动 30 秒、普通播放、普通歌词页、全屏莫奈、退出回落。默认 threaded 渲染循环，开始前确认 Windows 已解锁。
- `browsing-final`：歌曲播放、发现页三张卡片、拼窗六次往返平移、艺术家主图、返回及回落。
- `acceptance-stress`：样式、频谱/氛围灯、唱片队列、本地 MV 暂停/恢复及释放、六轮沉浸进出、75 秒回落。
- `navigation-final`：六页状态恢复及返回后 0/16/50/100/250ms 截图。使用 basic 循环，密集截图会改变内存和时序，只用于功能/画面检查。
- `effects-scenes`：同窗口强制原效果与优化效果，比较固定歌词画面。
- `background-final`：固定背景尺寸和透明 PNG，检查全局旧图释放与艺术家合成画面。

Python 依赖 `psutil`；像素检查需要 Pillow。采样每 250ms 记录整个进程树的 PWS（USS）、WS、Private Commit、CPU、句柄；每秒读取 Windows PDH GPU 专用/共享内存。summary 的稳态值取各阶段末 5 秒中位数。渲染线程直接记录 afterRendering 间隔；它表示提交节奏，并非 GPU 执行时长。

采样临时调用 `SetThreadExecutionState` 防息屏/休眠，退出解除，不改持久电源计划。它不能解锁 Windows。每行同时记录 `sessionLocked`、`ownForeground` 和前台进程 ID；测试期间重新激活本测试窗口：锁屏、遮挡、没有连续提交的结果不作为前台性能验收。basic 循环和强制截图结果不能代替产品默认 threaded 帧时间。

运行时使用独立资料库，关闭自动扫描、启动播放和动态封面，音频输出为 null；三轮必须保持相同输入。对真实设备输出、动态封面等完整用户配置的结论需另测。探针不强制压缩工作集，不修改用户资料库。

```powershell
python tools/check_navigation_resources.py build/performance-optimization/results/navigation-final/objects.json
python tools/check_navigation_pixels.py build/performance-optimization/results/navigation-final
python tools/check_background_resources.py build/performance-optimization/results/background-final/objects.json
```

历史证据和已撤回的候选见 `docs/PERFORMANCE_OPTIMIZATION_2026-09-08.md`；不能把撤回版本的内存降幅算作最终收益。

## 固定版本 A/B

`python tools/performance/build_counterfactual.py` 暂时关闭六处本任务的资源优化，使用相同的其他源代码、依赖与诊断入口构建 `matched-baseline-runtime`，然后恢复六个源文件的原始字节并重建正常 Release。只能在没有其他构建和基准运行时执行；冲突检测会保留并报告并发修改。随后执行 `python tools/performance/build_probe.py --link-only` 重新链接优化诊断版本。这个对照是当前版本的开关对照，不是历史 EXE。

将同一份生成配置分别设置 `runtime` 为两个目录，并使用不同 `report` 目录。`compare_runs.py` 要求两个配置的步骤、曲目、资料库、窗口和渲染方式一致，检查会话/前台/连续渲染后生成对照数据。所有原始 PWS、WS、Commit、GPU、CPU 和提交间隔保留在结果中。

`expectedLyricLines: 89` 在进入歌词页前核对原生歌词负载；空歌词直接以退出码 10 拒绝，不能将该轮低占用当作优化收益。测试从隔离的空队列打开曲目，并清空隔离资料库中的待写标签任务，避免执行用户未完成的元数据写入。

曲库场景可在步骤中指定 `expectedCatalogRows`，同时核对 ready、歌曲总数与原生模型行数；不符时以退出码 10 拒绝。快照中的 `catalogRows`、`catalogModelRows`、`catalogAlbums`、`catalogArtists` 用于核对前后负载，避免将歌曲未加载完整算作内存收益。

`editor` 步骤通过 `open` 和可选 `track` 控制隔离编辑器夹具；快照记录 `editorControlsLoaded`、`editorItems` 及 `editorActionMs`。后者只测属性更新/创建控件的同步执行耗时，不能作为首帧延迟或 FPS。截图步骤与正式内存采样分开运行。

`hidden-lyrics-return` 使用暂停的固定 50000ms 位置，对比返回后 0/16/50/100/250/2500ms 完整画面；`tools/check_hidden_lyric_pixels.py` 要求最大通道差不超过 2/255。该密集读回只验证画面，不用于前台内存或帧时间。

最终证据使用 `final-acceptance-1/2/3`、`matched-acceptance-stress-baseline/optimized`、`foreground-browsing-baseline/verified`。浏览验收还检查回落阶段没有额外导航/切歌。运行期间保持测试窗口自动执行，避免向测试窗口输入额外操作；Windows 前台锁定可能阻止程序激活，需查看实际前台采样，而不是只相信 requestActivate/SetForegroundWindow 的调用。此次经用户授权临时调整的电源、屏保和前台锁定等待均已恢复。

## 音源插件与真实在线播放补测

此前的本地音频用例只复制 SQLite，没有复制音源脚本；因此虽计入 SourceHost 进程，但没有覆盖已加载插件的运行时。不能将此前数字称为完整在线播放占用。

```powershell
python tools/performance/build_probe.py
python tools/performance/prepare_online_cases.py
python tools/performance/run_online.py build/performance-optimization/online-cases/online-acceptance-1.json
python tools/performance/summarize_online.py docs/validation/performance-optimization-2026-09-08/online-acceptance-1
```

`sourcesDirectory` 将当前安装脚本复制到隔离资料目录，产品中的路径重定向正常执行；不修改用户插件、资料库、队列或设置。`startWithoutSource` 仅清空隔离配置中的音源记录，随后通过真实导入接口加载当前插件，以测量同进程的加载增量。隔离资料库与脚本文本由 `.gitignore` 排除，不纳入交付证据。

`online-acceptance-1/2/3` 使用当前活动音源、酷我 450444 的真实元数据和线上 FLAC，覆盖插件加载、普通播放、普通歌词、全屏莫奈、在线 Seek、停止及清空队列后 45 秒回落。`online-switch-stress` 使用三个真实搜索结果、九次切歌及双向 Seek，启用智能过渡与动态封面，停止清空后观察 60 秒。`online-source-smoke-verified` 逐一加载当前安装的四份音源并实际起播。

探针新增音源加载状态、解析成功/失败计数、曲目身份、音频格式、歌词负载及队列大小。`summarize_online.py` 要求音源已加载、在线身份正确且解码进度持续推进，分别输出主程序、SourceHost 和控制台宿主的 PWS / WS / Commit。只有返回音频 URL、不实际解码，或者中途变成本地歌曲，均不能通过。

`ignoreUserInput` 仅在诊断窗口过滤外部鼠标/键盘事件，避免额外操作改变场景，不改变产品输入或视觉代码。`run_online.py --manage-foreground` 只在用户已授权调整测试设置时使用；临时屏保和前台锁定设置在 `finally` 恢复并核验，原值及恢复记录落盘。已有采样器的临时防休眠租约随进程退出解除。

`lyricPreviewFixture: true` 为歌词匹配弹窗注入隔离合成控制器，便于排除在线波动，测量完整应用中预览界面的创建和关闭。`lyricPreview` 动作以 `count` 指定完整预览行数（默认 240，含换行、翻译和罗马音）；`lyricPreviewClose` 走原弹窗关闭入口。快照记录 `lyricMatchVisible`、`lyricPreviewItems`、`lyricPreviewRows` 和 `lyricPreviewCharacters`。该夹具只证明 UI 生命周期与完整进程树的对应变化，不代表真实来源缓存、网络请求或原生解析器的内存；后端取消、释放与缓存语义由 `listenfree_lyric_search_tests` 另测。

## 下载历史和实际传输

`download_memory.py prepare --profile <固定曲库.sqlite> --output <对照目录>` 生成 100/5,000 条合成历史的隔离数据库；`--sizes` 可覆盖规模。将匹配的诊断程序放到目录下的 `before-runtime` / `after-runtime` 后，运行 `download_memory.py run --output <对照目录>`，默认三轮交错执行两个版本。

测量使用前台可见窗口；核对阶段末采样的实际前台状态，以及打开、滚动、关闭和重开的渲染帧。仅有 visible/exposed 为真不足以证明 Windows 上的遮挡窗口完成了动画；发生零帧、动画未完成或锁屏时，保留该次日志并排除重测。后台下载阶段没有界面变化时零帧正常。此脚本不修改系统前台锁定或电源设置。

重测前先归档受影响的成对输出；例如 `run --sizes 5000 --start-round 2 --rounds 2` 只重跑 5,000 条历史的第 2、3 组，不覆盖已验收的第 1 组。脚本本身不自动归档同名输出。

`run` 每个用例结束后还会校验窗口条件：阶段完整、正常退出、阶段末足量采样全部处于未锁屏的本应用前台、交互阶段有渲染帧；失败立即结束批次并关闭夹具。`verify --sizes 100 --rounds 3` 可以只读复核已有运行，不启动应用或 HTTP 服务。该入口只验窗口和退出条件；任务数量、传输字节、模型角色、恢复语义及画面仍需相应功能验收和完整结果校验。

脚本在回环地址启动外部 HTTP 夹具，并生成只指向该地址的测试音源；应用使用真实 DownloadService、QNetworkReply、进度通知和文件写入。传输为有节奏的合成字节流，暂停后结束，不用于音频解码或标签正确性判断，服务端不计入应用进程树。已有原生下载测试另验 MP3 音频字节、续传、备用源和清理。脚本结束关闭服务；所有数据库、下载文件和脚本均在指定对照目录中。

探针动作 `downloadAdd`、`downloadPanel`（`open`）、`downloadsPause`、`downloadsResume`、`downloadsClear` 调用原服务和面板。阶段结束才读取一次完整任务快照，周期采样不反复调用 tasks()；记录任务总数、首任务状态和字节数、列表行数、Item 数及进度通知计数。前后均包含同样的诊断开销。`visual --sizes 100 --rounds 1` 单独生成静态历史、滚动、关闭和重开的画面对照，不能将该截图运行的内存用于正式结果。
