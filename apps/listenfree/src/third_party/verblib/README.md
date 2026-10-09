# Verblib

独立的 Freeverb 算法混响，作者 Philip Bennefall。版本 0.5（上游修订时间 2022-10-25），取自 miniaudio 固定标签 0.11.23：

https://github.com/mackron/miniaudio/blob/0.11.23/extras/nodes/ma_reverb_node/verblib.h

`verblib.h` 原样引入，选择 MIT No Attribution（MIT-0）许可，全文也保留在头文件末尾与 `licenses/Verblib-MIT-0.txt`。未引入 miniaudio 的设备、解码或播放器代码。

应用仅通过上游配置宏将最高采样率倍数设为 5，并在 `src/media/sound_effects.cpp` 完成参数平滑、干湿混合及 Qmmp 音频线程适配。该实现为稳定的小型独立 C 库；固定版本的数值、采样率与旁路行为由本项目测试覆盖，后续更新手动评估。
