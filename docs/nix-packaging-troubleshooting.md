# KOS Desktop Shell Nix 打包问题排查记录

## 背景

用户需要为 KOS Desktop Shell（基于 KDE Plasma 6 Quickshell 的桌面 shell）完成 Nix 打包，目标是 `nixos-rebuild switch` 后能正确安装所有组件，`kos-settings` 能正常启动。

项目仓库：`git@gitee.com:xiaoyintx_ciallo/test.git`
用户 NixOS 配置：`/home/xiaoyintx/nix-configuration-xiaoyintx`

---

## 第一阶段：工具脚本与基础 Nix 打包

### 1.1 tools/kosctl 重构

**改动：**
- 重构 `ensure_kwin_build_dependencies()`，支持 NixOS（`is_nixos()`）
- `doctor` 命令添加 NixOS 提示（`nix-env -iA` 安装方式）
- 新增 `nix build`、`nix install`、`nix start`、`nix shell` 子命令
- 新增 `nix-status` 检查 Nix 打包和 systemd 服务状态

### 1.2 新增打包文件

- `nix/kos-platform.nix` — 构建 C++ 平台守护进程
- `nix/kwin-effects-glass.nix` — Glass 特效插件

### 1.3 修复现有打包文件

- `nix/package.nix` — 整合所有组件 + systemd 服务 + 快捷方式创建
- `nix/shell-data-service.nix` — 修复 Go 模块路径、systemd 服务路径
- KWin 插件路径修正为 `integrations/kwin/...`

### 1.4 flake.nix 完善

- 从 GitHub 切换到 Gitee 远程（`git+https://` 协议）
- 使用南京大学镜像源加速 nixpkgs 下载
- 暴露 `packages`、`nixosModules.kos`、`services.kos.enable`

---

## 第二阶段：kos-settings 启动失败排查

### 问题 1：Nix 字符串插值错误

**报错：**
```
ReferenceError: Can't find variable: main_window_width
```

**根因：** Nix 字符串插值不解析 `..`，`${src}/../shared` 在沙箱中不被识别。

**修复：** 改为 `${src}/../../shared/qml/controls`。

---

### 问题 2：QML 文件未安装到输出路径

**报错：**
```
file:///nix/store/...-shared/qml/controls/LinearProgress.qml: No such file or directory
```

**根因：** `installPhase` 只复制了二进制文件，`main.qml` 和 `controls/` 目录没有被复制到 `$out/share/kos/settings/`。

**修复：** 在 `kos-settings.nix` 的 `installPhase` 中添加：
```bash
mkdir -p $out/share/kos/settings
cp ${src}/apps/settings/main.qml $out/share/kos/settings/main.qml
cp -r ${src}/../../shared/qml/controls $out/share/shared/qml/controls
```

---

### 问题 3：系统 PATH 缺少 kos-settings

**报错：**
```
kos-settings: command not found
```

**根因：** `flake.nix` 的 NixOS module 只把 `kos-desktop` 加入 `environment.systemPackages`，没有包含 `kos-settings`。

**修复：** 在 `flake.nix` 的 `environment.systemPackages` 中添加 `kos-settings`：
```nix
environment.systemPackages = [ self.packages.${system}.kos-desktop self.packages.${system}.kos-settings ];
```

---

### 问题 4：CMake 从根目录构建，触发平台依赖

**报错：**
```
CMake Error at platform/CMakeLists.txt:10 (find_package):
  Could not find "KF6IconThemes"
```

**根因：** `kos-settings.nix` 设置 `src = src`（repo 根目录），CMake 从根目录运行，触发了 `platform/CMakeLists.txt` 的依赖检查。

**修复：** `kos-settings.nix` 改用自定义 `buildPhase`，只构建 `apps/settings` 子目录：
```nix
dontBuild = true;
installPhase = ''
  cmake -S "${src}/apps/settings" -B build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$out
  cmake --build build --parallel
  cmake --install build
  # 复制 QML 文件
  cp ${src}/apps/settings/main.qml $out/share/kos/settings/main.qml
  cp -r ${src}/../../shared/qml/controls $out/share/shared/qml/controls
'';
```

---

### 问题 5：`extra-cmake-modules` 缺失

**报错：**
```
Could not find a package configuration file provided by "KF6IconThemes"
```

**根因：** 即使路径正确，CMake 仍然找不到 `KF6IconThemes`，因为缺少 `extra-cmake-modules` 提供的 CMake 模块路径。

**修复：** 在 `kos-platform.nix` 的 `nativeBuildInputs` 中添加 `kdePackages.extra-cmake-modules`。

---

## 最终可用方案

### 安装命令

```bash
# 一键构建 + 部署 systemd 服务 + 启用 KWin 特效
./tools/kosctl nix install

# 启动
./tools/kosctl start

# 验证
kos-settings
quickshell --path /run/current-system/sw/share/kos-desktop
```

### NixOS 配置

```nix
# flake.nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  nextkde = {
    url = "git+https://gitee.com/xiaoyintx_ciallo/test.git";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};

# hosts/omen-16/config.nix
{ inputs, ... }: {
  imports = [ inputs.nextkde.nixosModules.kos ];
  services.kos.enable = true;
}
```

---

## 关键发现与经验

1. **Nix 字符串插值不解析 `..`** — 使用 `${src}/../../` 或在 `installPhase` 中用 `$src` 引用
2. **CMake 从 src 根目录运行** — 子目录需要 `dontBuild = true` + 自定义 `buildPhase`
3. **Gitee 只支持 `git+https://`** — 不能用 `git+ssh://`（除非配置 SSH 密钥）
4. **quickshell 不在 nixpkgs** — 需要单独安装或运行时路径
5. **systemd 服务路径需要 patch** — 用 `sed` 替换 `%h/.local/...` 为 Nix store 路径
6. **KWin 插件不自动安装到系统路径** — 需要复制到 `lib/kwin/` 并启用 `environment.pathsToLink`

---

## 修改文件清单

| 文件 | 改动内容 |
|------|----------|
| `tools/kosctl` | NixOS 支持、nix 子命令、doctor 增强 |
| `flake.nix` | Gitee 远程、NixOS module、services.kos.enable |
| `nix/package.nix` | 整合所有组件、systemd 服务、路径 patch |
| `nix/kos-settings.nix` | QML 安装、自定义 buildPhase |
| `nix/kos-platform.nix` | 新增、C++ 平台守护进程构建 |
| `nix/kwin-effects-glass.nix` | 新增、Glass 特效插件构建 |
| `nix/kwin-dock-window-animation.nix` | 修复路径 |
| `nix/kwin-context-menu-input.nix` | 修复路径 |
| `nix/shell-data-service.nix` | 修复 Go 模块路径、systemd 服务路径 |
| `nix-configuration-xiaoyintx/flake.nix` | 添加 nextkde input |
| `nix-configuration-xiaoyintx/hosts/omen-16/config.nix` | 导入 module、启用服务 |
