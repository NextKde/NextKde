# KOS 天气

**[English](README.md) | [中文](README.zh-CN.md)**

KOS 天气是独立的 Qt Quick 预报应用。它与 Quickshell 天气组件读取同一份带
版本的服务快照，网络请求和缓存状态不归任何一个界面单独所有。

## 当前状态

应用已经接入第 1 版共享天气服务，可搜索并保存地点、切换公制/英制、手动
刷新，并展示当前天气、逐小时预报和七日预报。离线时继续显示最后一份完整
预报，过期数据会明确标记为缓存。

`shell-data-service` 是唯一负责联网和持久化的进程。Qt 客户端读取它生成的
原子快照，并通过本地 Unix Socket 发送命令、接收变更通知；Quickshell 天气
组件读取同一份协议。

## 构建

```bash
cmake --preset weather-dev
cmake --build --preset weather-dev
```

应用位于 `.build/weather-dev/apps/weather/`。同一 preset 会同时构建 Go 数据
服务，因此除 Qt 6 外还需要 Go 工具链。

## 已包含范围

- 本地化地点搜索和多个收藏地点。
- 当前、逐小时和七日预报。
- 公制/英制单位和手动刷新。
- 包含生成时间、过期时间的原子离线缓存。
- 通过 `shell-data-service` 与桌面天气组件共享状态。

第 1 版不包含雷达、灾害推送、自动定位和天气服务商账号同步。

## 运行服务

CMake 会把 `kos-shell-data-service` 安装在应用旁边。若桌面数据服务已经运行，
KOS 天气会直接复用；否则应用会按需启动已安装的服务。服务或网络暂时不可用
时，先前缓存的预报仍会继续显示。

仓库原有的 `shell-data-service.service` 仍可用于登录时启动整个 Shell 的共享
服务，但独立安装天气应用不再强制依赖它。
