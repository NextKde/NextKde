import QtQuick
import QtTest

TestCase {
    id: root
    name: "StageDesktopTransition"
    property string modelDesktop: "desk1"

    StageDesktopTransition {
        id: motion
        desktopId: "desk1"
        onCommit: root.modelDesktop = motion._displayedDesktopId
    }
    SignalSpy { id: commits; target: motion; signalName: "commit" }

    function init() {
        motion.enabled = false
        motion.blocked = false
        motion.desktopId = "desk1"
        motion.enabled = true
        commits.clear()
    }
    function cleanup() { motion.enabled = false }

    function test_hold_old_model_throughout_desktop_switch() {
        motion.blocked = true
        motion.desktopId = "desk2"
        wait(350)
        verify(motion.active)
        compare(commits.count, 0)
        compare(root.modelDesktop, "desk1")
        motion.blocked = false
        tryCompare(motion, "active", false)
        compare(commits.count, 1)
        compare(root.modelDesktop, "desk2")
    }
    function test_rapid_switches_commit_only_the_latest_desktop() {
        motion.blocked = true
        motion.desktopId = "desk2"
        motion.desktopId = "desk3"
        motion.desktopId = "desk4"
        compare(root.modelDesktop, "desk1")
        motion.blocked = false
        tryCompare(motion, "active", false)
        compare(commits.count, 1)
        compare(root.modelDesktop, "desk4")
    }
    function test_model_sync_can_arrive_before_desktop_binding() {
        motion.blocked = true
        verify(motion.deferSync("desk2"))
        compare(root.modelDesktop, "desk1")
        motion.desktopId = "desk2"
        motion.blocked = false
        tryCompare(motion, "active", false)
        compare(commits.count, 1)
        compare(root.modelDesktop, "desk2")
    }
    function test_disabled_compositor_animations_commit_without_fading() {
        motion.desktopId = "desk2"
        compare(root.modelDesktop, "desk1")
        tryCompare(motion, "active", false)
        compare(commits.count, 1)
        compare(root.modelDesktop, "desk2")
    }
    function test_window_updates_are_held_even_before_desktop_id_changes() {
        motion.blocked = true
        verify(motion.active)
        verify(motion.deferSync("desk1"))
        compare(commits.count, 0)
        motion.desktopId = "desk2"
        motion.blocked = false
        tryCompare(motion, "active", false)
        compare(root.modelDesktop, "desk2")
    }
    function test_cancelled_switch_restores_original_model_once() {
        motion.blocked = true
        motion.desktopId = "desk2"
        motion.desktopId = "desk1"
        compare(root.modelDesktop, "desk1")
        motion.blocked = false
        tryCompare(motion, "active", false)
        compare(commits.count, 1)
        compare(root.modelDesktop, "desk1")
    }
    function test_disabling_cancels_pending_commit() {
        motion.blocked = true
        motion.desktopId = "desk2"
        motion.enabled = false
        verify(!motion.active)
        compare(root.modelDesktop, "desk2")
        const count = commits.count
        motion.blocked = false
        wait(100)
        compare(commits.count, count)
        motion.desktopId = "desk3"
        compare(root.modelDesktop, "desk3")
    }
    function test_new_switch_supersedes_commit_queued_for_previous_switch() {
        motion.blocked = true
        motion.desktopId = "desk2"
        motion.blocked = false
        motion.blocked = true
        motion.desktopId = "desk3"
        wait(100)
        compare(commits.count, 0)
        motion.blocked = false
        tryCompare(motion, "active", false)
        compare(commits.count, 1)
        compare(root.modelDesktop, "desk3")
    }
}
