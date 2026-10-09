# 歌词格式回归样本

这些样本使用自有测试文本 Hello world / Again，不来自实际歌曲。

- `synthetic.qrc.hex`：LDDC `84631e8cd011fcc3f71ca0ae017e2c9758958ffc` 的独立 Python tripledes 实现生成。明文为两行 QRC：第一行从 1000ms 开始，Hello 占 400ms、world 从 1400ms 开始占 500ms；第二行 Again 从 3000ms 开始占 500ms。zlib 压缩后补零到 8 字节边界，按上游 QQ 变体 DES 加密。
- `synthetic.krc`：相同时间和文本，附带类型 0 罗马音、类型 1 翻译；按旧 LX/LDDC 的 KRC 外层生成。
- `synthetic.ttml`：相同数据，覆盖秒/分秒时间、内联辅助轨、iTunes 头部 text@for 引用。

`PortableTests::externalLyricFormats` 检查解码内容、字起止时间和辅助轨对齐，不依赖外部网络。
