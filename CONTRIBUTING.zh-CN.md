# 贡献规范

[English](CONTRIBUTING.md)

适用于人类和 AI 贡献者。先读[项目上下文](PROJECT_CONTEXT.zh-CN.md)、
[开发指南](docs/Development.zh-CN.md)及所改模块的架构文档。

## 验证与审阅

所有项目构建、测试、诊断和图形验证**只在专用虚拟机或托管 CI 执行**，禁止在维护者本机执行。
本机可以进行 Git 操作及源码编辑。允许推送候选提交触发 CI；合并与发布前必须通过检查，
发布还需要维护者明确授权，见[发布流程](docs/Releasing.zh-CN.md)。

在验证环境执行契约、文档检查和 `tools/run-tests.sh` 的相关测试层。
UI 改动还需 `--all` 及真实 VM 图形会话。CI 覆盖数据/平台/逻辑/无界面测试、标准应用以及
KWin 6.6/6.7/6.8 完整 SDK。SDK 编译和离线检查不能证明真实合成器运行正常。
报告精确提交、环境、命令、结果、跳过项和剩余限制。

## main 分支合入

通过 PR 提交改动，等待最新提交的全部必需检查通过，再使用 squash 合并。
main 要求分支跟上最新基线，禁止强推与删除，不强制要求他人审批。
管理员绕过仅用于紧急情况，不用于日常合入；已合并的 PR 分支自动删除。

必需检查：`source release selection`、`data + platform + logic + headless`、
`Calendar Calculator Weather build and tests`、KWin 6.6/6.7/6.8 三个独立 SDK 检查、
`QML changed-file checks`、`block-ai-coauthor`。
QML 检查按 PR 基线比较提交差异，不依赖未提交文件；无变更时明确报告零个文件。
它检查语法与重复声明，不能替代完整的导入、编译和运行测试。不能为了全绿而禁用有效检查。

## 改动卫生

- 暂存前检查 `git status --porcelain`，包括未跟踪文件。新增 QML、着色器、图标、原生源码及打包文件不能漏交。
- 保留用户无关改动，选择合适的分支/工作树并确认基线。
- 显式暂存路径，检查暂存差异，不用 `git commit -a`。
- 功能、文档、仓库卫生分别形成可审阅提交。
- 删除或移动前搜索全部引用，包括源码注释。
- 可复现回归测试放入 `tests/` 或所属模块；探针、日志、截图和会话报告放入忽略的 `tmp/` 或外部 CI/Release 制品。
- `.gitignore` 只收固定生成路径；一次性临时文件放 `tmp/`。保留第三方许可和资源来源。

## 提交信息

人类贡献者保持为 author 和 committer。提交信息不得带 AI 署名 trailer
（`Co-Authored-By` 指向 `noreply@anthropic.com` 等 AI 服务地址），author/committer
邮箱也不得是 AI 服务地址：GitHub 会把这些计入贡献者面板。
`.github/workflows/block-ai-coauthor.yml` 会在 PR 上拒绝命中这些规则的新提交。
PR 被拒时，改写受影响提交的信息（`git commit --amend` 或 `git rebase -i` 的 reword），
用 `--force-with-lease` 推送即可；author 不变。

## 文档约定

[文档索引](docs/README.zh-CN.md)定义每个主题的权威入口。
架构/开发指南是给 **AI 贡献者**的操作上下文：说明现行所有权、契约、源码入口、故障行为及验证要求。
将过时方案、会话流水账整理为当前约束；计划和未经测量的性能不得写成已实现或已验证。

英文为默认。同次改动同步维护中英文对照；发布说明及安装、发布、开发入口提供双语。
详细内容集中一处并链接，不在多个指南重复命令和易变发布状态。
VERSION 与不可变 Tag 标识源码；Release 证据说明实际验收。历史结果保留原有验证范围。
