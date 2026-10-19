# 文件安装与 VM 启用分离

普通用户从仓库执行：

```sh
./tools/install-greeter-handoff.sh --check
./tools/install-greeter-handoff.sh
```

默认读取 `~/.cache/nextkde-builds/drm-handoff` 已构建产物，不重新编译。先普通用户打包/重定位/记录系统依赖摘要，安装步骤才调用 sudo。所有私有 ELF 路径仅使用 `$ORIGIN`，安装时复验 RPATH/SONAME。安装目标固定 `/opt/kos-handoff`，不覆盖 `/usr/bin`，不启用或重启任何服务。需已有 root 管理的 `/usr/local/lib/kos-greeter/app`；此命令不安装普通 app，也不运行原有会切换登录器的 install-greeter.sh。

需要 python3、patchelf、readelf、ldd、sudo 和与构建机相同的系统 KDE/Qt/图形依赖。包记录并校验实际系统共享库摘要，不是跨发行版分发包。构建缺失、系统依赖更新或 hash 不一致会失败，不会给出安装成功。已有 `/opt/kos-handoff.previous` 时拒绝覆盖备份。

文件级回滚或全新安装卸载（均不切换服务，必须先在 VM 恢复原服务配置）：

```sh
sudo ./tools/install-greeter-handoff.sh rollback
sudo ./tools/install-greeter-handoff.sh uninstall
```

回滚使用 `.previous`，卸载移走活动前缀；两者保留 `.displaced` 供恢复且不覆盖现有快照。升级失败会还原前缀。

## 仅一次性 VM 的显式启用示例

下面命令仅用于已有 app/greeter 用户、相同依赖的一次性 VM。systemd-logind 的 auto_features=disabled 构建是隔离原型，不是发行版替代；禁止在当前桌面执行此段。

```sh
sudo mkdir -p /etc/systemd/system/greetd.service.d /etc/systemd/system/systemd-logind.service.d
sudo tee /etc/systemd/system/greetd.service.d/90-kos-handoff-vm.conf >/dev/null <<'UNIT'
[Service]
Environment=KOS_GREETD_HANDOFF=1
ExecStart=
ExecStart=/opt/kos-handoff/bin/greetd -c /opt/kos-handoff/examples/greetd-vm-only.toml
UNIT
sudo tee /etc/systemd/system/systemd-logind.service.d/90-kos-handoff-vm.conf >/dev/null <<'UNIT'
[Service]
ExecStart=
ExecStart=/opt/kos-handoff/systemd/bin/systemd-logind
UNIT
# 在将要登录的 VM 普通用户账户执行：
mkdir -p ~/.config/systemd/user/plasma-kwin_wayland.service.d
install -m 0644 /opt/kos-handoff/examples/plasma-kwin_wayland.service.vm-override ~/.config/systemd/user/plasma-kwin_wayland.service.d/90-kos-handoff-vm.conf
# 先保存 VM 快照，从 VM TTY 执行；会结束 VM 图形会话：
sudo systemctl daemon-reload
sudo systemctl restart systemd-logind greetd
```

VM 恢复：删除上述三个精确的 `90-kos-handoff-vm.conf` 文件，执行 `sudo systemctl daemon-reload` 并重启 VM。恢复原二进制配置之后才进行文件 rollback/uninstall。安装器不会执行以上任何命令。真实 DRM/PAM/VT 连续性仍未验收。
