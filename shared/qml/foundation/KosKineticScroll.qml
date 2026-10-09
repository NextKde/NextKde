import QtQuick
import "KosKineticScrollPhysics.mjs" as Physics

// Opt-in mouse-wheel inertia for ordinary lists. Place inside a Flickable;
// its content item hosts the low-priority catcher behind interactive children.
// Pixel scrolling stays native so trackpads keep their existing inertia.
// FrameAnimation integrates only rendered frames and sleeps when settled.
Item {
    id: root

    // The view to scroll. Required and explicit: `parent` inside a Flickable is
    // the content item, not the view, so inferring it from the tree would bind
    // to the wrong geometry.
    required property Flickable flickable

    // `enabled` is Item's own, deliberately not redeclared: false both takes the
    // catcher out of the input chain and disables its wheel handler below, which
    // is the whole escape hatch -- set it to hand the wheel back to the
    // Flickable untouched. (Redeclaring it would only add Qt's "overrides a
    // member of the base object" warning.)

    // Whether wheel events with a horizontal component -- or Shift+wheel, which
    // is how a mouse asks for the other axis -- also reach contentX. Views that
    // cannot scroll sideways ignore this by themselves (their range collapses
    // to a single value).
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
        flickable ? flickable.bottomMargin : 0)
    readonly property var horizontalRange: Physics.bounds(flickable ? flickable.contentWidth : 0,
        flickable ? flickable.width : 0,
        flickable ? flickable.leftMargin : 0,
        flickable ? flickable.rightMargin : 0)

    // The viewport, in whatever coordinates this component's parent uses.
    //
    // The usual placement is inside the view, where that is content coordinates:
    // a Flickable's children live in its content, and only (contentX, contentY)
    // maps to the visible top-left corner. It also covers being declared
    // *beside* the view, which is the only option for a ScrollView (its
    // contentItem is sized from the content it holds, so an extra child there
    // collapses contentWidth/contentHeight to -1 and the view stops scrolling
    // at all -- measured, see tst_kinetic_scroll.qml).
    //
    // The walk is written out instead of calling mapToItem, which does the same
    // arithmetic in C++: a binding only re-evaluates for the QML properties it
    // read while evaluating, and a C++ call registers none. With mapToItem the
    // catcher keeps the position it had when the view was created -- the moment
    // anything scrolls it slides out of the viewport with the content, and the
    // wheel goes back to the un-smoothed built-in handler.
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
        _adopt();
    }

    // A wheel event updates the target and gesture speed. The next rendered
    // frame moves the view; event frequency does not advance simulation time.
    function _onWheel(angleX, angleY, pixelX, pixelY, shiftHeld) {
        if (!flickable || !enabled || !visible || !flickable.interactive)
            return false;
        // Pixel events already carry continuous-device/OS inertia. Leave
        // these, Ctrl gestures and reduced motion to the native controls.
        if (pixelX !== 0 || pixelY !== 0 || reducedMotion) {
            _release();
            return false;
        }
        // The newest operation owns the view: a glide is cancelled outright and
        // the input continues from where the view actually is, so a reversal
        // bites on this very event.
        // A gesture starting on a standing view re-reads it first (it may have
        // been scrolled natively since); one that interrupts a gesture in flight
        // continues from where the view actually is, and push() is what cancels
        // the glide and any reversal.
        if (!_animating)
            _adopt();

        const canScrollVertically = verticalRange.max > verticalRange.min;
        const canScrollSideways = root.horizontal && horizontalRange.max > horizontalRange.min;
        let vertical = Physics.wheelStep(angleY, pixelY);
        let horizontal = Physics.wheelStep(angleX, pixelX);
        if (shiftHeld && horizontal.delta === 0) {
            // Shift+wheel is how a mouse asks for the other axis.
            horizontal = vertical;
            vertical = { delta: 0, continuous: vertical.continuous };
        } else if (vertical.delta !== 0 && horizontal.delta === 0
                && !canScrollVertically && canScrollSideways) {
            // A view that can only travel sideways takes the plain wheel:
            // with nothing to
            // scroll vertically, refusing the event would just park it.
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
        // Qt's sign: a wheel turned away from the user reports a positive
        // angleDelta and scrolls *towards the start* of the content.
        if (horizontal.delta !== 0)
            Physics.push(_horizontal, -horizontal.delta, horizontalRange, dtSince);
        if (vertical.delta !== 0)
            Physics.push(_vertical, -vertical.delta, verticalRange, dtSince);
        // Changing the target schedules rendering; input never advances physics.
        _animating = true;
        return true;
    }

    // The hand stopped turning the wheel: hand the gesture's speed to the glide
    // and start pumping frames for it.
    function _handStopped() {
        _lastWheel = 0;
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
        if (!enabled || !flickable || flickable.moving || !flickable.interactive) {
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
        flickable.contentY = _writtenY = _vertical.position;
        if (root.horizontal)
            flickable.contentX = _writtenX = _horizontal.position;
        if (!verticalMoving && !horizontalMoving) {
            _animating = false;
        }
    }

    Component.onCompleted: _adopt()
    onFlickableChanged: _adopt()

    FrameAnimation {
        running: root._animating && root.visible && root.enabled
        onTriggered: root._tick(frameTime)
    }

    // The hand stopped: no wheel event for CONFIG.releaseDelay means the gesture
    // is over, and the speed it was carrying becomes a glide.
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
        enabled: root.enabled && root.flickable !== null && root.flickable.interactive
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
