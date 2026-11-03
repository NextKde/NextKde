import QtQuick
import QtTest

TestCase {
    id: root
    name: "StageDesktopTransition"
    property string modelDesktop: "desk1"
    property real progressAtCommit: -1

    StageDesktopTransition {
        id: motion
        desktopId: "desk1"
        hasCards: true
        onCommit: {
            root.modelDesktop = motion._displayedDesktopId
            root.progressAtCommit = motion.progress
        }
    }
    SignalSpy { id: commits; target: motion; signalName: "commit" }

    function init() {
        motion.enabled = false
        motion.desktopId = "desk1"
        motion.hasCards = true
        motion.offscreen = false
        motion.rightSide = false
        motion.enabled = true
        commits.clear()
        root.progressAtCommit = -1
    }
    function cleanup() { motion.enabled = false }

    function test_fade_out_before_replacing_then_slide_in() {
        motion.desktopId = "desk2"
        verify(motion.active)
        compare(root.modelDesktop, "desk1")
        compare(commits.count, 0)
        tryVerify(() => motion.progress > 0 && motion.progress < 1)
        verify(motion.offset < 0)
        tryCompare(commits, "count", 1)
        compare(root.progressAtCommit, 0)
        compare(root.modelDesktop, "desk2")
        tryCompare(motion, "active", false)
        compare(motion.progress, 1)
        compare(motion.offset, 0)
    }
    function test_rapid_switches_commit_only_the_latest_desktop() {
        motion.desktopId = "desk2"
        motion.desktopId = "desk3"
        motion.desktopId = "desk4"
        compare(root.modelDesktop, "desk1")
        tryCompare(motion, "active", false)
        compare(commits.count, 1)
        compare(root.modelDesktop, "desk4")
        compare(root.progressAtCommit, 0)
    }
    function test_model_sync_can_arrive_before_desktop_binding() {
        verify(motion.deferSync("desk2"))
        compare(root.modelDesktop, "desk1")
        motion.desktopId = "desk2"
        tryCompare(motion, "active", false)
        compare(commits.count, 1)
        compare(root.modelDesktop, "desk2")
        compare(root.progressAtCommit, 0)
    }
    function test_switch_during_entrance_continues_from_current_pose() {
        motion.desktopId = "desk2"
        tryCompare(commits, "count", 1)
        tryVerify(() => motion.progress > 0 && motion.progress < 1)
        motion._animation.pause()
        const previous = motion.progress
        motion.desktopId = "desk3"
        compare(motion.progress, previous)
        compare(root.modelDesktop, "desk2")
        tryCompare(motion, "active", false)
        compare(commits.count, 2)
        compare(root.modelDesktop, "desk3")
        compare(root.progressAtCommit, 0)
    }
    function test_already_hidden_cards_skip_the_exit_animation() {
        motion.offscreen = true
        motion.desktopId = "desk2"
        compare(motion.progress, 0)
        compare(root.modelDesktop, "desk1")
        tryCompare(commits, "count", 1)
        compare(root.modelDesktop, "desk2")
        compare(root.progressAtCommit, 0)
        tryCompare(motion, "active", false)
    }
    function test_empty_sidebar_still_animates_new_cards_in() {
        motion.hasCards = false
        motion.desktopId = "desk2"
        compare(motion.progress, 0)
        tryCompare(commits, "count", 1)
        motion.hasCards = true
        tryCompare(motion, "active", false)
        compare(root.modelDesktop, "desk2")
        compare(motion.progress, 1)
    }
    function test_disabling_cancels_delayed_commits() {
        motion.desktopId = "desk2"
        motion.enabled = false
        verify(!motion.active)
        compare(motion.progress, 1)
        compare(root.modelDesktop, "desk2")
        const count = commits.count
        wait(400)
        compare(commits.count, count)
        motion.desktopId = "desk3"
        compare(root.modelDesktop, "desk3")
        verify(!motion.active)
    }
    function test_hidden_commit_can_be_cancelled_before_next_frame() {
        motion.offscreen = true
        motion.desktopId = "desk2"
        motion.enabled = false
        const count = commits.count
        wait(50)
        compare(commits.count, count)
        verify(!motion.active)
        compare(motion.progress, 1)
    }
    function test_right_sidebar_motion_is_mirrored() {
        motion.rightSide = true
        motion.desktopId = "desk2"
        tryVerify(() => motion.progress > 0 && motion.progress < 1)
        verify(motion.offset > 0)
        tryCompare(motion, "active", false)
        compare(motion.offset, 0)
    }
}
