# GradientBlur 组件

方向可调、半径沿方向**连续变化**的高斯模糊 + 跟随同一条斜坡的色调层。背景被模糊、前景保持锐利，模糊量从「起点」的百分比连续过渡到「终点」的百分比。

对应路线图 #3（iOS 26 风格局部渐变模糊）。

## 用法

把要模糊的内容放进 `sourceItem`，把组件盖在它上面：

```qml
Item {
    id: page
    Image { anchors.fill: parent; source: "壁纸.jpg" }
}

GradientBlur {
    anchors.fill: page
    sourceItem: page

    startPoint: Qt.point(0, -0.5)   // 局部坐标：中心 (0,0)，±0.5 = 矩形边
    endPoint: Qt.point(0, 0.25)
    blurStart: 0.0                  // 起点处模糊占 maxRadius 的比例
    blurEnd: 1.0                    // 终点处……
    maxRadius: 46

    band: true                      // 越过终点后淡回清晰（参考图里状态栏下缘）
    featherOut: 0.5

    tintColor: "#000000"            // 色调层：继承同一条百分比剖面
    tintOpacity: 0.16
}
```

组件默认隐藏 `sourceItem` 并由自己绘制整个区域；宿主想在模糊之上再放东西，把内容放在组件的兄弟层级（前景永远锐利）。想保留源自己绘制则设 `hideSource: false`。

## 属性

| 属性 | 类型 / 单位 | 默认 | 说明 |
| --- | --- | --- | --- |
| `sourceItem` | Item | null | 被模糊的内容 |
| `hideSource` | bool | true | 捕获后隐藏 sourceItem |
| `enabled` | bool | true | 关掉即完全不绘制（A/B 对比用） |
| `startPoint` / `endPoint` | point（局部坐标） | (0,-0.5) / (0,0.5) | 0% 端与 100% 端；中心 (0,0)，±0.5 = 矩形边，**可为矩形外** |
| `blurStart` / `blurEnd` | 0–1（占 `maxRadius` 的比例） | 0 / 1 | 两点处的模糊量，例如 0.2 → 0.8 |
| `maxRadius` | px | 46 | 上限 130（= 金字塔最高一级） |
| `feather` | 0–1 | 1.0 | 斜坡缓动：0 线性，1 smoothstep |
| `cornerRadius` | px | 0 | 模糊区圆角（1px 抗锯齿） |
| `band` | bool | false | 越过终点后模糊按 `featherOut` 淡回清晰 |
| `featherOut` | 局部单位 | 0.5 | 0.5 ≈ 半个矩形在该方向的尺寸 |
| `sideFeather` | 局部单位 | 0 | 垂直方向两条边上的淡出距离；**模糊与色调都受它影响** |
| `tintEnabled` | bool | true | 色调层总开关 |
| `tintColor` | color | "#000000" | 不跟随深浅色时用的颜色 |
| `tintOpacity` | 0–1 | 0.0 | 色调不透明度（在终点处达到该值的 × `blurEnd`） |
| `followsAppearance` | bool | false | 跟随深浅色：按 `appearanceIsDark` 取 `tintColorDark` / `tintColorLight` |
| `appearanceIsDark` | bool | true | 宿主绑定自己的主题（KOS 里绑 `AppearanceTokens.isDarkTheme`） |
| `tintColorDark` / `tintColorLight` | color | #000000 / #ffffff | 跟随模式下深/浅色各用哪支 |
| `tintPerTap` | bool | false | true = 色调对每次采样着色（色调自身也被模糊）；false = 压在模糊结果上 |
| `devGuides` | bool | false | 画出起点/终点与连线（**只读指示**，供开发核对；正式使用保持关闭） |

## 语义（实现要点）

- **只有半径在渐变，绝不做"清晰图与模糊图按渐变混合"**：后者中段会出现半透明重影。起点半径默认 0，所以模糊区边缘天然无缝。
- **起点/终点是矩形局部坐标里的两个点**（中心 0,0，±0.5 = 边），渐变方向 = 两点连线；两点之外各自夹紧（起点前取 `blurStart`，终点后取 `blurEnd`）。
- **模糊由预模糊金字塔两级插值得到**：内部 5 级（12/26/48/80/130 px，`MultiEffect`）各渲染一次后只当纹理用，着色器按当前半径取相邻两级插值。离散抽样在锐利边缘上会露出"多重影像"，层级插值不会。
- **色调层直接继承模糊的百分比剖面**（起点 20% → 起点处色调强度也是 20%），它自己的量只有颜色与不透明度。
- **`band` 的远端淡出只作用于模糊**，色调在终点之后保持满值（参考图里状态栏玻璃的色调是铺满整条带的）；`sideFeather` 则两者都管。

## 多个区域

组件实例 = 一个渐变模糊区。需要叠多个（例如状态栏带 + 悬浮胶囊光环）就放多个实例——每个实例各自建一份 5 级金字塔；同一张底图上想省这份开销，可以把金字塔外置成共享参数（当前为简单起见没有做）。

## 移植到合成器

`kwin/glass-effect/src/blur.cpp` 本来就维护着一条降采样/升采样金字塔，渐变数学不用改，只需：

1. 协议侧新增一个请求（如 `set_gradient_blur(enabled, angle, start, end, max_blur)`）把角度、起止点坐标、起止百分比与色调参数传过去；
2. 片元侧把"取相邻两级"从本地的 5 级换成它自己的金字塔；
3. QML 侧组件改为继承 `KosRoundedBlurRegion`（形状/圆角/scrim/per-shape blur 的既有通道全继承），色调层仍由 QML 画（它要读主题色）。

参数语义、坐标归一化方式与 `gradient_blur.frag` 完全一致，可以逐项对照。

## 调参实验室（临时工具，不在本目录）

交互式调参（画矩形、拖起点/终点手柄、逐参数实时改、A/B 对比、模型值↔像素读数）在开发树外的 `/home/purn/pr2/lab/gradient-blur-lab.qml` 运行：

```sh
qml6 /home/purn/pr2/lab/gradient-blur-lab.qml            # 内置测试图
qml6 /home/purn/pr2/lab/gradient-blur-lab.qml 图片.jpg   # 换底图
```

它自带一份本目录着色器的副本，只是可视化调参用，不参与组件调用。

## 重新烘焙着色器

改过 `gradient_blur.frag` 后必须跑一次：

```sh
./compile.sh        # 等价于 qsb --qt6 -o gradient_blur.frag.qsb gradient_blur.frag
```

`--qt6` 不能省：它才会同时产出 Qt 内置顶点着色器能链接的那些变体（细节见 `shell/desktop/shaders/compile.sh` 的注释）。
