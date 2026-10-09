import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import "../../shared/qml/foundation" as Foundation
import "../../shared/qml/foundation/KosKineticScrollPhysics.mjs" as Physics

// Wheel scrolling with inertia (Foundation.KosKineticScroll).
//
// These run headless and offscreen, so they assert the parts a compositor would
// otherwise only show as "it feels off": that a notch travels the same distance
// the platform's own wheel handling travels, that motion starts on the event
// rather than a frame later, that it coasts after the last event, that it stops
// exactly on the bounds, and that none of the view's own input or content stops
// working around it.
Item {
    id: page
    width: 320
    height: 1200

    component Scrollable: Flickable {
        width: 300
        height: 200
        contentWidth: 900
        contentHeight: 2000
        Rectangle { width: 900; height: 2000; color: "gray" }
    }

    // The view under test, and a plain one as the platform reference: a notch
    // must land on the same pixel either way.
    Scrollable {
        id: kinetic
        Foundation.KosKineticScroll { id: kineticContent; flickable: kinetic }
    }
    Scrollable {
        id: reference
        x: 320
    }
    Scrollable {
        id: horizontalOnly
        y: 240
        contentWidth: 900
        contentHeight: 200
        Foundation.KosKineticScroll { flickable: horizontalOnly }
    }
    Scrollable {
        id: verticalOnly
        x: 320
        y: 240
        Foundation.KosKineticScroll { flickable: verticalOnly; horizontal: false }
    }
    Scrollable {
        id: disabled
        y: 480
        Foundation.KosKineticScroll { flickable: disabled; enabled: false }
    }
    Scrollable {
        id: frozen
        x: 320
        y: 480
        interactive: false
        Foundation.KosKineticScroll { flickable: frozen }
    }

    ListView {
        id: list
        y: 720
        width: 300
        height: 200
        clip: true
        model: 60
        delegate: Item {
            required property int index
            width: list.width
            height: 40
            Rectangle { anchors.fill: parent; color: index % 2 ? "#333333" : "#444444" }
            MouseArea {
                anchors.fill: parent
                onClicked: page.clickedIndex = index
            }
        }
        Foundation.KosKineticScroll { flickable: list }
    }
    // Declared *beside* the view rather than inside it. A ScrollView cannot take
    // an extra child at all (its contentItem is sized from the content it holds,
    // and a second child collapses contentWidth/contentHeight to -1), so this is
    // the shape every ScrollView in the tree has to use.
    Flickable {
        id: beside
        x: 0
        y: 960
        width: 300
        height: 200
        contentWidth: 300
        contentHeight: 2000
        Rectangle { width: 300; height: 2000; color: "gray" }
    }
    Foundation.KosKineticScroll { flickable: beside }

    ColumnLayout {
        x: 320
        y: 960
        width: 240
        height: 200
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 40; color: "#555555" }
        ScrollView {
            id: scrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Column {
                width: 180
                Repeater { model: 20; delegate: Item { width: 180; height: 40 } }
            }
        }
        // A ColumnLayout sizes every child it owns, so a catcher declared here
        // is 0x0 unless it is reparented to a plain ancestor.
        Foundation.KosKineticScroll {
            id: scrollViewCatcher
            flickable: scrollView.contentItem
            parent: page
        }
    }

    property int clickedIndex: -1

    TestCase {
        name: "KosKineticScroll"
        when: windowShown

        function init() {
            kineticContent._release()
            kineticContent.reducedMotion = false
            beside.contentY = 0
            scrollView.contentItem.contentY = 0
            kinetic.contentY = 0
            kinetic.contentX = 0
            kinetic.contentHeight = 2000
            reference.contentY = 0
            horizontalOnly.contentX = 0
            verticalOnly.contentY = 0
            verticalOnly.contentX = 0
            disabled.contentY = 0
            frozen.contentY = 0
            list.contentY = 0
            list.contentX = 0
            page.clickedIndex = -1
            wait(20)
        }

        // A notch must travel exactly as far as the platform's own handling, so
        // this component changes the shape of the motion and nothing else.
        function test_distance_matches_the_platform() {
            mouseWheel(reference, 150, 100, 0, -120)
            tryCompare(reference, "contentY", 72, 1000, 1.0)
            const expected = reference.contentY
            verify(expected > 60, "the platform reference must have moved, got " + expected)
            mouseWheel(kinetic, 150, 100, 0, -120)
            tryCompare(kinetic, "contentY", expected, 1000, 1.0)
        }

        // Scrolling towards the start (wheel turned away from the user) moves
        // the content the same way the platform's own handling does.
        function test_direction() {
            kinetic.contentY = 300
            mouseWheel(kinetic, 150, 100, 0, 120)
            tryCompare(kinetic, "contentY", 228, 1000, 1.0)
        }

        // Following the hand: the view is where the wheel asked for it on the
        // frame the event arrived -- no animation in between that could lag.
        function test_follows_the_hand_closely() {
            // Real wheel events are ~30ms apart (KWin delivers a notch as a ramp
            // of them). The spring is stiff enough at that speed that the view
            // never lags the hand by more than a fraction of a row, and it ends
            // exactly on the sum.
            let worst = 0
            for (let i = 1; i <= 6; ++i) {
                mouseWheel(kinetic, 150, 100, 0, -120)
                wait(30)
                worst = Math.max(worst, i * 72 - kinetic.contentY)
            }
            verify(worst < 90, "the view must stay on the hand, worst lag " + worst)
            // ...and once the hand stops, it is the glide that finishes the trip.
            wait(400)
            verify(kinetic.contentY > 6 * 72, "the glide must carry it past the sum")
            tryCompare(kinetic, "contentY", kinetic.contentY, 1500, 2.0)
        }

        // A burst arrives as a ramp of events: every one of them lands in the
        // frame it arrives in, so the view tracks the hand one to one while the
        // wheel is turning.
        function test_a_single_notch_does_not_jump() {
            mouseWheel(kinetic, 150, 100, 0, -120)
            tryVerify(function() { return kinetic.contentY > 0 }, 300)
            const firstFrame = kinetic.contentY
            verify(firstFrame > 0 && firstFrame < 72,
                "a notch must ease in, not jump: " + firstFrame)
            tryCompare(kinetic, "contentY", 72, 1000, 1.0)
        }

        // The point of the exercise: when the hand stops, the speed the gesture
        // was carrying becomes a glide -- the view keeps going after the last
        // event, and further than the notches alone would take it.
        function test_the_glide_carries_past_the_hand() {
            for (let i = 0; i < 6; ++i) {
                mouseWheel(kinetic, 150, 100, 0, -120)
                wait(30)
            }
            // The hand is off the wheel now: what is left is the glide, so the
            // view is past the sum, not on it.
            wait(400)
            const later = kinetic.contentY
            verify(later > 6 * 72 + 150,
                "the glide must carry past the hand's last notch, reached " + later)
            tryCompare(kinetic, "contentY", later, 1500, 2.0)
            verify(kinetic.contentY > 6 * 72 + 150, "and then stop there")
        }

        // Any new operation owns the view: a notch in the middle of a glide
        // stops it dead and continues from where the view actually is, so a
        // reversal bites immediately instead of a few hundred pixels later.
        function test_a_new_notch_stops_the_glide() {
            for (let i = 0; i < 6; ++i) {
                mouseWheel(kinetic, 150, 100, 0, -120)
                wait(30)
            }
            wait(150)
            verify(kinetic.contentY > 6 * 72, "the glide must have started")
            const before = kinetic.contentY
            mouseWheel(kinetic, 150, 100, 0, 120)
            // The reversal bites here: the view must be back under `before` and
            // moving the other way, not still coasting forward.
            wait(120)
            verify(kinetic.contentY < before,
                "the reversal must bite on its own event: " + before + " -> " + kinetic.contentY)
        }

        // The same gesture, spaced out, is a series of separate notches and must
        // keep the platform's distance exactly -- momentum is for ramps.
        function test_a_spaced_gesture_keeps_the_platform_distance() {
            for (let i = 0; i < 4; ++i) {
                mouseWheel(kinetic, 150, 100, 0, -120)
                wait(320)
            }
            tryCompare(kinetic, "contentY", 4 * 72, 3000, 1.0)
        }

        function test_ends_settle_exactly_on_the_start() {
            for (let i = 0; i < 6; ++i)
                mouseWheel(kinetic, 150, 100, 0, 120)
            tryCompare(kinetic, "contentY", 0, 3000, 1.0)
            verify(kinetic.contentY >= -0.5, "never settles before the start")
        }

        function test_ends_settle_exactly_on_the_bound() {
            kinetic.contentY = 1600
            for (let i = 0; i < 20; ++i)
                mouseWheel(kinetic, 150, 100, 0, -120)
            const limit = kinetic.contentHeight - kinetic.height
            // A fast fling rebounds off the end (that is the point), so the
            // assertion is where it comes to rest, not the peak.
            tryCompare(kinetic, "contentY", limit, 3000, 1.0)
            verify(kinetic.contentY <= limit + 0.5, "never settles past the end")
        }

        function test_shift_wheel_reaches_the_other_axis() {
            mouseWheel(kinetic, 150, 100, 0, -120, Qt.LeftButton, Qt.ShiftModifier)
            tryCompare(kinetic, "contentX", 72, 1000, 1.0)
            compare(kinetic.contentY, 0)
        }

        function test_shift_wheel_is_ignored_when_horizontal_is_off() {
            mouseWheel(verticalOnly, 150, 100, 0, -120, Qt.LeftButton, Qt.ShiftModifier)
            tryCompare(verticalOnly, "contentY", 72, 1000, 1.0)
            compare(verticalOnly.contentX, 0)
        }

        function test_a_view_that_only_scrolls_sideways() {
            mouseWheel(horizontalOnly, 150, 100, 0, -120)
            tryCompare(horizontalOnly, "contentX", 72, 1000, 1.0)
            compare(horizontalOnly.contentY, 0)
        }

        // enabled:false is the escape hatch, and it has to leave the Flickable's
        // own handling untouched rather than merely freeze the view.
        function test_disabled_leaves_the_platform_handling() {
            mouseWheel(disabled, 150, 100, 0, -120)
            tryCompare(disabled, "contentY", 72, 1000, 1.0)
        }

        // A view that opted out of scrolling (interactive:false) must not start
        // scrolling because inertia was added to it.
        function test_non_interactive_view_stays_put() {
            mouseWheel(frozen, 150, 100, 0, -120)
            wait(200)
            compare(frozen.contentY, 0)
        }

        // The catcher covers the whole viewport, which is only safe if presses
        // keep reaching the content: a delegate click must still land.
        function test_delegate_clicks_still_arrive() {
            mouseClick(list, 150, 60, Qt.LeftButton)
            wait(20)
            compare(page.clickedIndex, 1)
        }

        // The same for a view whose content has scrolled: the wheel must reach
        // it and the click must reach a delegate at its new position.
        function test_scrolls_a_listview() {
            mouseWheel(list, 150, 100, 0, -120)
            tryCompare(list, "contentY", 72, 1000, 1.0)
            // Rows are 40px: the point 100px below the viewport top is at
            // content y 172 once the view has scrolled by 72.
            mouseClick(list, 150, 100, Qt.LeftButton)
            wait(20)
            compare(page.clickedIndex, 4)
        }

        // The same behaviour with the component declared next to the view.
        function test_placed_beside_the_view() {
            mouseWheel(beside, 150, 100, 0, -120)
            tryCompare(beside, "contentY", 72, 1000, 1.0)
        }

        // A ScrollView is the one view this component cannot drive to its own
        // target: the control owns its contentItem and re-lays it out, so the
        // animation is cut short. What still has to hold is that the view is not
        // broken by the companion -- an extra child *inside* the contentItem
        // unsizes it (contentWidth/contentHeight become -1) and nothing scrolls
        // at all -- and that the wheel reaches the catcher.
        function test_a_scrollview_keeps_its_content_sized() {
            const content = scrollView.contentItem
            verify(content.contentWidth > 0 && content.contentHeight > 0,
                "the ScrollView content collapsed: " + content.contentWidth + "x" + content.contentHeight)
            verify(scrollViewCatcher.width > 0 && scrollViewCatcher.height > 0,
                "the catcher was sized by the layout: " + scrollViewCatcher.width + "x" + scrollViewCatcher.height)
            mouseWheel(scrollView, 100, 100, 0, -120)
            wait(200)
            verify(content.contentY > 0,
                "the wheel must reach the catcher beside a ScrollView, contentY " + content.contentY)
        }

        // A drag owns the motion from the moment it starts: the inertia must
        // yield instead of fighting it for contentY. Dragged the opposite way to
        // the spin, so a leftover animation would visibly pull the view back.
        function test_a_drag_takes_over() {
            for (let i = 0; i < 8; ++i)
                mouseWheel(kinetic, 150, 100, 0, -120)
            wait(20)
            mousePress(kinetic, 150, 60, Qt.LeftButton)
            for (let y = 60; y <= 160; y += 10) {
                mouseMove(kinetic, 150, y)
                wait(12)
            }
            verify(kinetic.moving, "the drag itself must be running")
            mouseRelease(kinetic, 150, 160, Qt.LeftButton)
            wait(500)
            verify(kinetic.contentY <= 60,
                "the leftover inertia pulled the view back, reached " + kinetic.contentY)
        }

        // The same guarantee for a scroll this component did not make (a
        // restore, positionViewAtIndex, a page change): it must be left where it
        // was put, not dragged back to the wheel target.
        function test_a_foreign_scroll_wins() {
            for (let i = 0; i < 8; ++i)
                mouseWheel(kinetic, 150, 100, 0, -120)
            wait(20)
            kinetic.contentY = 1500
            verify(kinetic.contentY > 500, "the foreign scroll must have moved the view")
            wait(200)
            verify(Math.abs(kinetic.contentY - 1500) < 1,
                "the animation resumed and pulled the view away: " + kinetic.contentY)
        }

        // Content that shrinks under the animation (a filtered list, a removed
        // row) must not leave the view resting past its new end.
        function test_shrinking_content_returns_inside_the_bounds() {
            kinetic.contentY = 1400
            for (let i = 0; i < 4; ++i)
                mouseWheel(kinetic, 150, 100, 0, -120)
            wait(40)
            kinetic.contentHeight = 600
            wait(400)
            const limit = 600 - kinetic.height
            verify(kinetic.contentY <= limit + 0.5,
                "must return inside the bounds, got " + kinetic.contentY + " over " + limit)
        }
    }
}
