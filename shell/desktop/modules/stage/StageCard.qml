import QtQuick
import Quickshell.Widgets
import org.kde.pipewire
// ⚠️ ScreencastingRequest 在本模块（勿按直觉挪去 pipewire——删过一次
// 就 crash-loop："is not a type"）
import org.kde.taskmanager
import "../../../shared/qml/i18n"
import qs.desktop.modules.dock
import qs.desktop.modules.common
import "stage-geometry.mjs" as StageGeo

// StageCard — 台前侧栏的单张应用卡片（同应用窗口堆叠在同一张卡上）。
// 纯展示组件：编排（快照/预测卡位/最小化派发）都在 StageSidebarWindow，
// 这里只发信号。ListModel 的角色名与 required property 一一对应自动绑定。
// 卡面玻璃质感（圆角/背板/受光/描边/辉光/纵深）全部走 StageConfigService，
// 设置应用「台前侧栏 → 玻璃质感」实时可调。
//
// 倾斜 = 真透视（shaders/stage_tilt.frag 针孔重投影）：所有卡片共享同一
// 台相机（竖轴 = 内容列中心线、地平线 = 滚动视口垂直中心，由 slot 下传
// perspectiveYOff），近缘放大、远缘缩小，整列读作一面同向微转的 3D 墙、
// 灭点唯一——QML Rotation 是仿射变换给不了这个（近远缘同高、各卡各自
// 为政的"假透视"）。纯函数孪生 tiltProject/tiltUnproject 在
// stage-geometry.mjs（node 单测）。
//
// 动效状态机：
//   入场 = 从窗口方向滑进侧栏（shown 翻转驱动一次）
//   悬停 = 放大 + 提亮 + 辉光 + 关闭钮浮现（放大是指向卡片的即时反馈）
//   点击 = engageClicked() → 窗口编排（入队 + 同拍收编）→ engaging 原地
//          淡出并保持倾斜，把姿态交棒给窗口动画（派发在窗口侧队列，
//          engageDelay 到点统一处理——见 StageSidebarWindow._engageQueue）
Item {
    id: card

    required property string appKey
    // 合并动画窗内被吞卡的组键（非动画窗为 ""）：交棒淡出期间 rep 翻转
    // 不得复位 engaging（打断淡出＝闪回一帧）
    property string mergeAnimFromKey: ""
    required property string targetId // 代表窗口（缩略图与激活目标）
    required property int pid
    required property string appName
    required property string title
    required property string iconSource
    required property int count // 组内窗口数（>1 显示角标）
    required property string idsJson // 组内全部窗口 id 的 JSON 数组
    // 每窗图标（与 idsJson 平行；自由合并组内各应用图标不同）
    required property string iconsJson
    required property string iconIdsJson
    // 逐窗行（合并卡左下窗口列：图标+标题竖排，参考 ref/c2.png）
    required property string rowsJson
    required property bool merged // 自由合并卡（右键拆分）
    // 拖拽合并手势的落点高亮（窗口侧按 _dropMergeKey 绑定）
    property bool dropHovered: false
    // 驻留预示（窗口侧按 _mergeCandidate 绑定）：指针压在候选卡上、
    // 驻留计时中——淡蓝描边 = "keep holding"（武装前的可见反馈；纯等待
    // 无提示是"合并十分困难"体感的另一半，时长走 mergeDwellMs）
    property bool dwellHint: false
    // 中心合并预示（被拖卡自身）：拖进屏幕中心区且前台程序可并组 =
    // 松手即与正在运行的程序合组
    property bool selfMergeHint: false

    // 共享透视：卡中心相对滚动视口中心（= 共享地平线）的 y 偏移，slot 下传
    property real perspectiveYOff: 0

    // 拖拽中（窗口侧 dragKey 绑定）：被抓起的卡强制摆平——倾斜姿态在
    // 拖拽里只会碍事（对位/读位都难，实测"卡片是斜着的"）；松手回姿态
    property bool dragging: false

    // 窗口侧聚焦键（hoveredKey 下传）：活体流判定与布局同源
    property string focusKey: ""

    // 点击（请求编排：入队，窗口侧 engageDelay 到点派发）
    signal engageClicked()
    // 拖拽排序：按下后位移超过阈值（12px）才算拖拽；发生过拖拽的这次
    // 按压不再触发 engageClicked（点击/拖拽二选一）。传**场景坐标**——
    // 卡内坐标会随卡片移动而漂移（指针没动、卡动了，卡内 y 就变了），
    // 用它算位移会互相抵消＝"拖过一张卡就拖不动"（实测踩过）。
    // x 也要传：合并候选检测跟**指针**走（用户瞄的是指针，不是被拖卡
    // 中心——抓卡偏一点中心就落在别的卡上，驻留等错目标），"拖向屏幕
    // 中心与前台程序合并"也靠它判定离区。
    signal dragStarted(real sceneX, real sceneY)
    signal dragMoved(real sceneX, real sceneY)
    signal dragReleased()
    // 悬停进出（窗口侧据此聚焦布局：悬停卡原位放大置顶、其余原位退避）
    signal hovered(bool over)
    // 关闭按钮：关闭组内全部窗口
    signal closeAllRequested()
    // 点击左下角的窗口小图标：直达该扇窗（macOS Stage Manager 同语义，
    // 走 engage 管线但焦点钉在被点窗口）
    signal iconActivated(string windowId)
    // 右键合并卡 = 拆散回各自的应用卡
    signal ungroupRequested()

    // 组内窗口 id 与逐窗图标（合并组内各应用图标不同，逐窗取）
    readonly property var windowIds: {
        try {
            const arr = JSON.parse(idsJson || "[]")
            return Array.isArray(arr) ? arr : []
        } catch (e) {
            return []
        }
    }
    readonly property var windowIcons: {
        try {
            const arr = JSON.parse(iconsJson || "[]")
            return Array.isArray(arr) ? arr : []
        } catch (e) {
            return []
        }
    }
    // 与 windowIcons 索引对齐的窗口 id（decorateGroups 去重时记的首现窗）
    readonly property var windowIconIds: {
        try {
            const arr = JSON.parse(iconIdsJson || "[]")
            return Array.isArray(arr) ? arr : []
        } catch (e) {
            return []
        }
    }
    // 图标排消费的对（icon, id）：图标按源去重——同应用多窗只留一枚
    //（点击直达该应用首个窗口），窗口总数由标题 ×N 表达。id 取自与
    // icons 同源去重的 iconIds——旧实现拿全量 windowIds 按位 zip，重复
    // 图标排在异图标之前时会错位激活同应用兄弟窗（v87 审查）
    readonly property var iconPairs: {
        const icons = windowIcons
        const ids = windowIconIds
        const out = []
        for (let i = 0; i < icons.length && i < ids.length; i++)
            out.push({ icon: icons[i], id: ids[i] })
        return out
    }
    // 逐窗行（合并卡左下窗口列）：[{icon, title, id}]，代表窗在首位。
    // 与 iconPairs 的区别——这里**不按应用去重**：同应用两扇窗是两行
    //（各带自己的标题），点击直达对应窗口。
    readonly property var windowRows: {
        try {
            const arr = JSON.parse(rowsJson || "[]")
            return Array.isArray(arr) ? arr : []
        } catch (e) {
            return []
        }
    }
    // 图标排并列上限（stage-config maxIconSlots，设置页可调）；实际
    // 可见数还按卡宽动态封顶（见 iconRow.visibleCount），超出进 "+N"
    readonly property int maxIconSlots: StageConfigService.maxIconSlots

    // 右侧常驻（stage-config side）：内容整体镜像——入场方向/扇叠方向/
    // 图标排/深度渐变都翻到对侧
    readonly property bool rightSide: StageConfigService.side === "right"

    width: parent ? parent.width
                  : StageGeo.PANEL_WIDTH - StageGeo.CARD_WIDTH_INSET
    // 卡高由槽位按窗口宽高比决定（StageSidebarWindow._cardHeightFor）；
    // 无槽位父项（独立预览/调试）时回落配置卡高
    height: parent ? parent.height : StageConfigService.cardHeight

    // ── 动效状态机：点击=原地淡出并保持倾斜（窗口从倾斜姿态旋转展开接管）──
    // enterInstant = 行以"收集落卡"追加（窗口正飞进该卡位）：几何出生即
    // 终值（无侧滑/无缩放入场），只做**原地淡入**且时长对齐收编飞行
    //（animDuration）——卡与窗同拍开始、同拍落成。旧版 280ms 侧滑因快照
    // 延迟"迟一步"被砍成即时蹦出，又压着飞行中段突兀（2026-10-03 两轮
    // 回归后的折中：淡入时长=飞行时长，窗口飞到时卡片恰好凝实）
    property bool enterInstant: false
    property bool shown: false
    property bool engaging: false
    // 同组换代表（点同应用的另一扇窗）时模型行不销毁，engaging 不会随
    // delegate 重建归零——必须在此显式交还卡片姿态，否则卡片永远停在
    // 透明态，看起来就是"卡片消失了"
    // 同组代表窗翻转时交还姿态（防"换代表卡复活"），但**排除合并动画窗**
    // ——被吞卡的 engaging 是 _endCardDrag 交棒淡出的核心，动画窗内 rep
    // 翻转（最小化顺序变化换 pickRepresentative）会把淡出中途打断＝卡
    // 闪回一帧再被模型合并掉
    onTargetIdChanged: if (mergeAnimFromKey !== appKey)
        engaging = false
    // 合成器活体卡让位标记：特效回执（stage-live.json.status）确认正在
    // 直绘这张卡 → 缩略图 Image 透明让出卡面（opacity 而非 visible——
    // plane 不可见子树吞 visible 改动，opacity 链实测有效）
    property bool livePainted: false
    // 特效接管卡面视觉（方案"卡进特效"）：本卡 QML 视觉（plane 透视层）
    // 整体让位，只留根层输入热区（MouseArea 仍收点击/拖拽/悬停——特效
    // 画不出输入）；回执失效自动恢复 QML 自绘（快照时代观感兜底）
    property bool effectOwnedChrome: false
    // The owner disables preview resources for hidden or offscreen cards.
    property bool previewActive: true
    // 无头排障读数:卡面 layer 是否有效(=previewActive 且未被特效接管)。
    // "缩略图空白"悬案的 C 假设(layer 未生效)经 debugGeom 直读判别
    readonly property bool faceLayerActive: previewActive && !effectOwnedChrome
    // 关闭钮悬停态（根层热区 containsMouse；铭牌在特效侧据此画红钮）
    readonly property bool closeHot: closeHit.containsMouse

    // ── 卡面"空脸先渲"自愈（2026-10-11 实测）──
    // Qt 的 QQuickItemLayer 在这条路径上会把卡面纹理做死在"空"的状态：卡面
    // 在**没有缩略图**的时候被曝光渲染过一次，之后缩略图到位（Image Ready、
    // paintedWidth 正常、数据链全绿）层纹理也不会再刷新——卡面整块空白，
    // 直到 delegate 重建（点卡换主/重开侧栏/收编新建）才恢复。隔离会话确定性
    // 复现：卡列展开时重启壳（截图 + cardItem.grabToImage 双存证）。
    // 自愈：无图期间被曝光过 → 缩略图首次就绪时请宿主把这张卡重建一次
    // （真实 sync 路径移除+重建，层纹理首渲即带内容，实测恢复）。收起状态
    // 下卡面被剔除渲染、不会中招，故不重建（避免无谓的 delegate churn）。
    signal faceRecreateRequested()
    // 宿主注入：卡面此刻会不会被渲染（抽屉展开且侧栏开着）
    property bool faceExposed: false
    property bool _faceEmptyExposed: false
    function _noteFaceExposure() {
        // 判据："曝光时图还没就绪"（不是"URL 为空"）。壳重启时 URL 已在
        // 表里但 PNG 还没写好，层纹理同样会烘死在空态（2026-10-18 实测：
        // 6 张里 4 张空白，最终 thumbStatus=Ready 却永不刷新）。
        if (faceExposed && preview.status !== Image.Ready)
            _faceEmptyExposed = true
    }
    onFaceExposedChanged: _noteFaceExposure()
    // 无头读数（stage-sidebar debugGeom 消费）：当前预览图 URL 与 Image
    // 状态（-1 = 无 URL / 0 Null / 1 Ready / 2 Loading / 3 Error）——
    // "卡没图"类排障一眼区分"没拍"还是"拍了读不出来"
    readonly property string thumbPreviewUrl: thumbCard.thumbUrl
    readonly property int thumbPreviewStatus: thumbCard.thumbUrl === ""
        ? -1 : preview.status
    // 排障补全(2026-10-17):Image 实际 source 与可见性 — thumbStatus=0
    // 而 thumbUrl 非空的矛盾靠这两个分量分辨"source 空"vs"加载未启动"
    // ⚠️ thumbPreviewVisible 读的是**有效可见性**（Qt 语义 = 自身 && 祖先），
    // thumbCard 是 visible:false 的离屏烘焙层，故这里恒为 false——它不是
    // "图没画"的判据（2026-10-18 曾据此误判一整轮）
    readonly property string thumbPreviewSource: preview.source.toString()
    readonly property bool thumbPreviewVisible: preview.visible
    // 排障补全(2026-10-18):空脸自愈的两个状态位（曝光时是否已记"空脸"）
    readonly property bool dbgFaceExposed: faceExposed
    readonly property bool dbgEmptyExposed: _faceEmptyExposed
    // 活体卡发布参数（StageSidebarWindow.publishLiveCards 消费）：
    // 卡面矩形 + 透视参数。**发布动画中的实时值**（card.scale / tiltCur
    // 都带 Behavior，悬停/入场期间逐帧变化）——旧版发终态值，特效按自己的
    // 曲线追，而卡面走 OutBack 过冲曲线，两者中途必然脱节（"悬停时内容和
    // 卡片不协调"）。配合 16ms 发布节拍 + 特效 80ms 短缓动，内容贴着卡面
    // 动画走（滞后 ≤2 帧）。engaging 卡不发布。
    signal livePoseDirty()
    onScaleChanged: livePoseDirty()
    onTiltCurChanged: livePoseDirty()
    onXChanged: livePoseDirty()
    // y 也必须挂：滚动（layoutCards 的 scroll 偏移走 slot.y）只改 y——
    // 漏挂 = 滚动后卡已滚走、内容还停在旧姿态（"内容不在卡片里"帮凶）
    onYChanged: livePoseDirty()
    // 切侧也必须挂：方向符号在下游 angleRad/liveCardPose 里取
    //（tiltCur 是不带符号的幅值），切侧时 y/x/scale/tiltCur 全不变
    //= 没有任何信号触发发布，特效按旧角度+旧 rightSide 画到下一次
    // hover 才纠正（"切侧后倾斜角不对、划一下鼠标就好"的根因）
    onRightSideChanged: livePoseDirty()
    // engaging 翻转也必须挂：deskReveal 放出/撤销看门狗/拖拽中心等路径
    // 只置 slot.cardItem.engaging 就去激活窗口，无姿态变化＝零发布触发
    //——engaging=true 永远进不了载荷，特效按满 alpha 等 600ms 缺席迟滞
    //再 150ms 淡出＝放大后旧卡位残影一闪（v80 交棒淡出在这些路径从未
    // 生效的真因；窗口还原销毁委托比下一次发布更快，标记必须同拍出帧）
    onEngagingChanged: livePoseDirty()
    // closeHover/mergeGlow 同族（v87 审查）：scroll 模式下指针从卡面移到
    // 关闭钮，isHovered 合成值不变、姿态全不动＝零触发，特效红钮要等
    // 15s 心跳；mergeGlow 1.8s 到期翻转时指针早已离开同理。载荷字段
    // 的每个输入都必须有发布触发
    onCloseHotChanged: livePoseDirty()
    onMergeGlowChanged: livePoseDirty()
    // dwellHint 同族补漏（合并驻留的本质是"指针停住"——停住后姿态全
    // 静止＝零发布触发，特效看不到武装态；驻留到点 layoutCards 才补发）
    onDwellHintChanged: livePoseDirty()
    // v2：发布**静止姿态** + 卡面元数据。悬停放大/压平动画不再由 QML
    // 驱动（特效 cursorPos 自驱，同管线像素级同步）——这里除放
    // card.scale（TopLeft 变换原点下原点不动，仅 w/h 回到静止尺寸），
    // 倾角也发静止值（hoverTilt 单独给终态）。engaging 卡照发（特效淡出）。
    function liveCardPose(): var {
        const sc = parent && parent.slotScale !== undefined
            ? parent.slotScale : 1.0
        // ⚠️ mapToItem 实测（plate 是 plane 的子项，坐标手工加会偏 (74,115)）
        const pp = plate.mapToItem(null, 0, 0)
        // 静止/悬停双旋钮解耦（与 tiltCur 同源）：静止姿态 = 静置倾斜角
        //（两模式统一，adaptive 完整显示也有静置姿态）；悬停终态 =
        // 悬停倾斜角（特效 cursorPos 自驱悬停引擎的终点）
        const restTilt = StageConfigService.deckRestTilt
        const hoverT = StageConfigService.tiltAngle
        const title = card.count > 1
            ? (card.appName || card.title || I18n.tr("App")) + " ×" + card.count
            : (card.appName || card.title || I18n.tr("App"))
        return {
            x: Math.round(pp.x),
            y: Math.round(pp.y),
            w: Math.round(sc * plate.width),
            h: Math.round(sc * plate.height),
            angle: card.rightSide ? -restTilt : restTilt,
            yOff: card.perspectiveYOff,
            focal: StageGeo.TILT_FOCAL,
            radius: StageConfigService.cardRadius,
            title: title,
            count: card.count,
            z: parent && parent.z !== undefined ? parent.z : 0,
            hoverScale: StageConfigService.hoverScale,
            hoverTilt: card.rightSide ? -hoverT : hoverT,
            // engaging 交棒保持静置角（与 kwinrc TiltAngle 投影同源：
            // 展开窗口动画的起摆姿态；交棒时卡不压平）
            engagingTilt: (card.rightSide ? -1 : 1) * restTilt,
            hoverMs: StageConfigService.cardEnterDuration + 40,
            hoverDwellMs: StageConfigService.hoverDwellDelay,
            tiltMs: StageConfigService.tiltAnimDuration,
            enterMs: StageConfigService.cardEnterDuration,
            animMs: StageConfigService.animDuration,
            fanSpacing: StageConfigService.fanSpacing,
            fanHoverSpread: StageConfigService.fanHoverSpread,
            cardTint: StageConfigService.cardTint,
            cardBorder: StageConfigService.cardBorder,
            cardDepth: StageConfigService.cardDepth,
            cardTopLight: StageConfigService.cardTopLight,
            rightSide: card.rightSide,
            merged: card.merged,
            showCardTitle: StageConfigService.showCardTitle,
            enterInstant: card.enterInstant,
            // 拖拽净放大（老语义：1.06 槽位缩放 × 悬停 1.18 叠加）
            dragScale: card.scale,
            selfMergeHint: card.selfMergeHint,
            chipHot: card.isHovered || card.mergeGlow,
            iconsJson: card.iconsJson,
            rowsJson: card.rowsJson,
            // 图标排消费参数（v88：特效侧原本硬编码 24px+仅宽度封顶＝
            // stripIconSize/maxIconSlots 两个旋钮在实时模式失灵，且与
            // 静态模式 40px 视觉不一致）
            iconSize: StageConfigService.stripIconSize,
            iconSlots: card.maxIconSlots,
        }
    }
    // x 入列方向镜像：左侧从右滑入（+70），右侧从左滑入（−70）——都从
    // 桌面一侧进条；收集落卡（enterInstant）几何即终值，不走侧滑
    x: rightSide
        ? (parent ? parent.width - width - StageGeo.CARD_X_INSET : 0)
            - ((shown || enterInstant) ? 0 : 70)
        : StageGeo.CARD_X_INSET + ((shown || enterInstant) ? 0 : 70)
    opacity: (engaging ? 0.0 : (shown ? 1.0 : 0.0)) * StageConfigService.cardOpacity
    scale: (shown || enterInstant)
        ? (isHovered ? StageConfigService.hoverScale : 1.0) : 0.86
    // 悬停放大从左上角外扩（与 slot 的 TopLeft 缩放同向）：上边钉死、只向
    // 右/下生长——绕中心缩放会让四边同缩，压在边条上的指针被"缩出去"→
    // 悬停丢失（kill 循环的一环）。外扩区域内的指针不可能被挤出。
    transformOrigin: Item.TopLeft
    Component.onCompleted: {
        shown = true
        _noteFaceExposure()
    }
    Behavior on x { NumberAnimation { duration: StageConfigService.cardEnterDuration; easing.type: Easing.OutCubic } }
    // ⚠️ 无 Behavior on y：y 由窗口侧 layoutCards 经 slot（anchors 垂直
    // 居中）管理，这里没有 y 属性可动画；拖拽跟手走 slot.y 直赋
    // 收集落卡的淡入时长 = animDuration（收编飞行时长）：卡与窗同拍
    Behavior on opacity { NumberAnimation { duration: engaging ? StageGeo.ENGAGE_FADE_MS : (enterInstant ? StageConfigService.animDuration : StageConfigService.cardEnterDuration); easing.type: Easing.OutCubic } }
    // 缩放带过冲（OutBack）：悬停放大/入场有弹性回弹；位置类刻意保持
    // OutCubic——x/y 过冲会越过槽位触发悬停丢失（kill 循环前科）
    Behavior on scale {
        NumberAnimation {
            duration: StageConfigService.cardEnterDuration + 40
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    // 展开延迟派发改由窗口级队列 Timer 承担（round35 NEW-1/NEW-5：挂在
    // delegate 上的定时器会在派发窗口内随 delegate 销毁而丢派发），
    // 卡片淡出动画由 engaging 驱动的 opacity/tilt Behavior 承担。

    // ── 倾角状态机（角度交给着色器做真透视）：悬停/静止双旋钮解耦 ──
    // 静止 = 静置倾斜角（deckRestTilt，两模式统一——adaptive 完整显示
    // 也有静置姿态）；悬停 = 悬停倾斜角（tiltAngle，0 = 悬停放平阅读）；
    // 交棒（engaging）保持静置角——kwinrc TiltAngle 同源投影给展开窗口
    // 动画，卡片淡出姿态与窗口起摆姿态零跳变。
    // ⚠️ 悬停倾斜下 plane 内的关闭钮被透视投影挪位，热区对齐改走
    // _closeProj（见 closeHit）；"按钮角区瞄准摆平"已废除——活体模式下
    // 卡面由特效直绘，QML 的摆平从没生效过（两侧不一致的既存缺陷），
    // 统一由热区跟随解决。
    // ⚠️ schema 键 deckRestTilt/deckSidePeek 是牌堆时代遗名（持久化配置
    // 不能改名）：deckRestTilt 现役语义 = 双模式的静置倾角；
    // deckSidePeek 仍属 scroll 模式。
    property real tiltCur: dragging ? 0
        : (engaging
            ? StageConfigService.deckRestTilt
            : (isHovered
                ? StageConfigService.tiltAngle
                : StageConfigService.deckRestTilt))
    Behavior on tiltCur {
        NumberAnimation {
            duration: card.engaging ? 180 : StageConfigService.tiltAnimDuration
            easing.type: Easing.OutCubic
        }
    }

    // 悬停 = 整卡或任一按钮热区命中（合成）：按钮类 MouseArea 在最上层，
    // 指针移上去会让整卡 MouseArea 失去悬停——若只看后者，卡片会缩回
    // 1.0 → 按钮随 5% 缩放位移 → 指针脱出 → 再放大 = 抽搐循环（实测），
    // 且点击永远落空。⚠️ splitHit 必须在列（2026-09-30 抽搐定案）：漏列
    // 时指针移上拆分钮 = isHovered 翻 false → hovered(false) → 窗口侧
    // 清 hoveredKey 整列回基础槽位 = 卡在静止指针底下移位 → 悬停失而
    // 复得 → 布局弹回 = 抖动 + tilt/scale 来回翻转（"拆分钮点不到"）。
    // 按钮角区合成进 isHovered：指针在角区（按钮间的空隙）时卡不缩回。
    readonly property bool isHovered: cardMouse.containsMouse
        || closeHit.containsMouse
        || splitHit.containsMouse
        || iconRowHover.containsMouse
        || buttonAimHover.containsMouse
    onIsHoveredChanged: card.hovered(card.isHovered)

    // ── 关闭钮热区的透视跟随（悬停倾斜的点击对齐）──
    // 关闭钮视觉在 plane 内、随真透视投影（倾斜卡面上的钮被挪位），而
    // 热区是轴对齐固定矩形——不跟随的话悬停倾斜（tiltAngle>0）下指针点
    // "看到的钮"会落在热区外、被整卡 MouseArea 接走（点关闭反被展开）。
    // 按与 stage_tilt.frag 同源的针孔公式把热区中心从平面位投到视觉位
    //（tiltProject 孪生；Δ = 投影后 − 平面位）。角用 tiltCur 绑定：
    // 拖拽摆平/悬停补间都自动连续跟随（含 Behavior），两模式一致。
    // 拆分芯片/图标排是"正视覆盖层"（用户定稿不随倾斜）——热区与芯片
    // 都在固定位，天然对齐，不动。
    readonly property var _closeProj: {
        // 热区中心平面位（相对卡中心）：宽 24 锚右上 6/6 + 卡头 18 中心
        const hu = card.width / 2 - 18
        const hv = 18 - card.height / 2
        const rad = (card.rightSide ? -1 : 1) * card.tiltCur * Math.PI / 180
        const s = Math.sin(rad), c = Math.cos(rad)
        const k = StageGeo.TILT_FOCAL / (StageGeo.TILT_FOCAL + hu * s)
        return {
            dx: hu * c * k - hu,
            dy: (hv + card.perspectiveYOff) * k
                - card.perspectiveYOff - hv,
        }
    }

    // 合并完成的可拆分提示：merged 原地翻真（首次拖卡合并就是这条路径）
    // 时拆分钮自动亮一小会儿——拆分钮平时只在悬停时显现，合并完指针不在
    // 卡上，用户看到的是"没有任何拆分入口"，实测被读作"按钮丢了"
    //（2026-10-03；切换走再切回的重建路径因自然带 hover 而"就有了"）
    property bool mergeGlow: false
    property Timer _mergeGlowTimer: Timer {
        interval: 1800
        onTriggered: card.mergeGlow = false
    }
    onMergedChanged: {
        if (merged) {
            mergeGlow = true
            _mergeGlowTimer.restart()
        }
    }
    // 聚焦辉光：悬停/交棒时点亮（与聚焦放大同步）
    readonly property bool glowOn: card.isHovered || card.engaging

    // ── 卡面内容层（离屏）：背板/辉光/头部/缩略图全部渲染进 plane 的层
    // 纹理，再由 stage_tilt 着色器按共享透视重投影。plane 比卡面大一圈：
    // 辉光外扩 ~14px + 扇叠偏移（2 张 × 间距 × 悬停 1.4，fanPad 随
    // fanSpacing 缩放——层纹理只渲染 item 自身尺寸内的内容，扇叠超界会
    // 被切断成直角，实测"堆叠卡被裁剪"即此）。
    // ⚠️ 着色器以 plane 中心对称采样：扩容必须对称（plate 保持居中）。
    // 层纹理外扩余量：2 张 × 最大扩散系数 × 间距（默认 2×1.4=2.8 同旧值；
    // fanHoverSpread 调大时余量同步长——不够＝扇叠被层边界裁成直角）
    // 单窗卡没有扇叠背板，余量归零：plane 只剩 16/22 的辉光/投影余量
    //（辉光实测外扩 13×18、投影 8×17，均 < 16/22），层纹理与着色器项
    // 面积各减 ~30%，悬停动画期的离屏重渲随之变小。count 变化（合并/
    // 拆散）时 plane 尺寸跟着变，层保持启用、只做常规重烘焙。
    readonly property real fanPad: card.count > 1
        ? 2 * Math.max(1.4, StageConfigService.fanHoverSpread)
            * StageConfigService.fanSpacing
        : 0
    Item {
        id: plane
        visible: false
        // 余量 50（原 16/22）：投影改 SDF 后外扩 = offsetY + softness + 1
        // ≈ 49px，旧的 22 会把它裁成直边。余量对称 = 卡面仍居中，透视
        // 采样（stage_tilt 以项中心为相机竖轴）不受影响。
        x: -(50 + card.fanPad)
        y: -(50 + card.fanPad)
        width: parent.width + 100 + card.fanPad * 2
        height: parent.height + 100 + card.fanPad * 2
        // ⚠️ 层启用**不跟 previewActive**（2026-10-18 合并/拆分拖回排障）：
        // 卡在屏幕外创建（拆组后追加到列尾）时 layer 为 false，之后拖回
        // 屏幕内再启用，烘焙出的层纹理整块空白且此后不再刷新——卡面
        // 全丢、只剩根层图标排（悬停/再出屏再入屏都不愈，只有 delegate
        // 重建能愈）。层只有在被 stage_tilt 采样时才真正渲染，离屏卡
        // 的 ShaderEffect 不可见＝不采样＝不产生逐帧开销，故可常开。
        layer.enabled: !card.effectOwnedChrome
        layer.smooth: true

        // ── 扇叠背板（macOS Stage Manager 同语义）：同应用多窗 = 一前
        // 一后的卡片簇。声明在 plate 之前 = 画在卡背之下；随卡面一起被
        // 透视投影（它们本来就是"卡片"）。方向镜像：条在右时朝屏缘一侧
        // 探出。悬停时间距微扩（卡片簇"吸气"的即时反馈）。最多露 2 张，
        // 更多的用左下角图标排表达 ──
        Repeater {
            model: Math.min(card.count - 1, 4)
            Rectangle {
                required property int index
                readonly property real off: (index + 1)
                    * StageConfigService.fanSpacing
                    // 触发集与特效侧 fanBlend 一致（hover/dropHover/dwellHint
                    // 三态同权）+ 时长 150ms OutCubic——两模式动画手感统一
                    * ((card.isHovered || card.dropHovered || card.dwellHint)
                        ? StageConfigService.fanHoverSpread : 1)
                // 方向（用户定稿）：左上角探出；条在右时镜像到右上
                x: card.rightSide ? plate.x + off : plate.x - off
                y: plate.y - off
                width: plate.width
                height: plate.height
                radius: plate.radius
                color: Qt.rgba(0.03, 0.05, 0.09,
                    StageConfigService.cardTint * (0.88 - index * 0.18))
                border.width: 1
                border.color: Qt.rgba(255, 255, 255,
                    StageConfigService.cardBorder * (0.8 - index * 0.18))
                opacity: card.engaging ? 0.0 : 1.0
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }
        }

        // 背板（原根 Rectangle 的颜色/描边/圆角，随卡面一起被透视投影）
        Rectangle {
            id: plate
            x: 50 + card.fanPad
            y: 50 + card.fanPad
            width: parent.width - 100 - card.fanPad * 2
            height: parent.height - 100 - card.fanPad * 2
            radius: StageConfigService.cardRadius
            // 背板浓度：静置 cardTint，悬停/驻留预示自动 ×1.3 提亮（上限 0.95）
            //（活体内容走 paintScreen 后置通道画在一切之上——背板正常渲染，
            // 内容盖在其上，视觉与快照时代同层。旧的 livePainted 开洞是
            // 给"内容画在条带之下"的已废弃架构留的，留着会把玻璃底板抠空
            // = 卡片分裂成"透明框＋悬浮内容"）
            color: (card.isHovered || card.dropHovered || card.dwellHint)
                ? Qt.rgba(0.10, 0.13, 0.20,
                    Math.min(0.95, StageConfigService.cardTint * 1.3))
                : Qt.rgba(0.05, 0.07, 0.12, StageConfigService.cardTint)
            border.width: (card.dropHovered || card.selfMergeHint
                || card.dwellHint) ? 2 : 1
            // dropHovered/selfMergeHint = 武装级高亮（亮蓝）；
            // dwellHint = 驻留预示（强蓝，"停住别动"的即时反馈——首版
            // 1px@45% 实测几乎不可见 = "反馈太差"，加粗提亮）
            border.color: (card.dropHovered || card.selfMergeHint)
                ? Qt.rgba(0.45, 0.85, 1.0, 0.95)
                : card.dwellHint
                    ? Qt.rgba(0.45, 0.85, 1.0, 0.78)
                    : card.glowOn
                        ? Qt.rgba(0.62, 0.80, 1.0, 0.85)
                        : Qt.rgba(255, 255, 255, StageConfigService.cardBorder)
            Behavior on color { ColorAnimation { duration: 130 } }
        }

        // ── 常驻投影(iPadOS 还原,2026-10-17):参考缩略图卡四周有柔和短
        // 投影（sm4 原生尺度实测：贴边压暗 ~15-20%，衰减半径 ≈ 卡宽
        // 20%，上/左也有一圈淡影 = 光源略偏左上而非纯底投影）。声明在
        // 背板之后/内容之前 = 随 plane 纹理一起被透视斜切（投影随卡
        // 姿态，与参考一致）。
        // 2026-10-18：改用与浮层同源的 SDF 投影着色器（KosCardShadow）。
        // 旧的 4 层步进黑矩形在 30° 透视角下卡底能看出阶梯边（每级
        // 6/8px 的外扩在斜切后被放大），而 SDF 的 smoothstep 是连续
        // 衰减；峰值也压回参考的 ~20%（旧叠加 ≈26% 偏重）。
        // ⚠️ 不要改回 anchors.centerIn：锚点会覆盖 x/y 绑定，投影变成
        // 上下对称的光晕（2026-10-18 卡顶黑边事故）。显式 x/y 定位。
        KosCardShadow {
            cardWidth: plate.width
            cardHeight: plate.height
            cornerRadius: plate.radius
            // 光源在左上：右下重、左上轻
            offsetX: 1
            offsetY: 4
            // 模糊半径 ≈ 卡宽 35%：着色器对衰减再平方（alpha²），视觉
            // 半程 ≈ softness/2，44 对应实测参考的 ~17-19px 有效衰减
            softness: 44
            shadowColor: Qt.rgba(0, 0, 0, 0.20)
            x: plate.x - margin
            y: plate.y - margin
        }

        // ── 聚焦辉光：多层薄步进衰减模拟柔和光晕。⚠️ 平色矩形层叠会出硬边
        //（在深色壁纸上呈"黑条"，实测踩过）——每层透明度减半、外扩小步长，
        // 层间差异小到不可辨。声明在内容之前 = 画在卡背之上、内容之下；
        // Rectangle 不裁剪子项，超出卡面的辉光进 plane 纹理 ──
        Repeater {
            model: 5
            Rectangle {
                required property int index
                anchors.centerIn: plate
                width: plate.width + 6 + index * 5
                height: plate.height + 8 + index * 7
                radius: plate.radius + 4 + index * 4
                color: Qt.rgba(0.55, 0.75, 1.0, 1.0)
                opacity: card.glowOn
                    ? StageConfigService.cardGlow / Math.pow(2, index) : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: StageConfigService.cardEnterDuration
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // ── 玻璃质感：顶部受光渐变（悬停 ×2 提亮） ──
        Rectangle {
            anchors.fill: plate
            radius: plate.radius
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop {
                    position: 0.0
                    color: Qt.rgba(1, 1, 1, card.isHovered
                        ? Math.min(0.4, StageConfigService.cardTopLight * 2)
                        : StageConfigService.cardTopLight)
                }
                GradientStop { position: 0.35; color: Qt.rgba(1, 1, 1, 0.02) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.10) }
            }
        }

        // 头部：名称（多窗带数量）+ 关闭。不放应用图标——卡面保持纯缩略图
        //（图标只在缩略图未就绪的占位里出现）
        // z:1 抬到整卡 cardMouse 之上（声明在后的 MouseArea 会盖住关闭钮，
        // 点关闭变成展开窗口——实测踩过）；红色悬停高亮随之恢复
        Item {
            id: cardHeader
            z: 1
            anchors {
                top: plate.top
                left: plate.left
                right: plate.right
                margins: 8
            }
            height: 24

            Text {
                anchors {
                    left: parent.left
                    // 合并卡让位给拆分芯片（芯片亮起盖住标题尾部 ~18px，
                    // elide 又按全宽算——读作"标题被啃"）。芯片已搬根层，
                    // 锚点坐标不再同系，改固定让位量：merged 时让出 ✕(20)
                    // + 间隙(4) + 芯片(20) + 余量(6)
                    right: parent.right
                    rightMargin: card.merged ? 50 : 26
                    verticalCenter: parent.verticalCenter
                }
                // 名称可关（stage-config showCardTitle）：关=纯窗口内容。
                // 沉浸缩略图上白字需要描边兜可读性
                visible: StageConfigService.showCardTitle
                text: card.count > 1
                    ? (card.appName || card.title || I18n.tr("App")) + " ×" + card.count
                    : (card.appName || card.title || I18n.tr("App"))
                color: "white"
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.55)
                font { pixelSize: 11; weight: Font.Bold }
                elide: Text.ElideRight
            }

            // 拆分钮视觉在根层 splitHit 内（见下）——原画在 plane 头部，
            // 但不可见子树（plane visible:false）里的 visible 改动被吞
            //（绑定不重求值 + 命令式写也不重渲染，2026-10-03 原地合并
            // 三轮实测），原地合并后芯片永远隐身。根层直渲染 + opacity
            // 门控彻底绕开；悬停时卡片压平，直渲染芯片与卡面对齐

            Rectangle {
                id: cardClose
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                width: 20
                height: 20
                radius: 10
                // iPadOS 还原(2026-10-17):参考缩略图无常驻关闭钮——只在
                // 卡片悬停时出现。静置=暗底圆 + 白 ×；悬停按钮本体=红圆底
                opacity: (card.isHovered || closeHit.containsMouse) ? 1.0 : 0.0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                color: closeHit.containsMouse
                    ? "#ef4444" : Qt.rgba(0.04, 0.055, 0.08, 0.45)

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.pixelSize: 11
                    font.bold: true
                    color: closeHit.containsMouse
                        ? "white" : Qt.rgba(1, 1, 1, 0.82)
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
            }
        }

        // 缩略图视口：填满整卡（沉浸式——整卡就是窗口内容，无内框）。
        // ⚠️ Rectangle.clip 是矩形裁切：满卡后直角缩略图会盖住卡背的
        // 圆角（"卡片变矩形"实测）。圆角 = 下面的 thumbRound 着色器对
        // thumbCard 的层纹理做 SDF 抠 alpha——结构与 plane → stage_tilt
        // 完全同款（visible:false + 裸 layer 出纹理 + 自写着色器采样）。
        // ⚠️ 勿改回 Qt5Compat OpacityMask（layer.effect 形态）：带特效的
        // 嵌套层在 plane 离屏层内于本机 freedreno 栈上静默失效（实测直角
        // 照旧，且疑似连带杀掉整卡渲染——2026-09-30 排障定案）。
        Item {
            id: thumbCard
            anchors.fill: plate
            visible: false
            // 同上（plane 层注释）：不跟 previewActive，避免"离屏创建 →
            // 回屏启用"的空白层纹理；本层只在 plane 烘焙时被采样。
            layer.enabled: !card.effectOwnedChrome
            layer.smooth: true

            readonly property string thumbUrl: WindowService.thumbnailUrl(card.targetId)

            // ── 活体流（round30 迁移 / round36 占空比节流）──
            // ScreencastingRequest{uuid} 走 zkde_screencast 协议开单窗口
            // PipeWire 流；PipeWireSourceItem 渲染。悬停判定源 = 窗口侧
            // hoveredKey（聚焦布局同一来源；卡片自己的 MouseArea isHovered
            // 无头调试钩子触不到，且多卡瞬时命中会破"单流"约束，故不参与）。
            //
            // ⚠️ round36 占空比节流：kpipewire 无 fps 旋钮（API 只有
            // nodeId/allowDmaBuf/state），本机容器 GPU 预算红线（round31
            // 悬停即被宿主杀桌面）。nodeId 可运行时改写 = 消费者可拔插：
            // 连接 streamOnMs 抓新鲜帧（断开前 grabToImage 定格最后一帧，
            // 防闪烁）→ 断开 streamOffMs（无消费者 = WirePlumber 撤链 =
            // KWin 停止离屏渲染，源节点挂起零成本）。平均负载 ≈ 占空比 ×
            // 单流全速，GPUTotalUsed（/proc/meminfo）可实测对账。
            readonly property bool liveWanted:
                card.previewActive && !card.effectOwnedChrome
                    && (card.focusKey === card.appKey || card.engaging)
            // 合成启停门：liveWanted 与 thumbLiveStream 任一翻转都要重算
            //（原先只监听 liveWanted——悬停中途在设置页打开"活体流"开关
            // 不会启动消费，直到悬停离开再进）
            readonly property bool streamArmed:
                thumbCard.liveWanted && StageConfigService.thumbLiveStream
            property bool streamOn: false     // 占空比相位：true=连接消费
            property var liveGrabResult: null // Hold only the current frozen frame.
            // 2026-10-17 根修:url 类型声明会把 result.url 的 undefined 转成
            // "非空 url"(!== "" 为真),下游三元误走活体支拿 undefined →
            // source 恒空。改 string + 真值判(根因:grabToImage 结果对象的
            // url 在本机栈上返回 undefined,见 ledger 第 18 轮)
            readonly property string liveGrabUrl: liveGrabResult
                ? String(liveGrabResult.url || "") : ""
            property int streamGeneration: 0

            function _syncStream() {
                streamGeneration++
                liveGrabResult = null
                if (streamArmed) {
                    streamOn = true   // 首相位即连接（别先空等 off 周期）
                    streamCycle.restart()
                } else {
                    streamOn = false
                    streamCycle.stop()
                }
            }
            onStreamArmedChanged: _syncStream()

            ScreencastingRequest {
                id: streamRequest
                // ⚠️ uuid 口径 = KWin internalId（record.handleId）= PlasmaWindow
                // uuid；shell 句柄（window-N）直传会静默开不出流（实测）。
                // liveWanted 期间源常驻（无消费者时挂起，不渲染）。
                // ⚠️ 默认禁用（thumbLiveStream=false）：容器 GPU 预算红线
                uuid: thumbCard.liveWanted && StageConfigService.thumbLiveStream
                    ? WindowService.handleIdOf(card.targetId) : ""
                onNodeIdChanged: if (nodeId > 0)
                    console.info("[StageCard] stream node ready: " + nodeId
                        + " for " + card.appKey)
            }

            // 相位定时器：on 相位到期 → 抓帧定格 → 断开（off 相位）；
            // off 到期 → 重连。liveWanted 消失即停摆并复位。
            property Timer streamCycle: Timer {
                interval: thumbCard.streamOn
                    ? StageConfigService.streamCycleOnMs
                    : StageConfigService.streamCycleOffMs
                onTriggered: {
                    if (!thumbCard.liveWanted
                            || !StageConfigService.thumbLiveStream)
                        return
                    if (thumbCard.streamOn) {
                        // 断开前把活体帧定格进 preview（异步 grab，回调
                        // 晚于一拍也无碍——preview 旧帧兜底）
                        if (liveStream.ready) {
                            const generation = thumbCard.streamGeneration
                            liveStream.grabToImage(function(result) {
                                if (generation === thumbCard.streamGeneration
                                        && thumbCard.streamArmed)
                                    thumbCard.liveGrabResult = result
                            })
                        }
                        thumbCard.streamOn = false
                    } else {
                        thumbCard.streamOn = true
                    }
                    restart()
                }
            }


            PipeWireSourceItem {
                id: liveStream
                anchors.fill: parent
                visible: streamRequest.nodeId > 0 && ready && thumbCard.streamOn
                // 占空比消费：off 相位拔掉消费者（源保留挂起）
                nodeId: thumbCard.streamOn ? streamRequest.nodeId : 0
                // freedreno + 容器 GPU 栈 dmabuf 坑多（Chromium 纹理损坏
                // 同源），保守关闭；SHM 走系统内存，VRAM 占用最小
                allowDmaBuf: false
            }

            // 卡面 = 整窗缩略图（卡形跟窗口宽高比走，见 StageSidebarWindow.
            // _cardHeightFor）：完整显示窗口内容，不裁切、不留大边。
            Image {
                id: preview
                anchors.fill: parent
                // 活体流就绪时让位（避免双绘）；流断开自动回来兜底。
                // 优先显示占空比断开前定格的活体帧（最小化窗口无人交互，
                // 内容不再变化，定格帧即最新），否则收编快照
                //
                // ⚠️ 顺序即正确性：URL 判定排在 liveStream.visible 之前。
                // QML 的 && 短路不会为未求值的操作数建立依赖，而
                // PipeWireSourceItem.visible 在卡刚创建那一拍可能还没走到
                // 自己的绑定、读到 QQuickItem 默认的 visible=true——旧写法
                // `!liveStream.visible && !!url` 一旦在这一拍短路，URL 依赖
                // 就永远不会建立（绑定冻结在 false）；先判 URL 则 URL 变化
                // 必然触发重算，liveStream.visible 在其后才被读取。
                // 2026-10-17:displayUrl 链(parent.thumbUrl 经中间容器)在
                // 本机实测恒得空 source(status 卡 Null、文件有效、pA/layer
                // 全真)——旁路中间层,直接绑 thumbCard.thumbUrl;liveGrabUrl
                // 的优先级保持(活体定格帧仍优先)
                // displayUrl/visible 声明式绑定已废弃(见 _syncPreviewSource
                // 注释)——visible 也走命令式,读数属性保留供 debugGeom
                readonly property string displayUrl: source.toString()
                // 合成器活体卡直绘时让出卡面（opacity：plane 内 visible
                // 改动被吞，opacity 链有效——快照退路在任何让位失败时
                // 自动恢复，特效不在=livePainted=false=快照照常画）
                opacity: card.livePainted ? 0.0 : 1.0
                source: card.previewActive && !card.effectOwnedChrome
                    ? displayUrl : ""
                // 同步解码 + 禁缓存：实时换帧时不留异步空白间隙（闪烁根源）
                asynchronous: false
                cache: false
                sourceSize: Qt.size(StageConfigService.thumbSize,
                    Math.round(StageConfigService.thumbSize * 0.7))
                // 卡形已跟窗口宽高比走（横窗横卡），整窗等比缩进卡面：
                // 完整显示、不裁切（macOS 台前语义）。缩略图是窗口内容，
                // 与含装饰的 KWin 几何有细微比例差——居中留边即可
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignHCenter
                verticalAlignment: Image.AlignVCenter
                smooth: true
                // 失效自愈：URL 指向的 PNG 被新一轮拍摄替换/删除后，Image
                // 会停在 Error 且同一 source 不会重读盘（可见性变化、同串
                // 重赋值都无效）——上报给 WindowService 清账并补拍，见
                // thumbnailLoadFailed 注释
                // 2026-10-17 根修:声明式 source 绑定在本机实测**从未求值**
                //(onSourceChanged 一次不触发、src 恒空,而 pA/layer/thumbUrl
                // 全真)——thumbCard 是 visible:false+layer 烘焙子树,深层
                // 声明式绑定的依赖注册疑似被层烘焙路径丢弃。改为命令式:
                // thumbUrl/liveGrabUrl 变化与让位开关翻转时显式重算 source
                function _syncPreviewSource() {
                    const want = (card.previewActive && !card.effectOwnedChrome)
                        ? (thumbCard.liveGrabUrl
                            ? String(thumbCard.liveGrabUrl) : thumbCard.thumbUrl)
                        : ""
                    preview.source = want
                    preview.visible = preview.source !== ""
                        && !liveStream.visible
                }
                Component.onCompleted: _syncPreviewSource()
                Connections {
                    target: thumbCard
                    function onThumbUrlChanged() { preview._syncPreviewSource() }
                    function onLiveGrabUrlChanged() { preview._syncPreviewSource() }
                }
                // 让位开关翻转也得同步(卡所属特效接管状态变化时)
                Connections {
                    target: card
                    function onPreviewActiveChanged() { preview._syncPreviewSource() }
                    function onEffectOwnedChromeChanged() { preview._syncPreviewSource() }
                }
                // 2026-10-17 轮询兜底:实测本机 thumbCard 子树(visible:false
                // +layer 烘焙)信号链不可靠——onThumbUrlChanged 在值变化时
                // 不发(ledger 第 17 轮)。轮询直调 sync,与 WindowService
                // 的 1.5s retry 同拍;信号恢复时双路径幂等无副作用
                Timer {
                    interval: 500
                    running: card.faceExposed
                    repeat: true
                    onTriggered: preview._syncPreviewSource()
                }
                onStatusChanged: {
                    if (status === Image.Error) {
                        card._faceEmptyExposed = true   // 图被删等于回到"无图"态
                        WindowService.thumbnailLoadFailed(card.targetId,
                            String(preview.source))
                    } else if (status === Image.Ready
                            && card._faceEmptyExposed) {
                        // 首次出图：空脸先渲过的卡面需要重建才画得出来
                        card._faceEmptyExposed = false
                        card.faceRecreateRequested()
                    }
                }
            }

            // 缩略图未就绪时的占位：只留标题文本居中——应用图标改由左下
            // 角的正视图标排承担（居中大图标是旧占位形态，用户定稿移除）
            Text {
                anchors.centerIn: parent
                visible: !preview.visible && !liveStream.visible
                width: Math.min(parent.width - 16, contentWidth)
                text: card.title || I18n.tr("Window")
                color: Qt.rgba(1, 1, 1, 0.40)
                font.pixelSize: 10
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // 圆角化的缩略图本体：采样 thumbCard 层纹理，圆角矩形 SDF 抠
        // alpha——圆角外透出下方背板（背板自带 radius，视觉浑然一体）。
        // 半径/尺寸绑定 plate，与背板圆角严格同源（含设置页实时调整）。
        ShaderEffect {
            anchors.fill: plate
            property variant source: thumbCard
            property real crad: plate.radius
            property size isz: Qt.size(width, height)
            fragmentShader: Qt.resolvedUrl("../../shaders/stage_round.frag.qsb")
        }

        // 深度渐变：远侧压暗盖在内容之上，增强"退到侧边"的纵深（悬停/点击时淡出）。
        // 压暗侧 = 屏缘侧（左条压左、右条压右），条在右时整个翻转
        Rectangle {
            anchors.fill: plate
            radius: plate.radius
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: card.rightSide ? Qt.rgba(0, 0, 0, 0.0)
                        : Qt.rgba(0, 0, 0, StageConfigService.cardDepth)
                }
                GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, 0.0) }
                GradientStop {
                    position: 1.0
                    color: card.rightSide ? Qt.rgba(0, 0, 0, StageConfigService.cardDepth)
                        : Qt.rgba(0, 0, 0, 0.0)
                }
            }
            opacity: (card.isHovered || card.engaging) ? 0.0 : 1.0
            Behavior on opacity { NumberAnimation { duration: 250 } }
        }
    }

    // ── 真透视倾斜：把 plane 纹理按共享相机针孔模型重投影（逆映射逐像素
    // 采样）。相机 = 所有卡片共享：竖轴取本项中心（卡在内容列里居中），
    // 地平线 = 视口中心（camRel.y 由 perspectiveYOff 换算）——整列灭点唯一。
    // 覆盖整个 plane 再加边距：① 扇叠背板探出卡面外，必须整面入窗；② 近缘
    // 随 k 放大 ±3%，外扩余量防投影边缘被 item 边界裁掉。中心对称 = 采样
    // 映射不变（camRel 取项中心，尺寸只定义可见窗口）。
    ShaderEffect {
        anchors.centerIn: parent
        width: plane.width + 64
        height: plane.height + 64
        // chrome 让位：特效画卡面时 QML 透视层退场。用 visible（根层
        // 直渲染项，visible 正常生效——被吞的是 plane 不可见子树内部的
        // 改动）：彻底停掉对 plane 层纹理的采样与重渲染——opacity 0 时
        // 场景图仍逐帧重渲层（动画期掉帧的大头之一）。
        visible: card.previewActive && !card.effectOwnedChrome
        // uniform 显式声明（ShaderEffect 不自动创建属性；source 约定名，
        // plane 的 layer 纹理由此进 sampler）
        property variant source: plane
        // 右侧常驻镜像：正角 = 左缘近大（左条卡片朝屏幕中心），右条应
        // 右缘近大——倾斜角取反（深度渐变/扇叠/图标排的镜像在各自处）
        property real angleRad: (card.rightSide ? -card.tiltCur : card.tiltCur)
            * Math.PI / 180
        property real focal: StageGeo.TILT_FOCAL
        property size cardSize: Qt.size(plane.width, plane.height)
        property size camRel: Qt.size(width / 2,
            height / 2 - card.perspectiveYOff)
        property real yOff: card.perspectiveYOff
        property size itemSize: Qt.size(width, height)
        fragmentShader: Qt.resolvedUrl("../../shaders/stage_tilt.frag.qsb")
    }

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        property real pressSceneX: 0
        property real pressSceneY: 0
        property bool dragArmed: false
        property bool wasDrag: false
        onPressed: function(mouse) {
            const press = mapToItem(null, mouse.x, mouse.y)
            pressSceneX = press.x
            pressSceneY = press.y
            dragArmed = false
            // 每次按压重置：界外松手（拖拽中指针移出卡面）只发 released
            // 不发 clicked，wasDrag 若留到下一次按压会吞掉那次正常点击
            wasDrag = false
        }
        onPositionChanged: function(mouse) {
            if (!(mouse.buttons & Qt.LeftButton))
                return
            const p = mapToItem(null, mouse.x, mouse.y)
            if (!dragArmed) {
                // 双轴位移模长起拖：中心合并手势是纯横向位移，y-only 判定
                // 会把手压得稳的横拖整个饿死（永远进不了拖拽态）
                if (Math.hypot(p.x - pressSceneX, p.y - pressSceneY)
                        > StageGeo.DRAG_PICK_THRESHOLD) {
                    dragArmed = true
                    card.dragStarted(p.x, p.y)
                }
                return
            }
            card.dragMoved(p.x, p.y)
        }
        onReleased: {
            if (dragArmed) {
                dragArmed = false
                wasDrag = true
                card.dragReleased()
            }
        }
        onClicked: function(mouse) {
            // 右键合并卡 = 拆散回各自的应用卡（左键照常 engage）
            if (mouse.button === Qt.RightButton) {
                if (card.merged)
                    card.ungroupRequested()
                return
            }
            if (wasDrag) {
                wasDrag = false
                return
            }
            card.engageClicked()
        }
    }

    // 关闭钮热区必须在卡根层级：视觉树渲染进 visible:false 的透视层
    //（plane，着色器源），层内 MouseArea 不收输入——整卡 cardMouse 把
    // 点击全接走（"关闭按钮点不动"的根因）。plane/plate 与根坐标 1:1
    // 对齐（plane.x=-50/plate.x=50 抵消）。
    // x/y 显式定位 = 基准位（右上 6/6）+ _closeProj 透视位移：视觉钮在
    // 投影位、热区跟到同位（悬停倾斜下不跟随会"点关闭变展开"，见
    // _closeProj 注释）。
    MouseArea {
        id: closeHit
        z: 1
        width: 24
        height: 24
        x: parent.width - width - 6 + card._closeProj.dx
        y: 6 + card._closeProj.dy
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.closeAllRequested()
    }

    // 按钮角区热区：覆盖两个按钮的更大区域（NoButton 不截点击；声明在
    // cardMouse 之后=角区内它是 hover 顶层，压住 cardMouse；closeHit/
    // splitHit z:1 在按钮上仍是最顶层——isHovered 合成见上）。
    // ⚠️ 固定锚右上：视觉钮（cardClose/cardSplit）在头部永远位于卡面
    // 右上（头部横贯 plate、关闭钮锚右），不随 side 镜像——镜像到左上
    // 会瞄准错侧（2026-09-30 修正）。
    MouseArea {
        id: buttonAimHover
        width: 104
        height: 48
        anchors {
            top: parent.top
            right: parent.right
            rightMargin: 2
        }
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor
    }

    // 拆分热区：与 closeHit 同款根层原理（plane 层内不收输入）。位置与
    // 头部拆分钮对齐：closeHit 右缘 6 + 钮 20 + 间隙 4 = 30，热区 22px
    // 居中于 20px 视觉钮再 +1 → rightMargin 31
    MouseArea {
        id: splitHit
        z: 1
        width: 22
        height: 22
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 7
            rightMargin: 31
        }
        visible: card.merged
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.ungroupRequested()

        // 拆分钮视觉（根层直渲染，绕开 plane 不可见子树吞改动的坑）：
        // 芯片画两张错位小卡表达"拆开"；opacity 门控（悬停或合并提示），
        // 热区门控由外层 splitHit.visible 承担（根层绑定正常工作）
        Rectangle {
            id: cardSplit
            anchors.centerIn: parent
            width: 20
            height: 20
            radius: 10
            color: splitHit.containsMouse ? "#f59e0b" : "transparent"
            // 常显暗态：合并卡要让用户知道能拆（与特效芯片同语义）；
            // 活体模式特效覆盖层画右上同位芯片，QML 视觉隐藏防双绘
            visible: card.previewActive && !card.effectOwnedChrome
            opacity: (splitHit.containsMouse || card.isHovered || card.mergeGlow)
                ? 1.0 : 0.35
            Behavior on opacity { NumberAnimation { duration: 120 } }

            Rectangle {
                width: 9; height: 9; radius: 2
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1.5
                anchors.verticalCenterOffset: -1.5
                color: "transparent"
                border.width: 1.4
                border.color: "white"
            }
            Rectangle {
                width: 9; height: 9; radius: 2
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 1.5
                anchors.verticalCenterOffset: 1.5
                color: splitHit.containsMouse ? "#ffffff" : "transparent"
                border.width: 1.4
                border.color: "white"
            }
        }
    }

    // ── 左下角窗口标识（iPadOS 还原，参考 ref/c1·c2·c3）──
    // 单窗：一枚大图标半悬卡角外（ref/c3 实测：水平探出 27%、垂直 60%）。
    // 多窗合并卡：白色圆角胶囊，内为**逐窗**「图标 + 标题」竖排（ref/c2
    // 实测：胶囊 ≈ 卡宽 33%，底/左各探出卡外约 8-10px）。两种形态都正视、
    // 独立图层（不进 plane 透视纹理，不随卡倾斜——用户定稿"像小图标盖住
    // 卡片左下角"）；点击直达对应窗口；条在右时整体镜像到右下角。
    Item {
        id: iconRow
        z: 2
        // chrome 让位：图标排已迁特效正视覆盖层（用户定稿"正视盖住左下
        // 角"），QML 侧隐藏防双绘
        visible: card.previewActive && !card.effectOwnedChrome
        // 多窗形态：逐窗行 >1（同应用两扇窗也是两行——参考列的是窗口，
        // 不是应用）。rowsJson 缺失（旧载荷/热重载）时退回单图标 + "+N"
        readonly property bool listForm: card.windowRows.length > 1
        // 单窗图标随卡高封顶（横窗矮卡时 60px 图标会盖掉半张卡）
        readonly property int iconSize: Math.min(
            StageConfigService.stripIconSize,
            Math.round(card.height * 0.42))
        readonly property int iconGap: Math.max(3, Math.round(iconSize * 0.2))
        // 胶囊度量：按参考比例随卡宽缩放（ref/c2：胶囊≈33% 卡宽、图标
        // 22% 胶囊宽、行高 26%、圆角 24%；旧值是按 216 宽卡定死的绝对值，
        // 卡缩小到 96 后必须同比缩，否则胶囊会比卡还宽）
        readonly property int pillW: Math.round(card.width * 0.33)
        readonly property int pillIcon: Math.max(6, Math.round(pillW * 0.22))
        readonly property int pillRowH: Math.max(8, Math.round(pillW * 0.26))
        readonly property int pillPadX: Math.max(2, Math.round(pillW * 0.11))
        readonly property int pillPadY: Math.max(2, Math.round(pillW * 0.07))
        readonly property int pillRadius: Math.max(4, Math.round(pillW * 0.24))
        readonly property int pillMaxRows: 4
        readonly property int displayRows:
            Math.min(card.windowRows.length, pillMaxRows)
        readonly property bool overflow: card.windowRows.length > displayRows
        readonly property int pillH: displayRows * pillRowH + pillPadY * 2
        // 单窗形态的并列上限（maxIconSlots 旋钮保留；预设钳 1）
        readonly property int visibleCount: Math.min(card.iconPairs.length,
            card.maxIconSlots,
            Math.floor((card.width + iconGap) / (iconSize + iconGap)),
            1)
        readonly property real rowWidth:
            visibleCount * iconSize + Math.max(0, visibleCount - 1) * iconGap
        // 单窗：图标中心坐在卡左下角内（ref/card1-zoom 实测：水平探出
        // 30% 图标宽、垂直仅 26%——第 29 轮的 60% 把卡底量错了）；合并卡：
        // 胶囊底探出约 15% 胶囊高
        readonly property real outX: listForm
            ? Math.max(3, Math.round(pillW * 0.12)) : iconSize * 0.30
        width: listForm ? pillW : rowWidth
        height: listForm ? pillH : iconSize
        // ⚠️ 水平定位用 x 而非 left/right 锚点切换（同 cards 列的坑）：
        // 锚点对在 side 翻转瞬间同时定义会拆掉 width 绑定
        anchors.bottom: parent.bottom
        anchors.bottomMargin: listForm
            ? -Math.max(3, Math.round(pillH * 0.15)) : -iconSize * 0.26
        x: card.rightSide ? parent.width - width + outX : -outX

        // ── 单窗形态：一枚大图标（图标资源自带 squircle 底）──
        MouseArea {
            id: iconRowHover
            anchors.fill: parent
            anchors.margins: -3
            visible: !iconRow.listForm
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        Repeater {
            model: iconRow.listForm ? 0 : iconRow.visibleCount
            MouseArea {
                id: iconSlot
                required property int index
                // ⚠️ 必须显式排 x：Repeater 子项默认全叠在 x=0——"并列"
                // 变成一摞（实测：合并卡图标叠成一枚）
                x: index * (iconRow.iconSize + iconRow.iconGap)
                width: iconRow.iconSize
                height: iconRow.iconSize
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: card.iconActivated(card.iconPairs[index].id)
                Rectangle {
                    anchors.fill: parent
                    radius: width * 0.24   // iPadOS app 图标 squircle 比例
                    // 参考无底板:图标本体直接压卡。悬停显底板做点击反馈
                    color: iconSlot.containsMouse
                        ? Qt.rgba(0.16, 0.20, 0.30, 0.98)
                        : "transparent"
                    border.width: iconSlot.containsMouse ? 1 : 0
                    border.color: Qt.rgba(0.62, 0.80, 1.0, 0.85)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    IconImage {
                        anchors.fill: parent
                        anchors.margins: parent.width * 0.08
                        source: card.iconPairs[index]?.icon || card.iconSource || ""
                        asynchronous: false
                    }
                }
            }
        }

        // 单窗形态的 "+N"（iconPairs 超过可见上限时）
        Text {
            visible: !iconRow.listForm && card.iconPairs.length > iconRow.visibleCount
            anchors.verticalCenter: parent.verticalCenter
            x: card.rightSide ? -width - 5 : parent.width + 5
            text: "+" + (card.iconPairs.length - iconRow.visibleCount)
            color: Qt.rgba(1, 1, 1, 0.65)
            font { pixelSize: 10; weight: Font.DemiBold }
        }

        // ── 合并卡形态：白色圆角胶囊 + 逐窗行 ──
        // 投影（参考有一层很浅的落影；两层叠出柔和边）
        Rectangle {
            visible: iconRow.listForm
            x: -1; y: 2
            width: parent.width + 2; height: parent.height + 2
            radius: iconRow.pillRadius + 1
            color: Qt.rgba(0, 0, 0, 0.10)
        }
        Rectangle {
            id: pillBg
            visible: iconRow.listForm
            anchors.fill: parent
            radius: iconRow.pillRadius
            // ref/c2 实测底色 (251,252,251)
            color: "#fbfcfb"
        }

        Repeater {
            model: iconRow.listForm ? iconRow.displayRows : 0
            MouseArea {
                id: pillRow
                required property int index
                readonly property bool more:
                    iconRow.overflow && index === iconRow.displayRows - 1
                readonly property var row:
                    (!more && index < card.windowRows.length)
                        ? card.windowRows[index] : null
                x: 0
                y: iconRow.pillPadY + index * iconRow.pillRowH
                width: iconRow.pillW
                height: iconRow.pillRowH
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (row && row.id) card.iconActivated(row.id)
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: Math.max(2, Math.round(iconRow.pillRadius * 0.35))
                    color: pillRow.containsMouse
                        ? Qt.rgba(0, 0, 0, 0.06) : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                IconImage {
                    visible: !pillRow.more
                    x: iconRow.pillPadX
                    anchors.verticalCenter: parent.verticalCenter
                    width: iconRow.pillIcon
                    height: iconRow.pillIcon
                    source: pillRow.row ? (pillRow.row.icon || "") : ""
                    asynchronous: false
                }
                Text {
                    x: iconRow.pillPadX + iconRow.pillIcon
                        + Math.max(2, Math.round(iconRow.pillW * 0.08))
                    anchors.verticalCenter: parent.verticalCenter
                    width: iconRow.pillW - x - iconRow.pillPadX
                    text: pillRow.more
                        ? "+" + (card.windowRows.length
                                 - (iconRow.displayRows - 1))
                        : (pillRow.row ? pillRow.row.title : "")
                    // iOS 次要文字灰；参考标签很小、被模糊糊住
                    color: "#8e8e93"
                    font.pixelSize: Math.max(6,
                        Math.round(iconRow.pillW * 0.14))
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }
    }
}
