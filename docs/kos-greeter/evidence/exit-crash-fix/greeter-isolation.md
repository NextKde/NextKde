# Greeter KWin 专用配置隔离（待独立审查）

2026-10-13。用户已授权调用独立子代理修复；本批仅稳定登录 compositor 退场，不包含两 KWin 之间 DRM 保帧、资源预取、安装或系统切换。

## 实现

`apps/greeter/companion/greeter_config.py` 中受控配置常量在每次生产入口启动时写入经过验证的 Greeter UID 运行时目录下新建的随机私有子目录。正式 bundle 由现有 root 安装器管理 helper，不从用户 home 或桌面 kwinrc 复制。`XDG_CONFIG_HOME`、`XDG_CONFIG_DIRS`、`XDG_CACHE_HOME`、`XDG_DATA_HOME` 指向私有目录；传给 exec 的 `XDG_RUNTIME_DIR` 也为已验证路径。私有 config-dirs 是非空路径值，目录内容为空，避免 Qt 在空环境值时使用系统默认 config dirs。移除旧 KDEHOME/KDEROOTHOME 配置根，不改 HOME、系统 XDG_DATA_DIRS、字体/主题搜索或认证 socket。

入口保持 dbus-run-session → KWin 的原 exec 关系，仅将专用环境作为 execve 参数，不修改当前 Python 环境或认证后 Plasma wrapper。`--check` 在配置准备之前返回，不制造运行时目录。KWin 无已验证的 --config 参数，本批使用标准 KConfig 搜索路径。

本机 `/usr/share/kwin-wayland/effects/*/metadata.json`（已读取）提供脚本效果 ID/default。明确关闭 kos_bridge，以及 dialogparent、dimscreen、eyeonscreen、fade、fadedesktop、fadingpopups、frozenapp、fullscreen、login、logout、maximize、scale、sessionquit、squash、translucency、windowaperture。其中多个默认开启，空配置不足以隔离。Greeter 动画由 QML 自己执行，以上桌面窗口/会话脚本无本登录界面需求；不关闭 core blur/contrast 等原生效果，不改 QML 玻璃或 240Hz/1.5 输出策略。未知未来新增默认脚本不在此清单，需依版本复核。

## 权限与失败

以目录 fd + 每组件 O_NOFOLLOW 检查，拒绝 symlink、非 root/当前 UID owner、group/world 可写祖先。运行时根须当前 UID 拥有且严格0700；新配置/缓存/data目录0700，kwinrc0600。优先 XDG_RUNTIME_DIR，缺失使用 `/run/user/<UID>`；不存在或不可信时记录固定 `KOS_GREETER_CONFIG unavailable` 并 exit70，不回退到继承的桌面配置。不读取用户私有 home、不打开认证 socket。

新子目录位于 logind UID runtime 下，保持至 runtime teardown，避免 compositor 子进程与删除竞态。没有 /tmp 持久残留，也没有新增监督/重启行为。若同 UID 存在其他 session 或 linger，logind 可能延后清理；缓存可增长，本批不承诺立刻删除或固定大小。常规最后一个 Greeter 会话退出后的实际 runtime 清理仍未实机验证。

## 验证边界

最终15项纯隔离配置/入口测试通过，包括真实 `kreadconfig6` 搜索得到所有显式false、原桌面fixture保持true、UID/权限/symlink/可写祖先异常、独立启动路径、入口仅传专用环境、异常exit70不exec、--check不创建配置、临时copy及正式bundle清单包含helper。最终44项既有安装事务、12项session-output、5项UI supervisor、20项switch-scripts隔离回归通过，合计96项；命令、输出和退出码见 greeter-tests.txt。

最终守卫版96项回归不连接真实 GREETD_SOCK，不启动 compositor/DBus/登录 seat，不修改系统服务、账户/PAM或已安装 app；首次旧测试的误启动、失败与恢复单列在下文，未计入最终通过结果。kreadconfig6 测试清除 DISPLAY/WAYLAND_DISPLAY/GREETD_SOCK/DBUS_SESSION_BUS_ADDRESS，仅读私有fixture。实际 KWin 加载效果、正常注销退出、物理多屏模式和黑帧时长仍未测，不宣称零黑帧或完整跨会话验收。

## 回归测试适配失败与恢复

首次运行旧 `session-output.test.py` 时，该测试仅 mock `os.execv`；新入口使用 `execve`，因此 mock 未拦住入口，意外执行了 dbus-run-session/KWin。测试用 `clear=True` 清除环境，只带非真实 `GREETD_SOCK=fixture`，没有 DISPLAY/WAYLAND_DISPLAY/认证凭据；当时配置helper尚未向exec补充XDG_RUNTIME_DIR，KWin报 `XDG_RUNTIME_DIR is invalid or not set`、`could not add wayland socket` 后退出139。此轮失败，不计通过；未连接真实认证socket、未启动系统服务。

已更新旧入口回归为 mock execve 并 mock 配置准备，断言专用环境参数。修正后新增防穿透守卫与switch-scripts适配，经独立审查确认安全边界后，最终15+44+12+5+20共96项纯隔离回归全部通过。进程表核验没有fixture dbus-run-session/KWin残留（只读发现原有宿主KWin，未操作）；按精确已知随机目录、UID、文件清单与受控kwinrc字节校验后删除了该失败测试创建的单个runtime目录。未执行真实系统恢复命令。该适配失败说明启动入口测试必须同步拦截实际exec接口，不应单凭测试标题认为启动已隔离。
