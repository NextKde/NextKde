# 协议规则:kos_surface_shape_v1 v9

状态:**v9 已于 2026-11-18 落地**。唯一新增请求是 shape 上的
`set_pointer_effects(flags)`(逐 shape 指针效果掩码)。

原 v9 提议里的噪声 / 底色来源 / 壁纸样本**没有**写入
[协议 XML](../../../../shell/native/surface-shape/kos-surface-shape-v1.xml);
协议只允许在末尾追加,已占用的 v9 不能再加,该提议整体推迟为 **v10 提案**,
见附录 A。

## 1. 不变量

1. **只追加**:新 request 必须写在 interface 末尾(`destroy` 之后)。任何插入都会
   移动后续 opcode,使旧客户端的 destroy 指向错误请求。仓库已有此约束,继续遵守。
2. **版本化**:v9 的 request 带 `since="9"`;两个 interface 的 `version` 都是 9。
   **提升版本时,服务端 `bindManager` 的 version clamp 必须一起改**——只改
   `wl_global_create` 而让资源停在旧版本,会让客户端的 since=9 请求撞上协议错误,
   整条连接被断开(见 pitfalls C7)。
3. **能力门控**:客户端在 `wl_registry` 协商后检查 shape 代理版本 ≥ 9,未达标不得
   发送 v9 请求。v9 服务端必须接受全部旧请求。
4. **事务语义**:v9 setter 写入 v8 的 pending 状态,由 `commit` 封印,随下一次
   `wl_surface.commit` 生效。v1–v7 资源保持立即生效的历史行为。
5. **坐标**:几何、半径、sigma 仍用 surface-local 逻辑单位,与指针效果无关。
6. **无启发式**:不得根据 layer-shell namespace、窗口类名或应用身份推断材质或效果。

## 2. 版本摘要

| 版本 | 能力 |
| --- | --- |
| v1 | 几何、圆角、启用 |
| v2 | `set_role`(现为 no-op,保留 opcode) |
| v3 | 可读性 scrim |
| v4 | per-shape blur level |
| v5 | 固定捕获域 |
| v6 | 完整效果透明度 |
| v7 | 合成器驱动 reveal |
| v8 | 事务提交、显式 material/effect、连续 blur sigma、tint |
| **v9** | **per-shape 指针效果掩码(hover 光 / 透镜视差 / 点击光)** |

## 3. v9:`set_pointer_effects(flags)`

请求发在 shape 资源上,一个 `uint` 掩码:

| bit | 效果 | 说明 |
| --- | --- | --- |
| 0 | hover 光 | 指针悬停时的高光斑;强度/半径读全局 KCM |
| 1 | 透镜视差 | 边缘折射带随指针的位移;只作用于边缘,不是整块背景 |
| 2 | 点击光 | 按下左键时从点击点扩散的脉冲 |

- bit 3 以上忽略(服务端 `flags & 0x7`),不报错。
- 效果本身只对 `effect=liquid/soft`(effect=0)渲染;Frosted 形状收到掩码也不显示。
- 掩码写 pending,与其他 v8 setter 一起随 `commit` 生效。
- 更多效果的含义、默认值与指针采样来源见 pitfalls 第 23 条(B16)。

### 3.1 默认与兼容

- **pre-v9 客户端从不发送**:`GlassShape` 默认 `pointerEffects = 0x7`,
  即历史行为不变(三类效果全开),服务端不做额外推断。
- **v9 客户端**:默认发送 0x7;shell 侧由
  `AppearanceConfigService.pointerEffectsFor(id)` 决定哪些面板开启,
  不在 allow list 的面板显式发送 0,合成器不再为其推进 hover/点击动画。
- 客户端桥接的属性默认 0x7,`NOTIFY` 后参与 v8 pending/commit;越界 clamp 到 0..7。

### 3.2 XML 追加内容

在 shape interface 的最后一个 request 之后追加(不能插在 `destroy` 前):

```xml
<request name="set_pointer_effects" since="9">
  <description summary="per-shape pointer effect mask">
    Bit 0 enables the hover light, bit 1 the lens parallax and bit 2 the
    click ripple for this shape. Bits above 2 are ignored. Omitted by
    pre-v9 clients, in which case every effect stays enabled.
  </description>
  <arg name="flags" type="uint"/>
</request>
```

## 4. 服务端校验

- `flags & 0x7`,其余位丢弃;不因未知位断开连接。
- 只影响该 shape 的 onscreen uniform 与重绘计划,不改变捕获域、模糊链缓存键或
  材质参数;掩码变化本身不触发重绘,下一次合成自然生效。
- 指针命中测试只考虑 `pointerEffects & 0x3` 非零的 shape;全 0 的 shape 不参与
  指针遍历。

## 5. 兼容矩阵

| 客户端 | 服务端 | 行为 |
| --- | --- | --- |
| v8 | v9 | 不发送 v9 请求;shape 保持历史默认(三类效果全开) |
| v9 | v8 | 客户端检查版本后不发送;行为由旧服务端决定,无逐面板控制 |
| v9 | v9 | 全部能力 |
| v9 面板 mask=0 | v9 | 该面板无 hover/视差/点击,也不为指针移动重绘 |

客户端桥接要求:

- 新增 `Q_PROPERTY` 必须带 `NOTIFY`;写入参与 v8 pending/commit。
- 发送前检查 `wl_proxy_get_version(shape) >= 9`;版本未达标时只保留本地值。
- QML 侧掩码来源只允许配置(allow list),不按窗口身份推断。

## 6. 静态核对清单(构建步骤,不是测试)

- 新请求只出现在 interface 末尾;`destroy` opcode 未移动。
- 两个 interface 的 `version` 均为 9;新 request 带 `since="9"`。
- 服务端 `wl_global_create` 与 `bindManager` 的版本上限一致。
- 客户端发送点有 `wl_proxy_get_version` 门控。
- `uniformLocation` 名称与 shader 声明一致。
- 三套 KWin SDK 构建通过;shader 离线编译通过。
- `git diff --check` 无空白错误;文档相对链接存在。

## 7. 暂不进入 v9 的能力

以下保留为后续版本,不占用 v9 opcode(噪声 / 底色来源 / 壁纸样本已整体移至附录 A):

- `set_elevation(level)`(M3 elevation 语义);
- 动画提示(当前由插件根据几何变化自行推断);
- 逐面板强度系数(hover/点击/视差的百分比);当前只有逐面板开关。

新增请求仍必须追加在 interface 末尾。

---

## 附录 A:v10 提案(未落地)

以下内容来自 v9 的原始提议,因 v9 已被指针掩码占用,整体推迟到 v10。
落地前不得写入 XML;写入时两个 interface 的 `version` 提升到 10,所有新 request
带 `since="10"`,并同步 `bindManager` 的 clamp。

### A.1 新增状态

#### A.1.1 `set_noise(strength)`

- 强度 0–100,与 kwinrc `NoiseStrength` 同刻度;0 关闭。
- 作用于该 shape 的最终材质,不改变模糊、捕获或 tint。
- 与 `set_material_opacity` 一起淡出;静态背景上不得产生逐帧闪烁。
- 未发送时使用窗口/全局默认值,保持旧客户端行为。

#### A.1.2 `set_backdrop_source(source)`

- `live`(0):采样 surface 下方的合成结果,即现有行为。
- `wallpaper`(1):采样该输出由 `set_wallpaper` 提供的静态样本。
- `wallpaper` 只与 frosted 光学组合;液态光学在该来源下不参与计算,避免对预模糊
  壁纸做 Snell 折射。
- 同一 shape 的 blur sigma、tint、scrim、噪声、透明度仍生效。
- **closed fallback**:该输出无样本时复用上一次样本;从未有过样本时只渲染
  tint/scrim,不得退回 live 背景。Mica 的语义是"永远不显示后方应用内容"。
- 壁纸来源不消费背景损伤;缓存只依赖输出、壁纸 serial、shape 几何与材质。

#### A.1.3 `set_wallpaper(output, buffer, width, height, format, serial)`

由 manager 接收,按输出保存一份样本。

- 样本要求:正向、不透明、sRGB、显示参考;建议宽度 512–1024,最大 4096×4096。
- `format` 使用本协议自己的枚举,映射到 `wl_shm`:
  - `xrgb8888 = 0` → `WL_SHM_FORMAT_XRGB8888`
  - `argb8888 = 1` → `WL_SHM_FORMAT_ARGB8888`,alpha 按 255 处理
- 只接受 `wl_shm` buffer;dma-buf 拒绝(closed fallback)。
- 合成器在请求分发时**同步复制**像素;客户端在请求被处理后可释放 buffer。
- `serial` 每输出单调递增;小于等于当前值的请求忽略,防止乱序覆盖。
- 每输出仅保留一份;输出移除时释放。
- 多个客户端写同一输出时**最后成功者胜出**;协议不引入提供者身份。

采样规则:

- 样本按 cover 方式映射到输出逻辑矩形:等比放大到覆盖整个输出,居中裁剪。
- shape 在输出中的位置决定采样位置;窗口移动时壁纸图案相对屏幕不动。
- 样本更新只失效 wallpaper 来源的材质缓存,不影响 live 来源的 shape。

### A.2 XML 追加内容(v10)

manager,在 `commit` 之后追加:

```xml
<enum name="wallpaper_format" since="10">
  <entry name="xrgb8888" value="0"/>
  <entry name="argb8888" value="1"/>
</enum>
<request name="set_wallpaper" since="10">
  <description summary="per-output still wallpaper sample for Mica">
    Supplies a low-resolution, upright, display-referred image for one output.
    The compositor copies the pixels while dispatching this request; the client
    may destroy the buffer afterwards. At most 4096x4096. One sample is kept per
    output; a lower serial than the stored one is ignored. The sample is used
    only by shapes that selected the wallpaper backdrop source.
  </description>
  <arg name="output" type="object" interface="wl_output"/>
  <arg name="buffer" type="object" interface="wl_buffer"/>
  <arg name="width" type="uint"/>
  <arg name="height" type="uint"/>
  <arg name="format" type="uint" enum="wallpaper_format"/>
  <arg name="serial" type="uint"/>
</request>
```

shape,在末尾追加:

```xml
<enum name="backdrop_source" since="10">
  <entry name="live" value="0"/>
  <entry name="wallpaper" value="1"/>
</enum>
<request name="set_noise" since="10">
  <description summary="per-shape noise strength">
    Strength on the same 0..100 scale as the kwinrc NoiseStrength setting.
    Zero disables the pass. Values above 100 are clamped. Noise is applied
    after tint and before scrim, and fades with set_material_opacity.
  </description>
  <arg name="strength" type="uint"/>
</request>
<request name="set_backdrop_source" since="10">
  <description summary="select the pixels the finish samples">
    live samples the composited backdrop below the surface. wallpaper samples
    the per-output still image supplied through the manager. A wallpaper source
    is evaluated with frosted optics; liquid optics are not evaluated. With no
    sample for the output the previous sample is reused; with no sample at all
    the shape renders as tint without a backdrop and must not fall back to the
    live backdrop. Staged state is applied by commit.
  </description>
  <arg name="source" type="uint" enum="backdrop_source"/>
</request>
```

### A.3 渲染语义与顺序

材质的固定顺序(从底到顶):

1. 选择来源:`live` → 捕获 + 模糊链;`wallpaper` → 输出样本 + 可选 sigma;
2. tint(固定色/命名色);
3. noise(强度、形状裁剪、随 opacity 淡出);
4. scrim(自适应或固定);
5. 饱和度/对比度/亮度(沿用现有全局设置);
6. `material_opacity` 整体淡出。

约束:

- `set_blur` / `set_blur_sigma` 对两种来源都生效;Mica 通常使用 0–8。
- `set_material(effect=frosted)` + `source=live` + `noise>0` = Acrylic。
- `set_material(effect=frosted)` + `source=live` + `noise=0` = Material Frosted。
- `set_material(effect=frosted)` + `source=wallpaper` = Mica;更强 tint 或独立
  参数即 Mica Alt,不需要新请求。
- `set_material(effect=liquid)` + `source=wallpaper` 视为无效组合:液态光学
  不参与,其余按 frosted 执行;不报错,不改变来源。
- scrim 的亮度采样必须来自当前来源;Mica 用壁纸样本,不得读实时背景。
- reveal、captureGeometry、blur level 的既有语义不变;Mica 忽略
  `captureGeometry` 的捕获部分,但仍用于可见轮廓对齐。

### A.4 服务端校验与资源上限(v10 提案)

- `output` 必须是本合成器的有效输出;否则忽略请求。
- `width/height` 为 0 或超过 4096 拒绝;stride 必须 ≥ width×4。
- `format` 只接受 0/1;其他值拒绝。
- buffer 只接受 `wl_shm`;复制失败时保留旧样本。
- 单输出一份,总内存按输出数线性;输出销毁即释放。
- 不读取客户端提供的路径、不打开文件、不接受 dma-buf。
