import QtQuick
import "KosKineticScrollPhysics.mjs" as Physics

// Shared mouse-wheel and pixel-input policy. Place inside a Flickable;
// its content item hosts the low-priority catcher behind interactive children.
// Pixel input tracks fingers directly with bounded speed gain and no added coast.
// FrameAnimation integrates only rendered frames and sleeps when settled.
Item {
    id: root

    // Existing explicit flickable bindings remain supported. New consumers can
    // declare KosKineticScroll {} inside a view, or provide target: scrollView.
    property var target: null
    property Flickable flickable: _findView(target || parent)

    function _findView(item) {
        if (item instanceof Flickable)
            return item;
        if (item && item.contentItem instanceof Flickable)
            return item.contentItem;
        let ancestor = item;
        while (ancestor) {
            if (ancestor instanceof Flickable)
                return ancestor;
            ancestor = ancestor.parent;
        }
        return null;
    }

    // Whether wheel events with a horizontal component -- or Shift+wheel, which
    // is how a mouse asks for the other axis -- also reach contentX. Views that
    // cannot scroll sideways ignore this by themselves (their range collapses
    // to a single value).
    visible: flickable ? flickable.visible : false
    enabled: flickable ? flickable.enabled : true

    property bool horizontal: true
    property bool reducedMotion: AppTheme.reduceMotion
    property bool _animating: false
    onReducedMotionChanged: if (reducedMotion) _release()
    onVisibleChanged: if (!visible) _release()
    onEnabledChanged: if (!enabled) _release()

    // The view's scroll ranges. Recomputed when its content changes size, which
    // is what keeps a filtered list from resting outside its new bounds.
    readonly property var verticalRange: Physics.bounds(flickable ? flickable.contentHeight : 0,
        flickable ? flickable.height : 0,
        flickable ? flickable.topMargin : 0,
        flickable ? flickable.bottomMargin : 0,
        flickable ? flickable.originY : 0)
    readonly property var horizontalRange: Physics.bounds(flickable ? flickable.contentWidth : 0,
        flickable ? flickable.width : 0,
        flickable ? flickable.leftMargin : 0,
        flickable ? flickable.rightMargin : 0,
        flickable ? flickable.originX : 0)

    // Read ancestor coordinates in QML so viewport movement updates the
    // binding; mapToItem alone would not track those property dependencies.
    readonly property point _viewportOrigin: _originFor(parent)

    function _originFor(target) {
        if (!flickable)
            return Qt.point(0, 0);
        if (target === flickable.contentItem)
            return Qt.point(flickable.contentX, flickable.contentY);
        let x = 0;
        let y = 0;
        let item = flickable;
        while (item && item !== target && item !== null) {
            x += item.x;
            y += item.y;
            item = item.parent;
        }
        return Qt.point(x, y);
    }

    x: _viewportOrigin.x
    y: _viewportOrigin.y
    width: flickable ? flickable.width : 0
    height: flickable ? flickable.height : 0
    // Input belongs to controls and nested views before this fallback.
    z: -1

    // Motion state, one axis each: where the view is drawn, where the wheel
    // asked for it to be, and how fast it is travelling between the two.
    property var _vertical: Physics.axis()
    property var _horizontal: Physics.axis()
    // Last value this component WROTE to the view. A different one means
    // somebody else moved the view (a restore, positionViewAtIndex) and the
    // animation has to stand down instead of dragging it back.
    property real _writtenY: NaN
    property real _writtenX: NaN
    // When the previous wheel event of this gesture arrived: the gap to it is
    // the only speed signal a wheel gives, and a gap wider than the momentum
    // window means a new gesture rather than a continuing one.
    property double _lastWheel: 0
    property string _inputMode: ""

    function _adopt() {
        if (!flickable)
            return;
        Physics.reset(_vertical, flickable.contentY);
        Physics.reset(_horizontal, flickable.contentX);
        _writtenY = flickable.contentY;
        _writtenX = flickable.contentX;
    }

    // Give the view back, with no motion left in either axis.
    function _release() {
        _animating = false;
        _handTimer.stop();
        _lastWheel = 0;
        _inputMode = "";
        _adopt();
    }

    // Angle events schedule frame-driven motion. Pixel events follow fingers
    // directly, with shared velocity estimation and gain limits.
    function _onWheel(angleX, angleY, pixelX, pixelY, shiftHeld) {
        if (!flickable || !enabled || !visible || (!flickable.interactive && !_scrollViewWrapped))
            return false;
        if (reducedMotion) {
            _release();
            return false;
        }
        const mode = pixelX !== 0 || pixelY !== 0 ? "pixel" : "wheel";
        if (_inputMode !== mode) {
            _release();
            _inputMode = mode;
        } else if (!_animating && mode === "wheel") {
            _adopt();
        } else if (flickable.contentY !== _writtenY || flickable.contentX !== _writtenX) {
            // A scrollbar/programmatic move cancels both gesture estimates.
            _release();
            _inputMode = mode;
        }

        const canScrollVertically = verticalRange.max > verticalRange.min;
        const canScrollSideways = root.horizontal && horizontalRange.max > horizontalRange.min;
        let vertical = mode === "pixel" ? { delta: pixelY, continuous: true }
            : Physics.wheelStep(angleY, 0);
        let horizontal = mode === "pixel" ? { delta: pixelX, continuous: true }
            : Physics.wheelStep(angleX, 0);
        if (shiftHeld && horizontal.delta === 0) {
            // Shift+wheel is how a mouse asks for the other axis.
            horizontal = vertical;
            vertical = { delta: 0, continuous: vertical.continuous };
        } else if (vertical.delta !== 0 && horizontal.delta === 0
                && !canScrollVertically && canScrollSideways) {
            // A view that can only travel sideways takes the plain wheel:
            // with nothing to scroll vertically, refusing the event would just park it.
            horizontal = vertical;
            vertical = { delta: 0, continuous: vertical.continuous };
        }
        if (!root.horizontal && vertical.delta === 0 && horizontal.delta !== 0) {
            vertical = horizontal;
            horizontal = { delta: 0, continuous: false };
        }
        const movesVertical = vertical.delta !== 0 && canScrollVertically
            && (Physics.clamp(_vertical.target - vertical.delta, verticalRange.min, verticalRange.max) !== _vertical.target
                || (_animating && _vertical.position !== _vertical.target));
        const movesHorizontal = horizontal.delta !== 0 && canScrollSideways
            && (Physics.clamp(_horizontal.target - horizontal.delta, horizontalRange.min, horizontalRange.max) !== _horizontal.target
                || (_animating && _horizontal.position !== _horizontal.target));
        if (!movesVertical && !movesHorizontal)
            return false;
        // How fast this gesture is running: KWin and high-resolution wheels
        // deliver a notch as a ramp of events, and the gap between them is the
        // only speed signal there is.
        const now = Date.now();
        const dtSince = _lastWheel === 0 ? Infinity : (now - _lastWheel) / 1000;
        _lastWheel = now;
        _handTimer.restart();
        // Deltas already include the user's natural-scroll setting.
        if (mode === "pixel") {
            if (movesVertical) {
                flickable.contentY = Physics.pushPixels(_vertical,
                    -vertical.delta, verticalRange, dtSince);
                _vertical.position = _vertical.target = _writtenY = flickable.contentY;
            }
            if (movesHorizontal) {
                flickable.contentX = Physics.pushPixels(_horizontal,
                    -horizontal.delta, horizontalRange, dtSince);
                _horizontal.position = _horizontal.target = _writtenX = flickable.contentX;
            }
            // Pixel input is direct: don't inject another momentum tail on gaps.
            _animating = false;
        } else {
            if (movesHorizontal)
                Physics.push(_horizontal, -horizontal.delta, horizontalRange, dtSince);
            if (movesVertical)
                Physics.push(_vertical, -vertical.delta, verticalRange, dtSince);
            _animating = true;
        }
        return true;
    }

    // Angle input gets a short coast; pixel streams never get a second tail.
    function _handStopped() {
        _lastWheel = 0;
        if (_inputMode === "pixel") {
            _release();
            return;
        }
        const vertical = Physics.release(_vertical, verticalRange);
        const horizontal = root.horizontal
            ? Physics.release(_horizontal, horizontalRange) : false;
        if (vertical || horizontal) {
            _animating = true;
        }
    }

    // One frame of whichever phase the axis is in: the spring following the
    // wheel, or the glide it was released into.
    function _tick(frameSeconds) {
        if (!enabled || !flickable || flickable.moving || (!flickable.interactive && !_scrollViewWrapped)) {
            _release();
            return;
        }
        // Somebody else moved the view mid-flight (a restore, a
        // positionViewAtIndex, a programmatic scroll): yield at once instead of
        // dragging the view back to what this component last wrote.
        if (flickable.contentY !== _writtenY
                || (root.horizontal && flickable.contentX !== _writtenX)) {
            _release();
            return;
        }

        // Integrate once per rendered frame, never once per input event.
        const dt = Math.min(Math.max(0, frameSeconds), Physics.CONFIG.maxFrameTime);
        if (dt <= 0) return;

        const verticalMoving = Physics.advance(_vertical, dt, verticalRange);
        const horizontalMoving = root.horizontal
            ? Physics.advance(_horizontal, dt, horizontalRange)
            : false;
        // Write every frame, including the one that settles: an axis snaps onto
        // its target on that frame, and a frame that is not written leaves the
        // view resting a fraction of a pixel short of where it landed.
        flickable.contentY = _vertical.position;
        _writtenY = flickable.contentY; // pixelAligned views may round a write.
        if (root.horizontal) {
            flickable.contentX = _horizontal.position;
            _writtenX = flickable.contentX;
        }
        if (!verticalMoving && !horizontalMoving) {
            _animating = false;
        }
    }

    readonly property bool _scrollViewWrapped: _scrollContainer(flickable) !== null
    property bool _completed: false
    on_ScrollViewWrappedChanged: _attach()

    function _scrollContainer(view) {
        let ancestor = view ? view.parent : null;
        while (ancestor) {
            if (ancestor.contentItem === view)
                return ancestor;
            ancestor = ancestor.parent;
        }
        return null;
    }

    function _attach() {
        if (!_completed || !flickable)
            return;
        if (_scrollViewWrapped) {
            // Keep visual children out of ScrollView's implicit sizing.
            let host = flickable;
            while (host.parent)
                host = host.parent;
            parent = host;
        } else {
            parent = flickable.contentItem;
        }
    }

    Component.onCompleted: {
        _completed = true;
        _attach();
        _adopt();
    }
    onFlickableChanged: {
        if (_completed) {
            _release();
            _attach();
        } else {
            _adopt();
        }
    }

    // ScrollView handles wheel delivery itself. A nonvisual handler on its
    // Flickable shares the policy without disturbing implicit content sizing.
    Binding {
        target: root._scrollContainer(root.flickable)
        property: "wheelEnabled"
        value: false
        when: root._scrollViewWrapped && root.enabled && root.visible && !root.reducedMotion
        restoreMode: Binding.RestoreBindingOrValue
    }

    WheelHandler {
        parent: root.flickable || root
        target: null
        enabled: root._scrollViewWrapped && root.enabled && root.visible && !root.reducedMotion
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        blocking: true
        onWheel: function(event) {
            if (event.modifiers & Qt.ControlModifier) {
                event.accepted = false;
                return;
            }
            event.accepted = root._onWheel(event.angleDelta.x, event.angleDelta.y,
                event.pixelDelta.x, event.pixelDelta.y,
                (event.modifiers & Qt.ShiftModifier) !== 0);
        }
    }

    FrameAnimation {
        running: root._animating && root.visible && root.enabled
        onTriggered: root._tick(frameTime)
    }

    // Quiet gap: release an angle gesture or forget the pixel speed estimate.
    Timer {
        id: _handTimer
        interval: Math.round(Physics.CONFIG.releaseDelay * 1000)
        onTriggered: root._handStopped()
    }

    // MouseArea provides the established shell wheel path. NoButton preserves
    // clicks/drags; low stacking priority preserves child wheel handlers.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        // interactive is part of the contract: Qt's own wheel handling is off
        // for a non-interactive view, and a view that opted out of scrolling
        // must not start scrolling because inertia was added.
        enabled: !root._scrollViewWrapped && root.enabled && root.flickable !== null && root.flickable.interactive
        onWheel: function (event) {
            if (event.modifiers & Qt.ControlModifier) {
                event.accepted = false;
                return;
            }
            event.accepted = root._onWheel(event.angleDelta.x, event.angleDelta.y,
                event.pixelDelta.x, event.pixelDelta.y,
                (event.modifiers & Qt.ShiftModifier) !== 0);
        }
    }
}
