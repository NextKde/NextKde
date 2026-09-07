# KOS NixOS 快速启动指南

## 概述

KOS 提供了专门针对 NixOS 的控制接口，简化了在 NixOS 上的安装和管理。

## 安装

### 方法 1: 使用 NixOS 模块 (推荐)

1. 在你的 `flake.nix` 中添加 KOS 作为输入:

```nix
{
  inputs = {
    # ... 其他输入
    nextkde = {
      url = "git+https://github.com/SuceV587/NextKde.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
}
```

2. 在 NixOS 配置中启用 KOS:

```nix
{ inputs, ... }:
{
  imports = [
    inputs.nextkde.nixosModules.kos
  ];

  services.kos.enable = true;
}
```

3. 重新构建系统:

```bash
sudo nixos-rebuild switch
```

### 方法 2: 手动安装

```bash
git clone https://github.com/SuceV587/NextKde.git
cd NextKde
./tools/nix-start.sh start
```

## 使用

### kos-ctl 命令 (推荐)

安装后，你可以使用 `kos-ctl` 命令管理 KOS:

```bash
kos-ctl start      # 启动 KOS
kos-ctl stop       # 停止 KOS
kos-ctl restart    # 重启 KOS
kos-ctl status     # 查看状态
kos-ctl logs       # 查看日志
kos-ctl doctor     # 诊断问题
kos-ctl sync       # 同步配置
kos-ctl enable     # 启用开机自启
kos-ctl disable    # 禁用开机自启
```

### nix-start.sh 脚本

如果 `kos-ctl` 尚未安装，可以使用备用脚本:

```bash
./tools/nix-start.sh start
./tools/nix-start.sh status
./tools/nix-start.sh logs
```

## 常见问题

### 服务启动失败

如果遇到服务启动失败:

```bash
# 检查问题
kos-ctl doctor

# 查看详细日志
kos-ctl logs
```

### Shell 配置问题

如果界面显示异常:

```bash
# 重新同步配置
kos-ctl sync
kos-ctl restart
```

### 权限问题

NixOS 上的只读文件权限是正常的，KOS 会自动处理:

```bash
# 脚本会自动修复权限问题
kos-ctl start
```

## 架构说明

KOS 在 NixOS 上使用以下组件:

- **kos-platform**: 系统集成服务
- **kos-data**: 数据服务
- **kos-shell**: Quickshell 桌面界面
- **kos-shell-init**: 配置初始化服务

所有组件都通过 systemd 用户服务管理，支持自动重启和会话集成。

## 卸载

1. 在 NixOS 配置中禁用:

```nix
services.kos.enable = false;
```

2. 重新构建系统:

```bash
sudo nixos-rebuild switch
```

3. 清理垃圾:

```bash
nix-collect-garbage
```
