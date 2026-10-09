pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Basic
import QtQuick.Controls
import QtQuick.Effects
import ListenFree.Native 1.0

Item {
    id: panel
    signal matchRequested

    property var lyrics: []
    property int currentLineIndex: -1
    property string alignmentMode: "Center"
    property string currentLinePosition: "Center"
    property int fontSize: 28
    property bool darkMode: AppTheme.darkMode
    property bool reducedMotion: false
    property bool artworkBackground: false
    property bool springEnabled: true
    property bool scaleEnabled: true
    property bool inactiveBlurEnabled: true
    property bool showTranslation: true
    property bool showRomanization: false
    property string secondaryLineOrder: "TranslationFirst"
    property real positionMs: 0
    property bool playing: false
    property real renderPositionMs: 0
    property real lastPositionUpdate: 0
    property bool pendingSeekSync: false
    onPositionMsChanged: {
        const now = Date.now()
        const discontinuity = lastPositionUpdate > 0
            && Math.abs(positionMs-renderPositionMs) > Math.max(650, now-lastPositionUpdate+350)
        if (discontinuity)
            notifySeek()
        else seeking = false
        // Ordinary decoder updates can arrive behind the displayed frame.
        // Correct their phase in the frame loop instead of rewinding each word.
        if (pendingSeekSync || !playing || !animationActive || reducedMotion || lastPositionUpdate === 0)
            renderPositionMs = positionMs
        pendingSeekSync = false
        lastPositionUpdate = now
    }
    function resetPlayhead() {
        renderPositionMs = positionMs
        lastPositionUpdate = Date.now()
    }
    function advancePlayhead(deltaMs) {
        const expected = positionMs + Math.max(0, Math.min(250, Date.now()-lastPositionUpdate))
        const correction = Math.max(-deltaMs*.2, Math.min(deltaMs*.2, expected-renderPositionMs-deltaMs))
        // Bound extrapolation if playback stalls, without introducing a reverse
        // step when the most recent decoder sample is late.
        renderPositionMs = Math.max(renderPositionMs,
            Math.min(positionMs+250, renderPositionMs+deltaMs+correction))
    }
    onPlayingChanged: resetPlayhead()
    onAnimationActiveChanged: resetPlayhead()
    onReducedMotionChanged: resetPlayhead()
    FrameAnimation {
        running: panel.playing && panel.animationActive && !panel.reducedMotion && panel.wordTimingEnabled && panel.lineCount > 0
        onTriggered: panel.advancePlayhead(frameTime * 1000)
    }
    property bool wordTimingEnabled: true
    property bool karaokeEnabled: true
    readonly property color foreground: artworkBackground ? "#fffdfd" : (darkMode ? "#f5f5f7" : "#161618")
    property bool animationActive: visible
    property bool seeking: false
    property bool browsing: false
    property bool touchBrowsing: false
    property int focusLineIndex: currentLineIndex
    property string layoutReason: "geometry"
    property string pendingLayoutReason: "geometry"
    property bool applyingLayout: false
    property int layoutBatch: 0
    property int firstVisibleLine: 0
    readonly property real lineSpringStiffness: {
        const row = lineData(focusLineIndex)
        const before = lineData(focusLineIndex - 1)
        if (row && focusLineIndex === lineCount-1 && (row.words || []).length > 0
            && renderPositionMs >= Number(row.words[row.words.length-1].endMs)) return 140
        if (seeking || !row || !before) return 90
        const gap = lineTime(row) - lineTime(before)
        if (gap <= 0) return 90
        return 170 + 50 * Math.pow(1 - (Math.max(100, Math.min(800, gap)) - 100) / 700, .2)
    }
    readonly property real lineSpringDamping: lineSpringStiffness === 90 ? 15 : lineSpringStiffness === 140 ? 22 : 2.2 * Math.sqrt(lineSpringStiffness)
    readonly property bool menuOpen: lyricsMenu.opened
    readonly property int lineCount: lyrics
                                     ? (lyrics.count !== undefined ? lyrics.count : (lyrics.length || 0))
                                     : 0

    signal seekRequested(real timeMs, int index)
    signal displaySettingRequested(string key, var value)

    clip: true
    implicitWidth: 620
    implicitHeight: 580

    LyricTextMetrics { id: wordMetrics }

    function lineData(index) {
        if (index < 0 || index >= lineCount) return null
        return lyrics.get !== undefined ? lyrics.get(index) : lyrics[index]
    }
    function lineTime(line) {
        return Number(line.timeMs !== undefined ? line.timeMs : line.timestampMs || 0)
    }
    function notifySeek() {
        seeking = true
        pendingSeekSync = true
        resetPlayhead()
        browsing = false
        touchBrowsing = false
        returnToFocus.stop()
        wheelSettled.stop()
        focusLineIndex = currentLineIndex
        scheduleLayout("seek")
    }
    function suspendFollow(touch) {
        if (!browsing) focusLineIndex = currentLineIndex
        browsing = true
        touchBrowsing = touchBrowsing || touch
        returnToFocus.stop()
        layoutReason = touch ? "continuous" : "wheel"
        ++layoutBatch
    }
    function resumeFollow() {
        if (lyricList.moving) return
        browsing = false
        touchBrowsing = false
        focusLineIndex = currentLineIndex
        scheduleLayout("playback")
    }
    function scheduleLayout(reason) {
        // Layout notifications can follow a line change in the same event
        // turn. Keep that playback/seek intent when coalescing the pass.
        if (pendingLayoutReason !== "seek"
                && (reason !== "geometry" || pendingLayoutReason !== "playback"))
            pendingLayoutReason = reason
        Qt.callLater(flushLayout)
    }
    function flushLayout() {
        const reason = pendingLayoutReason
        pendingLayoutReason = "geometry"
        positionCurrentLine(reason)
    }

    function normalizedAlignment() {
        return String(alignmentMode || "Center").toLowerCase()
    }

    function textAlignment() {
        const value = normalizedAlignment()
        if (value === "left")
            return Text.AlignLeft
        if (value === "right")
            return Text.AlignRight
        return Text.AlignHCenter
    }

    function currentLineAnchorRatio() {
        const value = String(currentLinePosition || "Center").toLowerCase()
        if (value === "upper")
            return 0.30
        if (value === "lower")
            return 0.70
        return 0.50
    }

    function positionCurrentLine(reason) {
        if (currentLineIndex < 0 || currentLineIndex >= lineCount || lyricList.height <= 0)
            return

        if (lyricList.dragging || lyricList.flicking || browsing) return
        // Adjacent changes retain the existing delegates and their spring velocity.
        // Distant seeks create a new visible range immediately.
        const distant = !lyricList.itemAtIndex(currentLineIndex)
        applyingLayout = true
        if (distant)
            lyricList.positionViewAtIndex(currentLineIndex, ListView.Center)
        lyricList.forceLayout()
            const row = lyricList.itemAtIndex(currentLineIndex)
            if (!row) { applyingLayout = false; return }
            // AMLL delays accumulate from the first intersecting row, rather
            // than an arbitrary number of rows above the active line.
            let first = currentLineIndex
            const children = lyricList.contentItem.children
            const target = row.y + row.height / 2 - lyricList.height * currentLineAnchorRatio()
            for (let i = 0; i < children.length; ++i) {
                const candidate = children[i]
                if (candidate.index !== undefined && candidate.y-target + candidate.height >= 0)
                    first = Math.min(first, candidate.index)
            }
            firstVisibleLine = Math.max(0, first)
            layoutReason = distant ? "snap" : (reason || "geometry")
            ++layoutBatch
            lyricList.contentY = target
            applyingLayout = false
            for (let j = 0; j < children.length; ++j)
                if (children[j].retarget !== undefined) children[j].retarget()
    }

    function rowDelay(index) {
        let delay = 0
        let step = 50
        for (let i = firstVisibleLine; i < index; ++i) {
            delay += step
            if (i >= focusLineIndex) step /= 1.05
        }
        return delay
    }

    // Sample the upstream CSS curves once. Playback only interpolates this
    // small table; word timing itself remains linear in media time.
    function makeCurve(x1, y1, x2, y2) {
        const values = []
        for (let i = 0; i <= 32; ++i) {
            const x = i / 32
            let lo = 0, hi = 1, t = x
            for (let j = 0; j < 12; ++j) {
                const u = 1-t
                if (3*u*u*t*x1 + 3*u*t*t*x2 + t*t*t < x) lo = t
                else hi = t
                t = (lo+hi)/2
            }
            values.push(i === 0 ? 0 : i === 32 ? 1
                        : 3*(1-t)*(1-t)*t*y1 + 3*(1-t)*t*t*y2 + t*t*t)
        }
        return values
    }
    function sampleCurve(values, progress) {
        const x = Math.max(0, Math.min(1, progress)) * 32
        const i = Math.min(31, Math.floor(x))
        return values[i] + (values[i+1]-values[i])*(x-i)
    }
    readonly property var liftCurve: makeCurve(0, 0, .58, 1)
    readonly property var emphasisRise: makeCurve(.2, .4, .58, 1)
    readonly property var emphasisFall: makeCurve(.3, 0, .58, 1)

    function setAlignment(mode) {
        alignmentMode = mode
        displaySettingRequested("alignment", mode)
    }

    function setCurrentLinePosition(position) {
        currentLinePosition = position
        displaySettingRequested("currentLinePosition", position)
    }

    function setFontSize(size) {
        fontSize = Math.max(16, Math.min(48, Math.round(size)))
        displaySettingRequested("fontSize", fontSize)
    }

    function openMenuAt(rowItem, pointX, pointY) {
        const point = rowItem.mapToItem(panel, pointX, pointY)
        lyricsMenu.x = Math.max(8, Math.min(point.x, panel.width - lyricsMenu.width - 8))
        lyricsMenu.y = Math.max(8, Math.min(point.y, panel.height - lyricsMenu.height - 8))
        lyricsMenu.open()
    }

    function openSettingsMenu() {
        lyricsMenu.x = Math.max(8, (panel.width - lyricsMenu.width) / 2)
        lyricsMenu.y = Math.max(8, (panel.height - lyricsMenu.height) / 2)
        lyricsMenu.open()
    }

    onCurrentLineIndexChanged: {
        if (!browsing) focusLineIndex = currentLineIndex
        if (!seeking) scheduleLayout("playback")
        else scheduleLayout("seek")
    }
    onLyricsChanged: { browsing = false; touchBrowsing = false; returnToFocus.stop(); scheduleLayout("geometry") }
    onCurrentLinePositionChanged: scheduleLayout("geometry")
    onFontSizeChanged: scheduleLayout("geometry")
    onWidthChanged: scheduleLayout("geometry")
    onHeightChanged: scheduleLayout("geometry")
    onShowTranslationChanged: scheduleLayout("geometry")
    onShowRomanizationChanged: scheduleLayout("geometry")
    Component.onCompleted: scheduleLayout("geometry")

    Timer { id: returnToFocus; interval: 5000; onTriggered: panel.resumeFollow() }
    Timer { id: wheelSettled; interval: 150; onTriggered: returnToFocus.restart() }

    // Match the existing lyric-preview wheel handling. Explicitly consume the
    // event so the full-page modal barrier cannot swallow the ListView scroll.
    MouseArea {
        parent: lyricList
        anchors.fill: parent
        z: 2
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            lyricList.cancelFlick()
            panel.suspendFollow(wheel.pixelDelta.y !== 0)
            wheelSettled.restart()
            const delta = wheel.pixelDelta.y || wheel.angleDelta.y / 120 * 64
            const top = lyricList.originY - lyricList.topMargin
            const bottom = lyricList.originY + Math.max(0, lyricList.contentHeight - lyricList.height + lyricList.bottomMargin)
            lyricList.contentY = Math.max(top, Math.min(bottom, lyricList.contentY - delta))
            wheel.accepted = true
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: point => panel.openMenuAt(panel, point.position.x, point.position.y)
    }

    ListView {
        id: lyricList
        objectName: "lyricList"
        anchors.fill: parent
        clip: true
        model: panel.lyrics || []
        spacing: 18
        topMargin: height * .5
        bottomMargin: height * .5
        cacheBuffer: Math.max(0, height)
        onMovementStarted: { wheelSettled.stop(); panel.suspendFollow(true) }
        onMovementEnded: returnToFocus.restart()
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        currentIndex: panel.currentLineIndex
        highlightMoveDuration: panel.reducedMotion ? 0 : AppTheme.duration(240)
        highlightResizeDuration: panel.reducedMotion ? 0 : AppTheme.duration(180)

        delegate: Rectangle {
            id: lyricRow
            objectName: "lyricRow" + index

            required property int index
            required property var modelData
            readonly property bool current: index === panel.focusLineIndex
            readonly property bool timed: panel.wordTimingEnabled && (modelData.words || []).length > 0
            property real focusAmount: current ? 1 : 0
            Behavior on focusAmount { NumberAnimation { duration: panel.reducedMotion || !panel.animationActive ? 0 : (lyricRow.current ? 300 : 450); easing.type: Easing.BezierSpline; easing.bezierCurve: [.25,.1,.25,1,1,1] } }
            readonly property string primaryText: String(modelData.text || modelData.en || "")
            readonly property string secondaryText: {
                const translation = panel.showTranslation ? String(modelData.translation || modelData.zh || "") : ""
                const romanization = panel.showRomanization ? String(modelData.romanization || "") : ""
                return (panel.secondaryLineOrder === "RomanizationFirst" ? [romanization, translation] : [translation, romanization]).filter(Boolean).join("\n")
            }
            readonly property real targetY: y - lyricList.contentY
            readonly property real renderedY: rowSpring.value
            readonly property bool nearViewport: targetY > -height && targetY < lyricList.height + height
            // Inactive cached rows have no moving word effects. Avoid evaluating
            // every token and grapheme on every frame of the global playhead.
            readonly property real animationPositionMs: focusAmount > 0 && nearViewport && panel.animationActive
                ? panel.renderPositionMs : 0
            property bool ready: false
            property int targetBatch: -1
            function commitTarget() {
                rowSpring.retarget(targetY, panel.lineSpringStiffness, panel.lineSpringDamping, .9)
            }
            function retarget() {
                if (panel.applyingLayout) return
                if (!ready || !panel.animationActive || panel.reducedMotion || !panel.springEnabled || lyricList.moving || !nearViewport || panel.layoutReason !== "playback") {
                    stagger.stop(); commitTarget()
                } else if (targetBatch !== panel.layoutBatch) {
                    targetBatch = panel.layoutBatch
                    stagger.restart()
                } else if (!stagger.running) commitTarget()
            }
            onTargetYChanged: retarget()
            // Scrolling creates cached delegates while forceLayout/contentY is
            // being updated. Their initial height must not enqueue a second
            // geometry pass that cancels every row's playback stagger.
            onHeightChanged: if (ready && !panel.applyingLayout) panel.scheduleLayout("geometry")
            Component.onCompleted: { commitTarget(); ready = true }
            Connections {
                target: panel
                function onAnimationActiveChanged() { lyricRow.retarget() }
                function onReducedMotionChanged() { lyricRow.retarget() }
                function onSpringEnabledChanged() { lyricRow.retarget() }
            }
            Timer {
                id: stagger
                interval: panel.rowDelay(lyricRow.index)
                onTriggered: lyricRow.commitTarget()
            }
            SpringValue {
                id: rowSpring
                enabled: lyricRow.ready && panel.animationActive && panel.springEnabled && !panel.reducedMotion && panel.layoutReason !== "snap" && panel.layoutReason !== "continuous" && !lyricList.moving && lyricRow.nearViewport
            }
            transform: Translate { y: rowSpring.value - lyricRow.targetY }

            width: ListView.view.width
            height: Math.max(72, primaryBlock.implicitHeight
                             + (translationLine.visible ? translationLine.implicitHeight + 7 : 0) + 28)
            radius: 16
            clip: false
            color: rowHover.hovered ? "#12ffffff" : "transparent"
            property real focusOpacity: timed && panel.karaokeEnabled ? (current ? .85 : 1) : (current ? 1 : .2)
            Behavior on focusOpacity { NumberAnimation { duration: panel.reducedMotion || !panel.animationActive ? 0 : 400 } }
            // Fade whole lines before the viewport clips their glyphs. This is
            // ordinary scene-graph opacity, with no full-panel mask texture.
            readonly property real edgeOpacity: Math.max(0, Math.min(1,
                (Math.min(renderedY+height*.5, lyricList.height-renderedY-height*.5)+height*.2)
                    / Math.max(1,panel.fontSize*2.5)))
            opacity: focusOpacity * edgeOpacity
            property real blurAmount: !panel.inactiveBlurEnabled || current || panel.touchBrowsing ? 0
                : Math.min(5, (Math.abs(index-panel.focusLineIndex)+(index<panel.focusLineIndex?2:1))
                           * (panel.width <= 1024 ? .8 : 1)) / 8
            Behavior on blurAmount {
                NumberAnimation {
                    // Resolve the incoming line before a short first syllable
                    // finishes; outgoing lines can recede more gradually.
                    duration: panel.reducedMotion || !panel.animationActive ? 0 : (lyricRow.current ? 180 : 400)
                    easing.type: lyricRow.current ? Easing.OutCubic : Easing.Linear
                }
            }
            // Retain lyric/layout state while immersed, but release the hidden
            // row's offscreen blur textures. They return before it is painted.
            layer.enabled: panel.visible && panel.animationActive && panel.inactiveBlurEnabled && nearViewport && blurAmount > .001
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: lyricRow.blurAmount
                blurMax: 8
            }

            Behavior on color { ColorAnimation { duration: AppTheme.duration(100) } }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7

                Item {
                    id: primaryBlock
                    objectName: "lyricPrimary" + lyricRow.index
                    width: parent.width
                    implicitHeight: Math.max(primaryLine.implicitHeight,wordFlow.visible?wordFlow.implicitHeight:0)
                    height: implicitHeight
                    scale: scaleSpring.value / 100
                    transformOrigin: panel.normalizedAlignment()==="left"?Item.Left:panel.normalizedAlignment()==="right"?Item.Right:Item.Center
                    SpringValue {
                        id: scaleSpring
                        target: !panel.scaleEnabled || !panel.playing || lyricRow.current ? 100 : 97
                        enabled: panel.animationActive && !panel.reducedMotion && lyricRow.nearViewport
                        mass: 2; stiffness: 100; damping: 25
                    }
                    Text {
                        id: primaryLine
                        width: parent.width
                        text: String(lyricRow.modelData.text || lyricRow.modelData.en || "")
                        textFormat: Text.PlainText; color: panel.foreground
                        visible: !wordFlow.visible
                        font.family: AppTheme.fontFamily; font.pixelSize: panel.fontSize; font.weight: Font.DemiBold
                        horizontalAlignment: panel.textAlignment(); wrapMode: Text.WordWrap
                    }
                    TextMetrics { id: lineMetrics; font: primaryLine.font; text: primaryLine.text }
                    Flow {
                        id: wordFlow
                        objectName: "lyricWordFlow" + lyricRow.index
                        visible: lyricRow.timed
                        readonly property var tokens: visible ? wordMetrics.prepare(lyricRow.modelData.words, primaryLine.font) : []
                        width: Math.min(primaryBlock.width,Math.ceil(lineMetrics.advanceWidth)+1)
                        x: panel.normalizedAlignment()==="left"?0:panel.normalizedAlignment()==="right"?primaryBlock.width-width:(primaryBlock.width-width)/2
                        spacing: 0
                        // Flow wraps tokens but always starts each visual line
                        // at x=0. Align each wrapped line without changing its
                        // layout advances or feeding transforms back into Flow.
                        function alignWrappedLines() {
                            const lines = {}
                            for (let i=0;i<children.length;++i) {
                                const word = children[i]
                                if (word.lineOffsetX === undefined) continue
                                const key = String(word.y)
                                if (!lines[key]) lines[key] = {end:0, words:[]}
                                lines[key].end = Math.max(lines[key].end, word.x+word.width)
                                lines[key].words.push(word)
                            }
                            const alignment = panel.normalizedAlignment()
                            for (const key in lines) {
                                const line = lines[key]
                                const free = Math.max(0,width-line.end)
                                const offset = alignment === "left" ? 0 : alignment === "right" ? free : free*.5
                                for (let i=0;i<line.words.length;++i) line.words[i].lineOffsetX = offset
                            }
                        }
                        onPositioningComplete: alignWrappedLines()
                        Connections {
                            target: panel
                            function onAlignmentModeChanged() { wordFlow.alignWrappedLines() }
                        }
                        Repeater {
                            model: wordFlow.tokens
                            delegate: Item {
                                id: wordItem
                                required property var modelData
                                required property int index
                                property real lineOffsetX: 0
                                transform: Translate { x: wordItem.lineOffsetX }
                                // Read the QVariant-backed timing/shape maps when
                                // their data changes, not in every animation sample.
                                readonly property real startTimeMs: Number(modelData.startMs)
                                readonly property real endTimeMs: Number(modelData.endMs)
                                readonly property real progress: Math.max(0,Math.min(1,(lyricRow.animationPositionMs-startTimeMs)/wordDuration))
                                // AMLL's base word float rises once and holds;
                                // only scale/glow use the short accent release.
                                // A settled progress stays constant, so completed
                                // words do not keep sampling the lift curve.
                                readonly property real floatProgress: Math.max(0, Math.min(1,
                                    (lyricRow.animationPositionMs-startTimeMs) / Math.max(1000, wordDuration)))
                                readonly property real wordDuration: Math.max(1, endTimeMs-startTimeMs)
                                readonly property bool hasInk: Number(modelData.charCount) > 0
                                readonly property bool emphasized: Boolean(modelData.emphasized)
                                readonly property real emphasisAmount: Number(modelData.emphasisAmount)
                                readonly property real emphasisDuration: Number(modelData.emphasisDuration)
                                readonly property real emphasisStart: Number(modelData.emphasisStart)
                                readonly property real emphasisGlow: Number(modelData.emphasisGlow)
                                readonly property real groupCount: Math.max(1,Number(modelData.groupCount))
                                readonly property real accentEnvelope: accentActive ? panel.sampleCurve(panel.liftCurve,
                                    (lyricRow.animationPositionMs-startTimeMs)/Math.min(250, Math.max(80, wordDuration)))
                                    * (1-panel.sampleCurve(panel.emphasisFall, (lyricRow.animationPositionMs-endTimeMs)/320)) : 0
                                readonly property bool accentActive: hasInk && !emphasized && lyricRow.animationPositionMs >= startTimeMs
                                    && lyricRow.animationPositionMs < endTimeMs+320
                                // Allocate only for the actual emphasis envelope.
                                // The base float owns vertical motion; a second,
                                // early sine lift makes unsung glyphs rise too soon.
                                readonly property real emphasisEnd: emphasisStart
                                    + emphasisDuration/2.5/groupCount
                                        * Math.max(0,Number(modelData.charOffset)+Number(modelData.charCount)-1)
                                    + emphasisDuration
                                readonly property bool emphasisActive: emphasized && lyricRow.animationPositionMs >= emphasisStart
                                    && lyricRow.animationPositionMs < emphasisEnd
                                readonly property real sungAlpha: .2 + .8 * lyricRow.focusAmount
                                readonly property real unsungAlpha: .2 + .2 * lyricRow.focusAmount
                                readonly property real lift: !panel.reducedMotion && panel.animationActive
                                    ? -panel.fontSize * .05 * panel.sampleCurve(panel.liftCurve, floatProgress)
                                      * lyricRow.focusAmount : 0
                                width: Math.min(wordFlow.width,Number(modelData.leadingSpace)+wordGlyph.implicitWidth+Number(modelData.trailingSpace))
                                height: Math.max(wordGlyph.implicitHeight,panel.fontSize)
                                // Reserve the original advance. Animated glyphs never relayout the Flow.
                                Text {
                                    id: wordGlyph
                                    objectName: "lyricWord" + lyricRow.index + "/" + wordItem.index
                                    text: String(wordItem.modelData.displayText); textFormat: Text.PlainText
                                    color: panel.foreground; font: primaryLine.font
                                    // Loader teardown releases ShaderEffectSource's
                                    // hideSource reference a frame later. Own the
                                    // native/effect switch here so no frame loses ink.
                                    // Qt still captures an invisible sourceItem.
                                    visible: !emphasisLoader.active
                                    x: Number(wordItem.modelData.leadingSpace)
                                    y: wordItem.lift
                                    opacity: layer.enabled || emphasisLoader.active ? 1 : (panel.karaokeEnabled
                                        ? (wordItem.progress <= 0 ? wordItem.unsungAlpha : wordItem.sungAlpha) : 1)
                                    // Only a partially sung token needs a mask texture.
                                    // Before/after its interval, native text has the same pixels.
                                    layer.enabled: wordItem.hasInk && !emphasisLoader.active && lyricRow.focusAmount > 0 && lyricRow.nearViewport
                                        && panel.karaokeEnabled && panel.animationActive && wordItem.progress > 0 && wordItem.progress < 1
                                    layer.effect: ShaderEffect {
                                        property var source
                                        property real progress: wordItem.progress
                                        property real edgeWidth: panel.fontSize*.25/Math.max(1,wordGlyph.implicitWidth)
                                        property real sungAlpha: wordItem.sungAlpha
                                        property real unsungAlpha: wordItem.unsungAlpha
                                        fragmentShader: "qrc:/shaders/lyric-word.frag.qsb"
                                    }
                                }
                                Loader {
                                    id: emphasisLoader
                                    x: wordGlyph.x
                                    width: wordGlyph.implicitWidth; height: wordGlyph.implicitHeight
                                    active: (wordItem.emphasisActive || wordItem.accentActive) && lyricRow.focusAmount > 0 && lyricRow.nearViewport
                                            && panel.animationActive && !panel.reducedMotion
                                    sourceComponent: Item {
                                        id: emphasisBody
                                        // One static shaped texture for the token, shared by all glyph quads.
                                        ShaderEffectSource {
                                            id: shapedWord
                                            objectName: (wordItem.emphasized ? "lyricEmphasisTexture" : "lyricAccentTexture")
                                                + lyricRow.index + "/" + wordItem.index
                                            sourceItem: wordGlyph
                                            hideSource: false
                                            live: false
                                            visible: false
                                            sourceRect: Qt.rect(0, 0, wordGlyph.implicitWidth, wordGlyph.implicitHeight)
                                            Component.onCompleted: scheduleUpdate()
                                            Connections {
                                                target: wordGlyph
                                                function onTextChanged() { shapedWord.scheduleUpdate() }
                                                function onFontChanged() { shapedWord.scheduleUpdate() }
                                                function onColorChanged() { shapedWord.scheduleUpdate() }
                                            }
                                        }
                                        Repeater {
                                            // Short tokens need one quad, regardless of their character count.
                                            // Split glyphs only for the staggered, sustained-note animation.
                                            model: wordItem.emphasized ? wordItem.modelData.glyphs
                                                : [{left: 0, right: wordGlyph.implicitWidth, ordinal: 0}]
                                            delegate: ShaderEffect {
                                                id: glyphSlice
                                                required property var modelData
                                                required property int index
                                                objectName: (wordItem.emphasized ? "lyricGrapheme" : "lyricAccent")
                                                    + lyricRow.index + "/" + wordItem.index + "/" + index
                                                readonly property real glyphOrdinal: Number(modelData.ordinal)
                                                readonly property real ordinal: Number(wordItem.modelData.charOffset) + Math.max(0, Number(modelData.ordinal))
                                                readonly property real start: wordItem.emphasisStart + wordItem.emphasisDuration / 2.5
                                                    / wordItem.groupCount * ordinal
                                                readonly property real time: (lyricRow.animationPositionMs-start) / wordItem.emphasisDuration
                                                readonly property real envelope: !wordItem.emphasized ? wordItem.accentEnvelope * lyricRow.focusAmount
                                                    : glyphOrdinal < 0 ? 0 : (time < .5
                                                    ? panel.sampleCurve(panel.emphasisRise, time*2) : 1-panel.sampleCurve(panel.emphasisFall, time*2-1)) * lyricRow.focusAmount
                                                // Keep split-glyph geometry stable at its hard
                                                // internal clip edges. Whole-token accents can
                                                // fit the kernel, with one raster pixel of slack.
                                                readonly property real padding: wordItem.emphasized ? Math.ceil(panel.fontSize*.36)
                                                    : Math.ceil(Math.max(.5, glowRadius)*Math.SQRT2) + 1
                                                readonly property real glyphLeft: Number(modelData.left)
                                                readonly property real glyphRight: Number(modelData.right)
                                                width: Math.max(1, glyphRight-glyphLeft) + padding*2
                                                height: wordGlyph.implicitHeight + padding*2
                                                x: glyphLeft-padding - (wordItem.emphasized ? panel.fontSize*.03*wordItem.emphasisAmount*envelope
                                                   * (wordItem.groupCount/2-ordinal) : 0)
                                                y: -padding + wordItem.lift - (wordItem.emphasized ? panel.fontSize*.025*wordItem.emphasisAmount*envelope : 0)
                                                scale: 1 + (wordItem.emphasized ? .1*wordItem.emphasisAmount : .015)*envelope
                                                // Symmetric padding must not change the
                                                // visible glyph's expansion or add lift.
                                                transformOrigin: Item.Center
                                                property var source: shapedWord
                                                property vector4d sourceRect: Qt.vector4d(glyphLeft-padding, -padding, width, height)
                                                property vector4d clipRect: Qt.vector4d(glyphLeft, 0, glyphRight, wordGlyph.implicitHeight)
                                                property vector2d sourceSize: Qt.vector2d(Math.max(1,wordGlyph.implicitWidth), Math.max(1,wordGlyph.implicitHeight))
                                                property color glowColor: panel.foreground
                                                // A weaker note reduces halo energy without
                                                // collapsing its soft falloff to a hard edge.
                                                property real glowRadius: (wordItem.emphasized ? Math.max(.16, Math.min(.3, wordItem.emphasisGlow*.3)) : .09)*panel.fontSize
                                                property real glowAlpha: (wordItem.emphasized ? wordItem.emphasisGlow : .16)*envelope
                                                property real progress: wordItem.progress
                                                property real edgeWidth: panel.fontSize*.25/Math.max(1,wordGlyph.implicitWidth)
                                                property real sungAlpha: panel.karaokeEnabled ? wordItem.sungAlpha : 1
                                                property real unsungAlpha: panel.karaokeEnabled ? wordItem.unsungAlpha : 1
                                                fragmentShader: "qrc:/shaders/lyric-grapheme.frag.qsb"
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    id: translationLine
                    opacity: lyricRow.timed && panel.karaokeEnabled ? .22 + .58 * lyricRow.focusAmount : 1
                    visible: text.length > 0
                    width: parent.width
                    text: lyricRow.secondaryText
                    color: panel.artworkBackground
                           ? "#f0ebed"
                           : lyricRow.current ? AppTheme.textSecondary : AppTheme.textMuted
                    font.family: AppTheme.fontFamily
                    font.pixelSize: Math.max(12, Math.round(panel.fontSize * 0.54))
                    font.weight: Font.Normal
                    horizontalAlignment: panel.textAlignment()
                    wrapMode: Text.WordWrap
                }
            }

            HoverHandler { id: rowHover }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: function(mouse) {
                    panel.notifySeek()
                    panel.seekRequested(Number(lyricRow.modelData.timeMs || lyricRow.modelData.timestampMs || lyricRow.modelData.time || 0), lyricRow.index)
                }
            }

        }

        ScrollBar.vertical: Basic.ScrollBar {
            policy: ScrollBar.AlwaysOff
            visible: false; width: 0
        }
    }

    Text {
        anchors.centerIn: parent
        visible: panel.lineCount === 0
        text: qsTr("暂无歌词")
        color: AppTheme.textSecondary
        font.family: AppTheme.fontFamily
        font.pixelSize: 14
    }

    Popup {
        id: lyricsMenu
        objectName: "lyricsContextMenu"
        onOpened: AppTheme.presentPopup(lyricsMenu)
        parent: panel
        width: Math.max(0, Math.min(330, panel.width - 16))
        height: Math.max(0, Math.min(252, panel.height - 16))
        padding: 0
        modal: true
        dim: false
        focus: true
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        transformOrigin: Item.TopLeft

        background: GlassSurface {
            blockInput: true
            cornerRadius: 18
            tint: AppTheme.cardStrong
            edgeColor: AppTheme.border
            shadowOpacity: .30
        }

        contentItem: Flickable {
            id: menuViewport
            clip: true
            contentWidth: width
            contentHeight: menuColumn.height + 28
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            Column {
                id: menuColumn
                x: 14
                y: 14
                width: Math.max(0, menuViewport.width - 28)
                spacing: 8

                UiButton { objectName: "lyricsContextMatchButton"; width: parent.width; label: qsTr("歌词匹配"); onClicked: { lyricsMenu.close();panel.matchRequested() } }

                Text {
                    text: qsTr("歌词显示")
                    color: AppTheme.textPrimary
                    font.family: AppTheme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                MenuSection {
                    title: qsTr("歌词对齐方式")
                    options: [
                        { label: qsTr("居左"), value: "Left" },
                        { label: qsTr("居中"), value: "Center" },
                        { label: qsTr("居右"), value: "Right" }
                    ]
                    value: panel.alignmentMode
                    onSelected: function(value) { panel.setAlignment(value) }
                }

                MenuSection {
                    title: qsTr("当前行位置")
                    options: [
                        { label: qsTr("偏上"), value: "Upper" },
                        { label: qsTr("居中"), value: "Center" },
                        { label: qsTr("偏下"), value: "Lower" }
                    ]
                    value: panel.currentLinePosition
                    onSelected: function(value) { panel.setCurrentLinePosition(value) }
                }

                Item {
                    width: parent.width
                    height: 46

                    Text {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        text: qsTr("字体大小  ") + panel.fontSize + " px"
                        color: AppTheme.textSecondary
                        font.family: AppTheme.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }

                    Row {
                        id: fontButtons
                        width: parent.width
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        spacing: 6

                        MenuButton {
                            width: (fontButtons.width - fontButtons.spacing * 2) / 3
                            label: qsTr("重置")
                            onClicked: panel.setFontSize(28)
                        }
                        MenuButton {
                            width: (fontButtons.width - fontButtons.spacing * 2) / 3
                            label: "A↓"
                            enabled: panel.fontSize > 16
                            onClicked: panel.setFontSize(panel.fontSize - 2)
                        }
                        MenuButton {
                            width: (fontButtons.width - fontButtons.spacing * 2) / 3
                            label: "A↑"
                            enabled: panel.fontSize < 48
                            onClicked: panel.setFontSize(panel.fontSize + 2)
                        }
                    }
                }
            }
        }

        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: panel.reducedMotion ? 0 : AppTheme.duration(170); easing.type: Easing.OutCubic }
                NumberAnimation { property: "scale"; from: .97; to: 1; duration: panel.reducedMotion ? 0 : AppTheme.duration(190); easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: panel.reducedMotion ? 0 : AppTheme.duration(120); easing.type: Easing.InCubic }
                NumberAnimation { property: "scale"; from: 1; to: .97; duration: panel.reducedMotion ? 0 : AppTheme.duration(120); easing.type: Easing.InCubic }
            }
        }
    }

    component MenuSection: Item {
        id: section

        required property string title
        required property var options
        required property string value
        signal selected(string value)

        width: parent ? parent.width : 0
        height: 58

        Text {
            anchors.left: parent.left
            anchors.top: parent.top
            text: section.title
            color: AppTheme.textSecondary
            font.family: AppTheme.fontFamily
            font.pixelSize: 10
            font.weight: Font.Medium
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 34
            radius: 10
            color: panel.darkMode ? "#26303942" : "#8af1f2f3"
            border.width: 1
            border.color: AppTheme.border

            Row {
                anchors.fill: parent
                anchors.margins: 2
                spacing: 2

                Repeater {
                    model: section.options

                    delegate: Rectangle {
                        id: segment
                        objectName: "lyricOption" + String(modelData.value)
                        required property int index
                        required property var modelData
                        readonly property bool selected: String(section.value).toLowerCase()
                                                         === String(modelData.value).toLowerCase()

                        width: (parent.width - parent.spacing * (section.options.length - 1))
                               / section.options.length
                        height: parent.height
                        radius: 8
                        color: selected ? (panel.darkMode ? "#53606a" : "#dfe1e3")
                                        : segmentHover.hovered ? (panel.darkMode ? "#35414b" : "#eaebed")
                                                               : "transparent"

                        Behavior on color { ColorAnimation { duration: AppTheme.duration(90) } }

                        Text {
                            anchors.centerIn: parent
                            text: segment.modelData.label
                            color: AppTheme.textPrimary
                            font.family: AppTheme.fontFamily
                            font.pixelSize: 11
                            font.weight: segment.selected ? Font.DemiBold : Font.Normal
                        }

                        HoverHandler { id: segmentHover }
                        MouseArea { anchors.fill: parent; onClicked: section.selected(String(segment.modelData.value)) }
                    }
                }
            }
        }
    }

    component MenuButton: Rectangle {
        id: menuButton

        required property string label
        signal clicked

        height: 28
        radius: 9
        color: buttonHover.hovered && enabled ? AppTheme.controlHover : AppTheme.control
        border.width: 1
        border.color: AppTheme.border
        opacity: enabled ? 1 : .42
        scale: buttonTap.pressed ? .96 : 1

        Behavior on color { ColorAnimation { duration: AppTheme.duration(90) } }
        Behavior on scale { NumberAnimation { duration: AppTheme.duration(80); easing.type: Easing.OutCubic } }

        Text {
            anchors.centerIn: parent
            text: menuButton.label
            color: AppTheme.textPrimary
            font.family: AppTheme.fontFamily
            font.pixelSize: 11
            font.weight: Font.Medium
        }

        HoverHandler { id: buttonHover; enabled: menuButton.enabled }
        TapHandler {
            id: buttonTap
            enabled: menuButton.enabled
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: menuButton.clicked()
        }
    }
}
