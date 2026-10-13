# Bridge 删除窗口生命周期修复

日期：2026-10-13（Asia/Shanghai）。执行者：`/root/fix_bridge_lifecycle`。状态：待独立审查；由父代理另派未参与实现的审查者。

用户明确要求调用独立子代理修复，覆盖此前“只研究”的历史限制。本次仅项目源文件与离线测试修改，不安装、不热加载、不启动或重启宿主 KWin/greetd，不改 PAM/logind/系统 KWin。

## 问题与修复

研究提供的三次相同退出栈是 `AnimationEffect` 清空动画释放最后窗口引用 → `windowDeleted` → bridge `forget/restore` 删除场景 Item → expanded geometry 信号同步进入尚在析构的动画效果。这能指明本次消除的同步重入路径，不能证明全部黑屏仅由该崩溃引起，也未确认 core 中具体失效对象。

`WindowAppearanceManager::forget` 只在 `windowDeleted` 路径调用。本次将已删除窗口的跟踪清理与活窗口恢复分离：断开每窗口连接、删除状态、末窗口移除时停止计时器；不恢复已删除窗口属性，不同步删除场景节点。生产 `sceneShadow` 构造函数及 `outline/frame/continuousBounds` 创建处均明确设置真实 QObject 父对象为 `WindowItem`；其父树最终负责销毁，场景 shadow 自身持有 atlas 引用，不依赖被清除的跟踪记录保活。

活窗口禁用配置/卸载插件仍执行 `restoreAll`，恢复原属性并删除附加节点。当前记录先移出 hash，再进入可同步发信号的 `restore`，因此重入 `forget` 不会删除正被引用的记录或使遍历迭代器失效。恢复期阻止递归 `restoreAll` 和 `prepare` 重建记录。`restore` 提前以 QPointer 保存 native window；同步回调销毁窗口或 decoration 后，不再解引用已清空的对象。

Bridge 成员默认逆序析构会先销毁 clip 再恢复 appearance，QObject 基类随后才自动断开连接。本次在 Bridge 析构体内先断开发往 bridge 的 effects/renderer/appearance 回调，再在兄弟成员仍存活时明确恢复外观，避免恢复期回调访问已析构成员。没有全局阻塞 KWin 信号，没有 deleteLater，也没有修改上游动画行为。

## 冻结范围与构建

最终源文件摘要见 `bridge-SHA256SUMS`，范围为 CMakeLists、bridge.cpp、windowappearance.{cpp,h}、新增 tests/appearance_lifecycle_test.cpp。未创建分支或提交，保留仓库已有其它未提交工作。

本机 KWin 开发头/库版本 6.7.5；现有 paint API 头检测得到 6.7 无 presentTime 形式。真实插件 `kos_bridge.so` 在 `/tmp/kos-bridge-exit-crash-build` 完整编译成功，配置安装前缀仅 `/tmp/kos-bridge-exit-crash-prefix`，未执行 install。未增加生产依赖或改变安装路径/API 签名；测试默认关闭，沿用 `KOS_BRIDGE_BUILD_TESTS`。6.6 兼容分支未在本机编译，不能宣称通过。

复现命令：

```sh
cmake -S kwin/kos-bridge -B /tmp/kos-bridge-exit-crash-build -DCMAKE_INSTALL_PREFIX=/tmp/kos-bridge-exit-crash-prefix -DKOS_BRIDGE_BUILD_TESTS=ON
cmake --build /tmp/kos-bridge-exit-crash-build -j 4
ctest --test-dir /tmp/kos-bridge-exit-crash-build --output-on-failure
```

## 验证

- `bridge-build.log`：真实插件与离线 harness 构建成功。
- `bridge-ctest.log`：3/3 通过（appstreamtest、已有 rules_test、新 appearance_lifecycle_test）。
- 新回归测试直接链接生产 appearance manager、真实 KWin Item/OutlinedBorderItem 和生产 SceneShadowItem。验证 forget 不破坏场景边界、不提前销毁节点、断开状态连接、停止最后窗口计时器；父 QObject 删除后所有四类节点回收；活窗口场景恢复同步重入 `forget/restoreAll` 后容器和恢复门控正常。测试使用 nullptr 作为仅跟踪用窗口 key，不实例化真实 native window，因此不覆盖真实 Window 属性恢复与完整 compositor 动画交互。
- `bridge-sanitizers.log`：同一生产 manager/真实 Items fixture 使用 AddressSanitizer + UndefinedBehaviorSanitizer 编译运行通过。外部 KWin/Qt 库未启用 sanitizer；`ASAN_OPTIONS=detect_leaks=0`，未声明泄漏检测通过。
- `bridge-baseline.log`：独立 `/tmp` 源副本使用 `git show HEAD:kwin/kos-bridge/windowappearance/windowappearance.cpp` 的修复前实现，保留同一测试及 friend 访问头；回归测试退出 1，报告 `forget destroyed parent-owned scene nodes`。说明测试能够区分修复前后的具体删除行为，未复现原动画 SIGSEGV。
- `git diff --check` 通过。

测试平台固定 offscreen，清除 DISPLAY/WAYLAND_DISPLAY/GREETD_SOCK 并使 D-Bus session 地址指向不存在的专用路径，不会连接宿主认证/Wayland/D-Bus。测试未启动 compositor，也未接管输出。

## 未测与后续

真实登录 KWin 卸载动画效果的原崩溃栈、真实 native Window 属性恢复、常规桌面插件禁用/卸载、物理 DRM/VT 交接及黑帧时长尚未实机验收。安装本修复必须使用正常构建/更新并等下一次会话，不能替换当前已加载 .so 后热重载；Greeter 专用配置隔离由另一代理交付。本报告不承诺零黑帧或实机问题已消失。离线失败不会影响宿主会话，无需系统恢复；删除上述 `/tmp` 测试目录即可清理构建。

独立审查代理、结论和问题处置由父代理本批统一记录；审查之后若源文件改变须重新审查与更新摘要。
