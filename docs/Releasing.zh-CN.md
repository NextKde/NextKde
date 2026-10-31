# 发布与版本维护

[English](Releasing.md)

只维护**最新正式版**。`main` 开发，`release/X.Y` 准备正式版及补丁。
旧 Tag 保留用于追溯及兼容条件下的重装回退，不并行长期维护。公开 beta/RC 可选，维护者验收后可直接发布正式版。

## 身份与源码选择

`VERSION` 标识桌面发行版，不替代 IPC、数据库 schema 或应用自身版本。main 保留开发后缀，
发行分支使用精确 `X.Y.Z`。补丁递增 Z，新功能批次递增 Y；0.x 也要说明不兼容变化。
已发布 `vX.Y.Z` Tag 不可移动，修复需同步 main 与发行分支。

```sh
./tools/kosctl update             # GitHub Latest 正式版
./tools/kosctl update v0.1.0      # 显式选择历史 Tag
./tools/kosctl update main        # 显式开发版
./tools/kosctl version            # 分别显示部署文件与源码
```

选择器需要 Git、Python 3.9+。`update` 获取 origin 精确引用并 detached HEAD 检出，保留分支。
脏文件/未跟踪项、未完成 Git 操作、无正式版、API 限流、网络错误均停止，不重置工作树或静默切 main。
Fork 查询自身 origin；非 GitHub origin 需显式引用。浅克隆选择版本后继续保持浅历史，完整克隆保留原历史。
删除当前文件不会自动缩小历史 Git 对象。

`update` 只选源码，`install` 部署当前检出，`start` 启动已安装服务。KWin 更新需注销登录或重启。
Debian 安装器默认 stable，`--version main` 选开发，`--version vX.Y.Z` 固定版本（`--branch` 为别名）。
可能先装依赖，但必须成功选择请求源码后才构建 NextKDE。

## 准备、验收、发布

1. 确定范围及提交，创建/沿用 `release/X.Y`，只接收修复、发布文档和版本调整。0.1 补丁沿用 `release/0.1`。
2. 按[英文默认双语模板](releases/TEMPLATE.zh-CN.md)更新说明、依赖、升级/回退限制、已知问题和相关 PR；审阅文档及译文。
3. VERSION 改为目标版；推送精确候选提交，要求 **7 项** tests 任务通过：源码选择、数据/平台/逻辑/无界面、应用、变更 QML、
   KWin 6.6/6.7/6.8 SDK。每套 SDK 使用完整匹配仓库快照，构建链接插件和 Glass、跑离线回归并检查官方头文件。
   其他提交的绿灯不能替代。
4. 保存 VM 快照，在精确候选完成下列验收；修复后重验相关项，记录提交、环境、命令、结果、跳过项。
5. 已有明确发布授权且门槛全过后，在验收提交创建不可变 `vX.Y.Z`，要求 `release-checks` 的 Tag/VERSION 检查通过。
6. 创建正式 Release，附源码、校验和、双语验收范围，核对制品摘要并明确设为 **Latest**。
   工作流只查身份，不自动发布。
7. VM 用真实 GitHub Latest 端点执行无参数 `kosctl update`，安装、启动、重启，核对 Installed/Source 和插件并附结果。
   导出证据后恢复快照并关机；旧版停止维护。

## 必需 VM 验收

项目构建/测试/图形/诊断**只在 VM 或托管 CI 执行**，禁止本机。记录发行版、架构、Qt、KWin、Quickshell、GPU/后端。
SDK 成功不代表三套真实桌面成功，未验发行版、功能、跨 schema 降级需明确标注。

- 契约、文档、源码选择回归、相关测试及真实 Shell 图形流程；确认加载完成并检查 QML/运行错误。
- 全新**默认核心安装**、已安装正式版→候选升级、同版重装、候选→上一已验证 Tag 重装回退、配置保留和备份恢复。
- 实际运行 **`./tools/kosctl install apps`**，不能手工 CMake 代替；确认四个标准应用、ListenFree OFF、无 SDK 准备，
  音频 MIME/旧播放器不变、核心 Settings 不变、旧 ON 缓存重置 OFF、无核心的应用专用前缀成功。
  显式音频另测；缺少音频依赖时应在 SDK 构建前失败。
- 服务、自启动、重启/注销加载插件，启动器/Dock/顶栏/设置/通知及受影响应用交互，卸载后重启恢复 Plasma。
- 无效引用、脏源码、API/网络失败、构建/部署失败正确停止，部分替换后不能误报完整安装。
- 配置保留，旧运行文件清除，备份可读；可选组件和真实模型推理若声称覆盖需单独验收。

## 备份与回退

替换前把管理的 Shell/Settings 运行树、`~/.config/kos`、旧版本记录备份到
`${XDG_STATE_HOME:-$HOME/.local/state}/kos/install-backups/`；备份失败则停止。
重建运行树清理旧 QML/插件，保留用户状态，备份手工保留/清理。
备份不含全部系统插件、依赖及应用数据。部署不是事务，部分替换会撤销旧记录。
记录在 `${KOS_PREFIX:-$HOME/.local}/share/kos/release.json`，运行中的进程可能仍是旧版。

确认配置/schema、依赖兼容后，重装已验证旧 Tag：

```sh
./tools/kosctl update v0.1.0 &&
./tools/kosctl install &&
./tools/kosctl start
```

然后注销登录或重启。恢复旧格式配置前先停相关服务；不以删除个人数据作为回退方案。
跨 schema 降级要另测，早期 Tag 可能不清理新版残留；完整恢复依靠系统备份/VM 快照。
NixOS 固定 flake 输入和 lock 并重建，不在只读 store 运行 `update`，见[NixOS](nixos-quickstart.zh-CN.md)。
打包版查询真实部署记录，`KOS_RELEASE_RECORD` 可显式指定另一真实部署记录。

## 发布后严重问题

标注受影响 Release 并给出已验证恢复办法，必要时明确撤回 Latest 推荐，避免默认继续安装已知坏版。
沿当前发行分支修复并递增 Z，按相同门槛发布，同步 main。不移动坏 Tag，不承诺为每个旧系列打补丁。
