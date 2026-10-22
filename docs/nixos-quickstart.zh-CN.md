# NixOS 安装

[English](nixos-quickstart.md)

这是声明式打包指南，不代表 NixOS 整机运行验收完成；实测环境见[发布说明](releases/v0.1.1.zh-CN.md)。
固定已发布 Tag 并保留 `flake.lock`；只维护最新正式版。示例使用已存在历史 `v0.1.0`，
升级时从[最新 Release](https://github.com/SuceV587/NextKde/releases/latest)选择新 Tag。

## 模块配置

系统 `flake.nix` 输入：

```nix
nextkde = {
  url = "git+https://github.com/SuceV587/NextKde.git?ref=v0.1.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

向 `nixpkgs.lib.nixosSystem` 传 `specialArgs = { inherit inputs; };`，模块中：

```nix
{ inputs, ... }:
{
  imports = [ inputs.nextkde.nixosModules.kos ];
  services.kos.enable = true;
  services.kos.weather.enable = true; # 可选独立天气应用
}
```

修改 Tag 后更新 lock 并重建，`your-host` 换为实际配置名：

```sh
nix flake update nextkde
sudo nixos-rebuild switch --flake .#your-host
kosctl version
systemctl --user status kos-shell-init kos-platform kos-data kos-shell
```

包读取根 VERSION 并记录可得 revision；打包 `kosctl version` 查询
`/run/current-system/sw/share/kos/release.json` 的实际核心部署记录，`KOS_RELEASE_RECORD` 可另选真实部署。
不在只读 store 运行源码 `update`；开发输入可显式 `ref=main`，但不是稳定版。

## 所有权与排查

`flake.nix` 管包、KWin 集成和用户服务，`kos-shell-init` 在启动 Shell 前复制选定包的 QML/模块。
原生插件更新需注销登录或重启。初始化/服务失败查日志并修输入/包，不反复 chmod 或覆盖 store：

```sh
journalctl --user -b -u kos-shell-init -u kos-platform -u kos-data -u kos-shell
```

模块使用宿主的包集构建，包括宿主的 Qt/KWin 版本及 overlay。
旧 `kos-ctl` 和 `kos-shell-init` 共用同一部署脚本，绑定模块选定的包；`kos-ctl sync` 也会复制原生 QML 模块，
不再搜索任意匹配的 store 目录。版本化升级使用选定的系统 generation。
`tools/nix-start.sh` 是另一开发辅助，验收不混用手工与声明式 unit。
Settings 包需包含 QML 和 ECM 构建依赖；缺模块是打包错误，不绕过初始化。

设 `services.kos.enable = false;` 并重建以停用，保留恢复需要的配置/状态。
系统回退使用兼容旧 NixOS generation，跨 schema 降级仍需验证。贡献者构建/测试/图形验收只在 VM/CI。
GitHub 的 `nix packaging` 工作流分别构建关闭和开启 Weather 的模块，检查宿主 overlay 和 ARM 求值，
并在不启动桌面的情况下检查 QML 部署。
