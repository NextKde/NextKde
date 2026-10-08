import QtQuick
import "KosKineticScrollPhysics.mjs" as Physics

// Wheel scrolling with browser-style inertia, for any Flickable-shaped view.
//
// Declared *inside* the view it drives:
//
//     ListView {
//         id: resultView
//         contentHeight: ...
//         KineticScroll { flickable: resultView }
//     }
//
// The component claims the wheel ahead of the Flickable's own handling. While
// the wheel turns it moves the view *itself* -- no animation between events, so
// the view is exactly the input and never lags the hand. When the events stop,
// the speed the gesture was carrying is released as a short glide; the next
// event cancels it outright, so a reversal bites on the next notch instead of a
// few hundred pixels later. All of that arithmetic lives in
// KosKineticScrollPhysics.mjs, where it is replayed in node.
//
// The host view keeps its geometry, its model and its delegates exactly as they
// were -- and it keeps its native drag and flick, because the component only
// runs while the view is standing still.
//
// Two properties of the placement matter:
//
//   * It has to be a child of the view, and it positions itself from the
//     view's contentX/contentY so that it covers the *viewport* rather than the
//     content: a Flickable's children live in content coordinates, and only
//     (contentX, contentY) maps to the visible top-left corner.
//   * It must be left unanchored and uncontested. Nothing about the view's
//     scrolling changes shape here, so an outright `enabled: false` is the way
//     to keep the wheel for a view that wants its own handling.
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
    // Above the delegates and below any popup the host floats over the view.
    z: 1000

    // Motion state, one axis each: where the view is drawn, where the wheel
    // asked for it to be, and how fast it is travelling between the two.
    property var _vertical: Physics.axis()
    property var _horizontal: Physics.axis()
    // Last value this component WROTE to the view. A different one means
    // somebody else moved the view (a restore, positionViewAtIndex) and the
    // animation has to stand down instead of dragging it back.
    property real _writtenY: NaN
    property real _writtenX: NaN
    property double _lastTick: 0
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
        _ticker.stop();
        _lastTick = 0;
        _adopt();
    }

    // A wheel event: move the view now, and remember how fast the gesture is
    // going, so the glide knows what to inherit when the events stop.
    function _onWheel(angleX, angleY, pixelX, pixelY, shiftHeld) {
        if (!flickable)
            return;
        // The newest operation owns the view: a glide is cancelled outright and
        // the input continues from where the view actually is, so a reversal
        // bites on this very event.
        // A gesture starting on a standing view re-reads it first (it may have
        // been scrolled natively since); one that interrupts a gesture in flight
        // continues from where the view actually is, and push() is what cancels
        // the glide and any reversal.
        if (!_ticker.running)
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
            // A view that can only travel sideways (the wallpaper strip, a
            // horizontal film strip) takes the plain wheel: with nothing to
            // scroll vertically, refusing the event would just park it.
            horizontal = vertical;
            vertical = { delta: 0, continuous: vertical.continuous };
        }
        // How fast this gesture is running: KWin and high-resolution wheels
        // deliver a notch as a ramp of events, and the gap between them is the
        // only speed signal there is.
        const now = Date.now();
        const dtSince = _lastWheel === 0 ? Infinity : (now - _lastWheel) / 1000;
        _lastWheel = now;
        _handTimer.restart();
        // A view that opted out of sideways travel takes such an event on its
        // vertical axis rather than dropping it (Shift+wheel on a list).
        if (!root.horizontal && vertical.delta === 0 && horizontal.delta !== 0) {
            vertical = horizontal;
            horizontal = { delta: 0, continuous: false };
        }
        // Qt's sign: a wheel turned away from the user reports a positive
        // angleDelta and scrolls *towards the start* of the content.
        if (horizontal.delta !== 0)
            Physics.push(_horizontal, -horizontal.delta, horizontalRange, dtSince);
        if (vertical.delta !== 0)
            Physics.push(_vertical, -vertical.delta, verticalRange, dtSince);
        // Start the spring on this event rather than one interval later, so the
        // motion begins on the frame the wheel was turned.
        _lastTick = 0;
        _ticker.restart();
        _tick();
    }

    // The hand stopped turning the wheel: hand the gesture's speed to the glide
    // and start pumping frames for it.
    function _handStopped() {
        const vertical = Physics.release(_vertical, verticalRange);
        const horizontal = root.horizontal
            ? Physics.release(_horizontal, horizontalRange) : false;
        if (vertical || horizontal) {
            _lastTick = 0;
            _ticker.start();
        }
    }

    // One frame of whichever phase the axis is in: the spring following the
    // wheel, or the glide it was released into.
    function _tick() {
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

        // See frameDt: measured, capped, and one nominal frame for the tick that
        // runs on the wheel event itself.
        const now = Date.now();
        const dt = Physics.frameDt(now, _lastTick);
        _lastTick = now;
        if (dt <= 0)
            return;

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
            _ticker.stop();
            _lastTick = 0;
        }
    }

    Component.onCompleted: _adopt()
    onFlickableChanged: _adopt()

    // 16ms is a sampling interval, not a frame promise: the motion is driven by
    // measured elapsed time (above), so a late tick moves further instead of
    // running slow. FrameAnimation would tie this to the render loop, but it
    // does not advance at all where no frames are produced (offscreen loads,
    // compositor stalls), which is exactly where a frozen scroll would look
    // like a hung shell.
    Timer {
        id: _ticker
        interval: 16
        repeat: true
        onTriggered: root._tick()
    }

    // The hand stopped: no wheel event for CONFIG.releaseDelay means the gesture
    // is over, and the speed it was carrying becomes a glide.
    Timer {
        id: _handTimer
        interval: Math.round(Physics.CONFIG.releaseDelay * 1000)
        onTriggered: root._handStopped()
    }

    // A MouseArea rather than a WheelHandler, deliberately.
    //
    // A WheelHandler silently receives nothing on the shell's Wayland surfaces:
    // measured on a live session, every WheelHandler in this tree -- one on each
    // level of the launcher's delivery chain -- stayed silent while the grid
    // scrolled under the same wheel, and the only sensor that ever reported the
    // event was a MouseArea's onWheel. (The shell's own fullscreen pager wheel
    // receiver is written the same way.) acceptedButtons stays NoButton so this
    // claims the wheel and nothing else: presses, clicks and hover all continue
    // to the content underneath.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        // interactive is part of the contract: Qt's own wheel handling is off
        // for a non-interactive view, and a view that opted out of scrolling
        // must not start scrolling because inertia was added.
        enabled: root.enabled && root.flickable !== null && root.flickable.interactive
        onWheel: function (event) {
            root._onWheel(event.angleDelta.x, event.angleDelta.y,
                event.pixelDelta.x, event.pixelDelta.y,
                (event.modifiers & Qt.ShiftModifier) !== 0);
            event.accepted = true;
        }
    }
}
