# KOS 日历

KOS 日历是独立的 Qt Quick 应用，不导入 Quickshell 运行时，也不依赖
`desktop/` 下的文件。

## 当前状态

应用现在可以独立构建和安装。可用的月视图支持本地事件新建、编辑和删除，
以及全天/定时事件、重复规则预设、提醒、iCalendar 导入导出。带版本的 D-Bus
PIM 服务负责 KCalendarCore 持久化和桌面通知，界面不会直接读写数据文件。

## 构建

在仓库根目录执行：

```bash
cmake --preset calendar-dev
cmake --build --preset calendar-dev
```

可执行文件位于 `.build/calendar-dev/apps/calendar/`。

## 第一版边界

- 已包含：月网格、选中日期议程、事件增删改、时区感知的本地存储、全天事件、
  日/周/月/年重复规则、提醒、iCalendar 文件、键盘快捷键和屏幕阅读器标签。
- 暂缓：周/日视图、时区选择界面、搜索、参会人调度、高级重复规则编辑、
  云账户、CalDAV 和 Akonadi 集成。

日历和待办只共享 `Kos.Pim` 契约与服务，不互相导入应用代码。数据归属、兼容
规则和安全限制见 `docs/PimArchitecture.md`。
