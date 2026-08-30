# KOS 日历

KOS 日历是独立的 Qt Quick 应用，不导入 Quickshell 运行时，也不依赖
`desktop/` 下的文件。

## 当前状态

第一阶段提供可独立构建、安装的应用、KOS 公共视觉底座和支持键盘/辅助功能
的月视图框架。事件持久化、重复规则、提醒和 iCalendar 导入导出将由带版本的
本地 PIM 服务提供。

## 构建

在仓库根目录执行：

```bash
cmake --preset calendar-dev
cmake --build --preset calendar-dev
```

可执行文件位于 `.build/calendar-dev/apps/calendar/`。

## 计划范围

- 月、周、日和议程视图。
- 本地事件创建与编辑，包括全天事件。
- 时区、重复规则、提醒和搜索。
- 通过 KCalendarCore 导入、导出 iCalendar。
- 键盘导航和屏幕阅读器标签。

首版暂不包含云账户、CalDAV 和 Akonadi 集成。
