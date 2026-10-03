# 贡献与提交规范 / Contributing & Commit Conventions

**中文**

本文件只管**提交与改动卫生**。构建、安装、运行见 `README.md`；NixOS 见 `docs/nixos-quickstart.md`。
对 AI 会话同样适用 —— 提交前请逐条自查。

**English**

This document covers **commit and change hygiene** only. For building, installing and running, see
`README.md`; for NixOS, `docs/nixos-quickstart.md`. The same rules apply to AI sessions — check every
item below before committing.

---

## 1. 提交前看全部 `git status`（含未跟踪）

**中文**

本项目最容易踩的一条：新增的 QML、SVG、PNG、`.qsb`、原生源文件和 Nix 包大多是**新文件**，
`git diff` 和 `git commit -a` 都看不见它们 —— 只看 diff 会提交出一个跑不起来的树。

```bash
git status --porcelain          # 逐行看，包括 ?? 的未跟踪项
git diff --cached --stat        # 确认暂存的到底是什么
```

**English**

The easiest mistake to make here: newly added QML, SVG, PNG, `.qsb`, native source and Nix files are
mostly **new files**, and neither `git diff` nor `git commit -a` can see them — commit off the diff
alone and you ship a tree that does not run.

```bash
git status --porcelain          # read every line, including the ?? untracked entries
git diff --cached --stat        # confirm what is actually staged
```

---

## 2. 提交前本地测试必须全部通过

**中文**

提交前必须在本地把测试跑一遍，**全部通过才能提交**。跑不过就修到过为止；确实修不了的，
不要提交，并把失败输出留在 `tmp/`。

```bash
./tools/run-tests.sh            # 数据/服务层测试（提交前必须过）
```

`./tools/run-tests.sh` 是测试的唯一入口，本地与 CI 跑的是同一条命令
（CI 见 `.github/workflows/tests.yml`，跑 `data` + `platform` 两层）。默认只跑**数据/服务层** ——
这层不需要显示环境，是"不能崩"的部分，也是 CI 会验的部分：

```bash
./tools/run-tests.sh              # data 层（默认，与 CI 一致）
./tools/run-tests.sh --layer platform
./tools/run-tests.sh --all        # 含界面层；需要图形会话
./tools/run-tests.sh --help       # 全部选项
```

- 改了 `platform/`、C++ 或 Go：加 `--layer platform`。
- 改了 QML / 界面：加 `--all`。界面层需要 QML 引擎，面板测试还需要合成器 —— **CI 容器里跑不了**，
  所以它们只在本地生效。
- 另有三条轻量检查，同样必须过：

```bash
git diff --check                          # 空白错误与冲突标记
python3 platform/tests/test_contract.py
python3 tools/check-docs.py
```

**English**

Run the tests locally before committing, and **commit only once they all pass**. If a test fails,
fix it; if you genuinely cannot, do not commit — keep the failing output in `tmp/` instead.

```bash
./tools/run-tests.sh            # data/service layer tests (must pass before committing)
```

`./tools/run-tests.sh` is the single entry point for tests: local development and CI run the exact
same command (CI is `.github/workflows/tests.yml`, running the `data` and `platform` layers). By
default it runs only the **data/service layer** — that layer needs no display, it is the "must not
crash" part, and it is what CI verifies:

```bash
./tools/run-tests.sh              # data layer (default, same as CI)
./tools/run-tests.sh --layer platform
./tools/run-tests.sh --all        # includes the UI layer; needs a graphical session
./tools/run-tests.sh --help       # all options
```

- Platform, C++ or Go changes: add `--layer platform`.
- QML / UI changes: add `--all`. The UI layer needs a QML engine and the panel tests need a
  compositor — **CI containers cannot run them**, so they only take effect locally.
- Three lightweight checks must also pass:

```bash
git diff --check                          # whitespace errors and conflict markers
python3 platform/tests/test_contract.py
python3 tools/check-docs.py
```

---

## 3. 什么不该进提交

**中文**

| 内容 | 去处 |
| --- | --- |
| AI 工具产物：`CLAUDE.md`、`.claude/`、`.agents/`、`.zcode/`、`.reasonix/` | 写进 `.gitignore`，本地保留 |
| 会话工作汇报、修复清单（"本轮修了…"） | `tmp/` |
| 未解决的问题线索：崩溃栈签名、待验证行为、待部署的改动 | `tmp/` |

`tmp/` 是本地工作台（由 `.gitignore` 里的 `/tmp/` 忽略），**不随仓库走**；
它的用途与约定见 `tmp/README.md`。别把只此一份的重要信息放进去。

**English**

| Content | Where it goes |
| --- | --- |
| AI tool artefacts: `CLAUDE.md`, `.claude/`, `.agents/`, `.zcode/`, `.reasonix/` | Add to `.gitignore`, keep locally |
| Session work reports, fix lists ("this round fixed…") | `tmp/` |
| Open problem leads: crash stack signatures, unverified behaviour, undeployed changes | `tmp/` |

`tmp/` is a local workbench (ignored via `/tmp/` in `.gitignore`) and **does not travel with the
repository**; its purpose and conventions are documented in `tmp/README.md`. Never put the only copy
of important information there.

---

## 4. 文档该放哪

**中文**

| 内容 | 位置 |
| --- | --- |
| 模块设计 / 架构说明 | `docs/*Architecture.md` |
| 格式与契约 | `docs/`（如 `ThemePackFormat.md`） |
| 未来功能规划 | `docs/FutureFeatures.md` |
| 长期有效的项目约定 | `PROJECT_CONTEXT.md` |
| 面向用户的使用 / 排查指南 | `README.md`、`docs/nix-*.md` |
| **一次会话的过程记录** | `tmp/`（不提交） |

判断依据一句话：**读它的人是要了解"现在是什么样"→ 进仓库；是要复盘"某次是怎么做的"→ 进 `tmp/`。**

**English**

| Content | Location |
| --- | --- |
| Module design / architecture notes | `docs/*Architecture.md` |
| Formats and contracts | `docs/` (e.g. `ThemePackFormat.md`) |
| Future feature plans | `docs/FutureFeatures.md` |
| Long-lived project conventions | `PROJECT_CONTEXT.md` |
| User-facing usage / troubleshooting guides | `README.md`, `docs/nix-*.md` |
| **Process record of a single session** | `tmp/` (not committed) |

One-line test: if the reader wants to know **what it looks like now** → it belongs in the repository;
if they want to replay **how it was done once** → it belongs in `tmp/`.

---

## 5. 一次提交一件事

**中文**

- 功能改动、文档清理、仓库卫生（`.gitignore`、删文件）分到不同提交。
- 一个 message 需要"另外还…"来兜的时候，多半该拆。
- **删除文件前先查引用** —— 注释和文档里的死链比文件本身更难发现：

```bash
git grep -l '<被删文件的名字>'   # 删之前跑
```

**English**

- Feature changes, documentation cleanup and repository hygiene (`.gitignore`, deletions) go into
  separate commits.
- If a message needs "and also…" to cover everything, it probably should be split.
- **Check references before deleting a file** — dead links in comments and docs are harder to spot
  than the file itself:

```bash
git grep -l '<name of the deleted file>'   # run this before deleting
```

---

## 6. 提交前先查分支

**中文**

仓库经历过多次 PR 合并，本地可能停在**已合并的功能分支**上 —— 它的树与 `origin/main` 完全一致，
于是提交会落到一个没人认领的分支。

```bash
git rev-parse --abbrev-ref HEAD
git diff origin/main HEAD --stat     # 输出为空 = 树等价 ⇒ 分支已作废，先回 main
```

**English**

This repository has been through many PR merges, so your checkout may sit on an **already-merged
feature branch** — its tree is identical to `origin/main`, and your commits land on a branch nobody
claims.

```bash
git rev-parse --abbrev-ref HEAD
git diff origin/main HEAD --stat     # empty output = equivalent tree ⇒ stale branch, return to main first
```

---

## 7. 不要 `git commit -a`

**中文**

`-a` 会把所有已跟踪改动一并塞进提交，直接跨过第 1 条的检查。

**English**

`-a` sweeps every tracked change into the commit and bypasses the check in section 1.
