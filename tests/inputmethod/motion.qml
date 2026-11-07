import QtQuick
import QtTest
import "."

TestCase {
    name: "InputMethodPresentation"

    InputMethodPresentation { id: panel }

    function candidates(text) {
        return { enabled: true, visible: true, lookupVisible: true,
            candidates: [{ label: "1", text: text || "你好", comment: "" }],
            preeditVisible: true, preeditText: "nihao", auxVisible: false, auxText: "",
            cursorIndex: 0, layout: 0, hasPrev: false, hasNext: false }
    }

    function tip(text) {
        return { enabled: true, visible: true, lookupVisible: false, candidates: [],
            preeditVisible: false, preeditText: "", auxVisible: true, auxText: text }
    }

    function show(state) {
        panel.update(state || candidates(), { x: 160, y: 120, height: 20 }, true)
        tryCompare(panel, "mapped", true)
        tryCompare(panel, "progress", 1)
    }

    function cleanup() {
        panel.update({ enabled: true, visible: false }, null, false)
        tryCompare(panel, "mapped", false)
        InputMethodService._applyState({ enabled: true, visible: false })
        PlatformClient.calls = []
        WindowService.kwinActiveId = "window-a"
    }

    function test_exit_retains_candidates_and_anchor() {
        show()
        const oldState = panel.state
        const oldAnchor = panel.anchor
        panel.update({ enabled: true, visible: false, candidates: [] },
            { x: 900, y: 800 }, true)
        tryCompare(panel, "interactive", false)
        verify(panel.mapped)
        verify(panel.progress > 0)
        compare(panel.state, oldState)
        compare(panel.anchor, oldAnchor)
        compare(panel.isOnlyTip, false)
        tryCompare(panel, "mapped", false)
        compare(panel.progress, 0)
    }

    function test_tip_fades_and_reopens_without_reset() {
        show(tip("中"))
        verify(panel.isOnlyTip)
        panel.update({ enabled: true, visible: false }, null, true)
        tryCompare(panel, "interactive", false)
        wait(45)
        verify(panel.progress > 0 && panel.progress < 1)
        const before = panel.progress
        panel.update(tip("英"), { x: 160, y: 120 }, true)
        tryCompare(panel, "interactive", true)
        verify(panel.progress > 0)
        verify(Math.abs(panel.progress - before) < 0.3)
        compare(panel.state.auxText, "英")
        tryCompare(panel, "progress", 1)
        compare(panel.scale, 1)
    }

    function test_same_turn_updates_commit_latest_content() {
        panel.update(tip("中"), { x: 100, y: 100 }, true)
        panel.update({ enabled: true, visible: false }, null, false)
        panel.update(candidates("最新"), { x: 200, y: 200 }, true)
        tryCompare(panel, "mapped", true)
        compare(panel.state.candidates[0].text, "最新")
        compare(panel.anchor.x, 200)
        verify(!panel.isOnlyTip)
        tryCompare(panel, "progress", 1)
        panel.update(candidates("更新"), { x: 240, y: 200 }, true)
        tryVerify(function() { return panel.state.candidates[0].text === "更新" })
        compare(panel.progress, 1)
    }

    function test_screen_handoff_closes_in_place() {
        show()
        panel.update(candidates(), { x: 2100, y: 120 }, false)
        tryCompare(panel, "interactive", false)
        compare(panel.anchor.x, 160)
        tryCompare(panel, "mapped", false)
    }

    function test_empty_visible_payload_does_not_open() {
        panel.update(tip(""), { x: 160, y: 120 }, true)
        wait(30)
        compare(panel.mapped, false)
        compare(panel.progress, 0)
    }

    function test_first_frame_waits_for_fresh_anchor() {
        const state = candidates()
        state.anchorReady = false
        panel.update(state, { x: 0, y: 0 }, true)
        wait(35)
        compare(panel.mapped, false)
        compare(panel.progress, 0)
        panel.update(Object.assign({}, state, { anchorReady: true }),
            { x: 1500, y: 900 }, true)
        tryCompare(panel, "mapped", true)
        compare(panel.anchor.x, 1500)
        compare(panel.anchor.y, 900)
        tryCompare(panel, "progress", 1)
    }

    function test_service_resolves_anchor_once_per_opening() {
        const state = Object.assign(candidates(), { spot: {}, caret: {} })
        InputMethodService._applyState(state)
        compare(InputMethodService.popupState.anchorReady, false)
        compare(PlatformClient.calls.length, 1)
        InputMethodService._applyState(state)
        compare(PlatformClient.calls.length, 1)
        const call = PlatformClient.calls[0]
        compare(call.op, "input.clipboard-anchor")
        call.callback({ ok: true, result: { available: true, source: "caret", x: 1600, y: 950 } })
        compare(InputMethodService.popupState.anchorReady, true)
        compare(InputMethodService.globalAnchor.x, 1600)
        compare(InputMethodService.globalAnchor.y, 950)
    }

    function test_service_ignores_late_response_after_close() {
        InputMethodService._applyState(candidates())
        const call = PlatformClient.calls[0]
        InputMethodService._applyState({ enabled: true, visible: false })
        call.callback({ ok: true, result: { available: true, source: "caret", x: 2400, y: 1300 } })
        compare(InputMethodService.popupState.visible, false)
        compare(InputMethodService._openingCaret.available, undefined)
    }

    function test_service_anchor_timeout_releases_panel() {
        InputMethodService._applyState(candidates())
        compare(InputMethodService.popupState.anchorReady, false)
        tryVerify(function() { return InputMethodService.popupState.anchorReady }, 500)
        const call = PlatformClient.calls[0]
        call.callback({ ok: true, result: { available: true, source: "caret", x: 2400, y: 1300 } })
        compare(InputMethodService._openingCaret.available, undefined)
    }
}
