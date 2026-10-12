# 项目 App 定位与独立安装方案

这是用户新增的产品要求：Greeter 属于本项目的独立 app，与天气、日历等同属 apps 产品体系，具有自己的安装命令。当前仅补充设计文档，不实现或执行安装。

## 已核对的现有约定

仓库 apps/README.zh-CN.md 规定应用为独立进程，可使用 shared/，不能导入 shell/desktop/；天气有独立 CMake preset weather-dev。现有 ./tools/kosctl install apps 与 tools/install-apps.sh 面向普通用户级应用合集。登录前 Greeter 需要系统会话，因此复用 app 的组织与共享组件约定，不照搬普通用户应用的运行权限和桌面启动入口。

## 目标结构

建议 apps/greeter/ 作为本项目 app 的源码与资源根；产品名暂定 KOS Greeter。目录名与实现语言在 T01 记录最终决策。独立运行入口、构建或打包入口、版本、依赖清单、中英文说明、卸载与恢复说明均须具备。当前 greetd + 独立 KWin + Quickshell 为候选，不因 app 定位改成桌面 Shell 子页面；如果保持 QML/Quickshell 方案，需适配仓库打包，不假定天气的 C++ 可执行结构必须照搬。

可信共享渲染组件来自 shared/；登录前 app 不导入 shell/desktop/、其他 app 或完整用户服务。桌面侧发布/交接适配属于边界清楚的配套组件，不使登录 app 依赖已运行的用户桌面。Greeter 不是普通桌面应用入口，不能点击 .desktop 即占用真实登录 seat。

## 专属命令契约（拟议，当前不存在）

- ./tools/kosctl install greeter：仅构建、打包和安装本 app 及其必要配套；缺依赖时明确报告。
- ./tools/install-greeter.sh：建议提供同等专属脚本入口，避免必须安装整个 app 合集。
- ./tools/kosctl uninstall greeter：按安装清单卸载，并先检查活动服务与回退路径。

最终命令在实施时按 kosctl 现有解析约定确定并更新所有文档；上述是待实现契约，不是可立即执行指令。安装资源与启用为系统登录管理器必须分开：install 不自动停用当前显示管理器、不自动切换 PAM/默认服务。持久启用需明确操作入口、备份和恢复说明，并遵守用户授权范围。普通 install apps /整体项目安装不得顺带启用 Greeter，也不得覆盖旧 apps/sddm。独立安装无需安装天气、音乐等无关 app；按需依赖必须列明。

## 任务与验收

T01 定义 app 边界和构建方案；T14 交付独立安装、卸载、升级与回退方案及验收证据。实现测试包括干净环境独立安装、依赖缺失、重复安装、升级失败回滚、卸载恢复、合集安装不启用 Greeter；不得以用户级前缀的成功安装推导系统登录配置成功。当前研究不运行这些操作。见 acceptance.md 的 A19 和强制独立审查规则。

## 2026-10-12 用户明确授权的脚本交付

上述为历史设计契约。用户现明确要求专属安装脚本同时禁用原默认管理器并启用本app；据此交付 `tools/install-greeter.sh`（默认选择下次开机greetd，`--files-only`保留启用状态）与 `tools/rollback-installed-greeter.sh`。没有修改普通apps合集或kosctl入口，不自动运行安装。本轮脚本隔离验证与未测项见 [证据](evidence/persistent-install/REPORT.md)，[操作说明](../../apps/greeter/INSTALL.zh-CN.md)及[独立审查](reviews/persistent-install.md)。实机T14/A19仍未测。

## 2026-10-12 自动更新脚本追加交付

用户明确要求已安装时自动处理最新本地源码。本轮增加原位app更新，相同bundle跳过、不同bundle自动替换；保留首次恢复快照及服务启用状态，不重启当前桌面，不自动拉取远程源码。当前操作见 [安装/更新说明](../../apps/greeter/INSTALL.zh-CN.md)，证据与限制见 [自动升级记录](evidence/automatic-upgrade/REPORT.md)。本轮未执行宿主安装或系统切换；独立审查记录见 reviews/automatic-upgrade.md，完整T14/A19仍缺实机验收。
