# 面向 AI 贡献者的开发与审阅

[English](Development.md)

[文档](README.zh-CN.md) · [贡献规范](../CONTRIBUTING.zh-CN.md)

下列构建、测试、启动、诊断命令**只在专用 VM 或托管 CI 执行**，禁止在维护者本机运行。
本机可以编辑源码及执行 Git 操作。

## 选择正确运行入口

在 VM 的仓库根目录：

```sh
./tools/kosctl install
./tools/kosctl start
./tools/kosctl dev
```

`install` 部署当前源码并启用 unit，`start` 重启已安装服务。KWin 二进制需注销登录或重启，不热重载。
`dev` 使用源码 Shell QML 和已安装平台/数据服务，不重建服务；原生或服务改动后先安装并重启。
`run` 预览源码 UI。Settings 开发用 `./tools/kosctl dev settings`，确认打印的程序、QML、Shell、模块路径。
从桌面菜单打开的 Settings 通常服务于已安装会话。
Quickshell 的 `-c` 与 `-p` 不可混用。手动启动时 `QML_IMPORT_PATH` 与 `QML2_IMPORT_PATH`
都要选择匹配的原生模块；源码 Shell 混用旧服务不能算最终验收。

## 验证门槛

在 VM/CI：

```sh
python3 platform/tests/test_contract.py
python3 tools/ci/check-docs.py
./tools/run-tests.sh                 # 默认只跑数据层
./tools/run-tests.sh --layer platform
./tools/run-tests.sh --layer logic
./tools/run-tests.sh --layer headless
./tools/run-tests.sh --all           # 包含图形 UI，使用真实 VM 会话
```

另用 `git diff --check` 检查空白。CI 用相同 CTest 注册，构建后分组运行数据/平台/逻辑/无界面测试。
`.github/ci-tests.json` 检查必需注册项及完整结果。无界面 UI 可在 CI offscreen 跑，合成器流程仍需 VM。
精确门槛见[工作流](../.github/workflows/tests.yml)。

三套完整 SDK 分别为 KWin 6.6/6.7/6.8 编译链接插件和 Glass，执行离线回归及官方头文件检查。
容器缺少 GL 上下文时 GPU 读回可能跳过，需在 VM 补验并记录。构建兼容不代表真实桌面加载通过。
测试数量记录当次实测值，不复制旧报告数字。

## 可选应用

应用开发及运行测试现由独立仓库负责：
[NextKde/kos-apps](https://github.com/NextKde/kos-apps)（日历含待办和 PIM、计算器、天气）和
[NextKde/ListenFree](https://github.com/NextKde/ListenFree)。
根应用 preset、构建目标及已拆出的应用源码已移除；原应用开关设为 ON 会报错并提示迁移。

`./tools/kosctl install apps` 默认使用 GitHub Release 签名 Flatpak 包；
源码构建须显式 `--backend=source`。`--app APP` 选择单个应用，`--with-listenfree` 显式包含 ListenFree。
`update`、`status`、`check-update`、`uninstall` 使用同一分发入口。
尚无稳定 Release 时明确显示不可用。此路径不启停服务，不修改 MIME/默认应用关联。
用法及所有权边界见[应用指南](../apps/README.zh-CN.md)。

核心 CI 用 `tools/tests/test_app_installer.py` 与 `tools/tests/test_app_release.py`
替代原单仓库应用任务。应用偏好、PIM、日历语言及天气/计算器客户端测试归独立仓库；
核心 Go 数据服务、Settings、Shell、锁屏和平台测试仍是必需门槛。


## 审阅清单

1. 按架构文档确认所有权、协议/配置兼容、有界重试、取消及断连行为。
2. 检查 QML 经服务接入，可移植应用不导入 Quickshell 模块。
3. 检查新增资源、qmldir、安装/打包路径及状态迁移。
4. 在 VM/CI 执行相关自动化；视觉交互用真实 VM Shell，确认 `Configuration Loaded`，操作受影响流程并检查 QML/运行错误。
   只停止自己启动的实例，恢复正常服务。
5. 审阅暂存树中的新增文件、文档链接/译文、许可和证据表述；临时日志截图不提交文档目录。

发布还需[精确提交的 VM 验收](Releasing.zh-CN.md)。
