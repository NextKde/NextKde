# Notification tone / 通知提示音

`notification.wav` is Apple's classic Tri-tone notification sound
(`sms-received1.caf`), converted losslessly to PCM WAV for the bundled player.
It retains the original stereo, 44.1 kHz, 16-bit samples and 900 ms duration;
no synthesis, trimming, resampling or normalization is applied.

Source: [macOSsystemsounds archive, pinned revision
f3e8dcd8d2318d099ade479ad1b9778ce4e65cc7](https://github.com/extratone/macOSsystemsounds/blob/f3e8dcd8d2318d099ade479ad1b9778ce4e65cc7/caf/sms-received1.caf).
Source CAF SHA-256: `737b971fc6be6fa1864b32c94a6f703db4f68139ecc5e5b76185fd98c131f337`.
The audio belongs to Apple; the repository's GPL-3.0 license does not relicense
this third-party recording. This provenance record grants no additional rights.

`notification.wav` 使用 Apple 经典三音通知声 Tri-tone（`sms-received1.caf`），
仅无损转换为播放器使用的 PCM WAV，保留原始双声道、44.1 kHz、16 bit 采样及
900 毫秒时长，未合成、裁剪、重采样或归一化。来源及原文件校验值见上文。
音频权利归 Apple；仓库 GPL-3.0 许可不改变此第三方录音的许可，本来源记录不授予额外权利。

Container conversion (run only in a VM/CI):

```sh
ffmpeg -nostdin -i sms-received1.caf -map_metadata -1 -c:a pcm_s16le notification.wav
```

## Playback policy / 播放策略

Settings → Notifications exposes one global `soundEnabled` preference. New profiles
and profiles without a boolean value for this key default to **off**. It is stored
alongside the other notification preferences in `notifications/config.json` and
travels through the existing `notification-settings` IPC snapshot/update endpoint.
An explicit opt-in survives restart; disabling it unloads the audio backend.

Only a new notification arrival may play the bundled tone. Replacements and metadata
updates do not replay it. DND cancels playback, blocked apps and `suppress-sound`
notifications remain silent, and a 600 ms global cooldown coalesces bursts. Startup
notifications are silent for two seconds. No pre-roll, app-specific paths or sound
theme packages are required. Application sound-file/sound-name overrides are not used
by this global-tone policy. QtMultimedia is loaded dynamically only after opt-in;
an unavailable backend must leave notification delivery working.

“设置 → 通知”提供统一的 `soundEnabled` 开关。新装及旧配置中缺少此布尔值时均默认**关闭**。
该值随其他通知偏好保存到 `notifications/config.json`，经既有 `notification-settings` IPC
快照及更新接口读写。显式开启后重启仍保留，关闭时卸载音频后端。

仅新通知到达时可播放内置提示音，替换及元数据更新不重复响铃。勿扰立即停止播放，屏蔽应用及
`suppress-sound` 通知保持静音；全局 600 毫秒冷却合并突发通知，启动前两秒静音。
不使用静音预热、应用专用绝对路径、系统声音主题或应用的 sound-file/sound-name 覆盖。
只有用户开启后才动态加载 QtMultimedia；缺少后端不能影响通知投递。
