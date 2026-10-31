# 提醒事项兼容入口

**[English](README.md) | [中文](README.zh-CN.md)**

提醒事项已经合入 KOS 日历。日历窗口左侧的“日历／提醒事项”切换器可切换两个工作区；侧栏收起后，切换器移到工具栏，也可按 `Ctrl+Tab` 切换。

`kos-todo` 仅为旧快捷方式、固定图标和脚本提供兼容转发，直接替换自身进程为 `kos-calendar --view reminders`，没有独立窗口、QML 模块或数据存储。旧 desktop 文件设为 `NoDisplay=true`，应用菜单只显示日历。原 QML 源码保留作迁移参考，不参与构建和安装。

## 数据与功能

已有清单、提醒事项、日期、完成状态、优先级、重复规则、通知及备注继续使用原 PIM 服务，不复制、不迁移数据文件。所有任务在日历的提醒事项工作区中管理；有日期的任务也显示在日历视图。

提醒事项工作区支持全部、今天、已安排、已完成、清单筛选及搜索。新建、详情、编辑共用日历 Popover；清单可添加、改名和移除，移除后任务移到收件箱。

## 构建兼容入口

```bash
cmake --preset todo-dev
cmake --build --preset todo-dev
```

`KOS_BUILD_TODO=ON` 同时构建日历。`kos-todo --view today|planned|completed|inbox|calendar` 和 `--item ID` 保持兼容。`calendar` 在旧命令中表示关联日程的任务筛选。

子任务编辑、拖拽排序、云同步不在本轮范围内。详见 [日历文档](../calendar/README.zh-CN.md)。
