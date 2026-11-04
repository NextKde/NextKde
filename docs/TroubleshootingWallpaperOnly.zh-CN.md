# 故障排查：安装后开机只剩壁纸

> 记录时间：2026-11-04 · 适用版本：0.1.0-dev @ `3631ffc7`（KWin/Plasma 6.8.2、Quickshell 0.3.2）

## 现象

执行 `./tools/kosctl install` 后注销或重启，桌面只剩壁纸，没有顶栏、Dock 和桌面图标。

## 结论

不是壁纸、显卡或安装失败。`install` 本身是成功的，但负责绘制界面的 `kos-shell.service`（Quickshell）持续崩溃，于是只剩 plasmashell 按设计画出来的那层壁纸。

## 因果链

1. `take_over_plasma_desktop` 把 `~/.config/plasmashellrc` 的 `ShellPackage` 改成 `org.kos.desktop`。这个 shell 包按设计**只渲染壁纸**，所有 UI 由 Quickshell 提供，两半合起来才是完整桌面。
2. 本次开机 17:28:45，`kos-shell.service` 从 17:28:57 起每 2 秒崩溃重启（累计 230+ 次）：

   ```
   qs: ERROR: Failed to load configuration
     caused by @desktop/DesktopEnvironment.qml[5:1]: module "../shared/qml/i18n" is not installed
   systemd: kos-shell.service: Main process exited, status=255/EXCEPTION
   ```

3. 安装产物中 `~/.config/quickshell/kos/shared/qml/i18n/` 和 `foundation/` 是空目录，缺 `qmldir`、`I18n.qml` 及语言文件。
4. 根因：源码树里 8 个 git 符号链接被物化成了**空目录**：

   ```
   shell/shared/qml/{controls,foundation,i18n}
   shell/Kos/Ui/{colorize,controls,foundation,i18n,wallpapers}
   ```

   它们原本都指向 `../../../shared/qml/*`，仓库里的真实文件还在（时间戳与整批源码一致），属于源码导入 / 同步 / 解压环节丢了软链接，不是 `install` 造成的。
5. `deploy_artifacts` 只额外补了 `shared/qml/controls`，`materialize_kos_ui` 补了 `Kos/Ui/*`，**没有补 `shell/shared/qml/i18n` 和 `foundation`**。扫描全部 QML 相对 import，恰好只有这两个目标缺失，其中 `i18n` 被 100 多处引用。

## 为什么重启后才暴露

安装摘要注明「未打断当前会话，需注销或重启」：三个用户单元只 `enable` 不启动，`ShellPackage` 也要 plasmashell 下次启动才读取。所以重启后新配置生效，故障才显现。

## 已排除项

KWin 6.8.2 与插件 ABI 戳匹配且 kwin_wayland 正常；Quickshell 0.3.2 已安装；kos-platform 已 READY；kos-data socket 正常；三个单元都在 `graphical-session.target.wants` 里。

## 修复

根本做法（恢复软链接再重装）：

```bash
cd /home/louyve/NextKde
git checkout -f -- shell/shared/qml shell/Kos/Ui
git status --short                 # 应无输出
./tools/kosctl install
./tools/kosctl start
```

临时做法（立刻恢复当前会话，下次 `install` 会再被清空）：

```bash
cp -r shared/qml/i18n/.       ~/.config/quickshell/kos/shared/qml/i18n/
cp -r shared/qml/foundation/. ~/.config/quickshell/kos/shared/qml/foundation/
systemctl --user restart kos-shell.service
```

## 修复结果与复核（17:42 完成，17:48 复核）

- 8 个 symlink 全部恢复；就修复本身而言 `git status` 是干净的（文件本就在仓库里，只是被破坏了）
- 安装目录 `i18n` 5 项、`foundation` 35 项齐全；全量 QML 相对 import 168 处，缺失 0
- 最后一次 QML 加载失败停在 17:42:19，此后三个服务由 systemd 正常托管，开机自启链接完好
- 仍可能出现的 `PimWidgetService.qml` 找不到 `widget-snapshot.json` 是 PIM 小组件的无害警告

## 防复发建议

`kosctl` 存在一个健壮性缺陷：遇到丢软链接的 checkout 时，没有校验 `shell/shared/qml` 下的子目录是否非空，安装照样报成功。建议在 `deploy_artifacts` 之后增加一次 QML 模块完整性校验（检查 `qmldir` 是否存在、目录是否非空），缺失时让 `install` 明确失败并提示恢复 symlink。

## 最小修复集

另有一份仅用于「在别处应用同一修复」的最小文件包，包含 8 个符号链接、`shared/qml/i18n`（5 个文件）、`shared/qml/foundation`（35 个文件）、说明文档与 SHA256SUMS。符号链接是修复的核心，因此该包只用 tar.gz 分发，不用 zip——多数 zip 解压器会把链接写成普通文件或空目录，等于把故障一起打包进去。
