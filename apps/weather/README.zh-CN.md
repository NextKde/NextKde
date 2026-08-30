# KOS 天气

KOS 天气是独立的 Qt Quick 预报应用。它与 Quickshell 天气组件读取同一份带
版本的服务快照，网络请求和缓存状态不归任何一个界面单独所有。

## 当前状态

第一阶段提供可独立构建的应用以及完整的加载态、空状态布局。在天气模块从
现有单体数据服务中拆出之前，联网控件保持禁用。

## 构建

```bash
cmake --preset weather-dev
cmake --build --preset weather-dev
```

可执行文件位于 `.build/weather-dev/apps/weather/`。

## 计划范围

- 本地化地点搜索和多个收藏地点。
- 当前、逐小时和七日预报。
- 公制/英制单位和手动刷新。
- 包含生成时间、过期时间的原子离线缓存。
- 通过 `shell-data-service` 与桌面天气组件共享状态。

首版暂不包含雷达、灾害推送和自动定位。
