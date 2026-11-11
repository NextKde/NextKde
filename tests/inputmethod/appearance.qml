import QtQuick
import QtTest
import "."

Item {
    width: 640
    height: 480
    InputMethodCandidateList {
        id: list
        width: implicitWidth
        height: implicitHeight
        maximumWidth: 400
        maximumHeight: 150
    }
    SignalSpy { id: selection; target: list; signalName: "candidateSelected" }
    TestCase {
        name: "InputMethodAppearance"
        when: windowShown
        function initTestCase() {
            tryCompare(InputMethodConfigService, "ready", true)
            compare(InputMethodConfigService.fontSize, 18)
            compare(InputMethodConfigService.layout, "adaptive")
            compare(InputMethodConfigService.showAnnotations, false)
            compare(InputMethodConfigService.material, "liquid")
        }
        function init() {
            failOnWarning(/ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign/)
            list.reduceMotion = true
            InputMethodConfigService.saveTimer.stop()
            InputMethodConfigService.preferences = InputMethodConfigService.defaults()
            InputMethodConfigService.saveError = ""
            JsonConfigStore.writes = []
            JsonConfigStore.writeSucceeds = true
            list.candidates = [{label:"1", text:"你好", comment:"ni hao"},
                {label:"2", text:"hello world", comment:"greeting"},
                {label:"3", text:"👋", comment:"wave"}]
            list.maximumWidth = 400
            list.maximumHeight = 150
            list.engineLayout = 0
            list.layoutPreference = "engine"
            list.fontSize = 15
            list.cursorIndex = 0
            list.showAnnotations = true
            list.highContrast = false
            list.dark = false
            selection.clear()
            wait(20)
            list.reduceMotion = false
        }
        function test_preferences_persist_only_in_nextkde_state() {
            verify(InputMethodConfigService.update({fontSize:21, layout:"vertical", material:"frosted", highContrast:true}))
            tryVerify(() => JsonConfigStore.writes.length === 1)
            compare(JsonConfigStore.writes[0].path, "/state/kos/inputmethod/presentation.json")
            const saved = JSON.parse(JsonConfigStore.writes[0].data)
            compare(saved.fontSize, 21)
            compare(saved.layout, "vertical")
            compare(saved.highContrast, true)
            compare(saved.material, "frosted")
            verify(saved.enabled === undefined)
        }
        function test_invalid_or_engine_settings_are_rejected_atomically() {
            verify(!InputMethodConfigService.update({fontSize:21, enabled:true}))
            verify(!InputMethodConfigService.update({fontSize:99}))
            verify(!InputMethodConfigService.update({layout:"unknown"}))
            verify(!InputMethodConfigService.update({material:"unknown"}))
            compare(InputMethodConfigService.fontSize, 15)
            wait(300)
            compare(JsonConfigStore.writes.length, 0)
        }
        function test_failed_save_is_visible() {
            JsonConfigStore.writeSucceeds = false
            verify(InputMethodConfigService.update({showAnnotations:false}))
            tryCompare(InputMethodConfigService, "saveError", "Could not save candidate appearance")
        }
        function test_adaptive_layout_and_engine_override() {
            list.layoutPreference = "adaptive"
            list.maximumWidth = 160
            tryCompare(list, "isVertical", true)
            verify(list.width <= 160)
            list.maximumWidth = 1000
            tryCompare(list, "isVertical", false)
            list.engineLayout = 1
            list.layoutPreference = "engine"
            compare(list.isVertical, true)
            list.layoutPreference = "horizontal"
            compare(list.isVertical, false)
        }
        function test_click_keeps_original_engine_index() {
            list.layoutPreference = "vertical"
            wait(20)
            const item = findChild(list, "verticalCandidate-1")
            verify(item !== null)
            mouseClick(item, item.width/2, item.height/2)
            compare(selection.count, 1)
            compare(selection.signalArguments[0][0], 1)
            compare(list.candidates[1].text, "hello world")
        }
        function test_annotations_font_and_contrast() {
            const item = findChild(list, "horizontalCandidate-0")
            const annotation = findChild(item, "candidateAnnotation")
            const word = findChild(item, "candidateWord")
            verify(annotation.visible)
            list.showAnnotations = false
            compare(annotation.visible, false)
            list.fontSize = 24
            compare(word.font.pixelSize, 24)
            list.highContrast = true
            compare(word.color, Qt.rgba(1,1,1,1))
            list.dark = true
            compare(word.color, Qt.rgba(0,0,0,1))
        }
        function test_long_list_stays_bounded_and_reveals_selection() {
            list.layoutPreference = "vertical"
            list.candidates = Array.from({length:30}, (_,i) => ({label:String(i+1),text:"长候选 "+i,comment:"注释"}))
            list.cursorIndex = 29
            verify(list.height <= list.maximumHeight)
            const viewport = findChild(list, "candidateViewport")
            const selected = findChild(list, "verticalCandidate-29")
            tryVerify(() => viewport.contentY > 0
                && selected.y + selected.height <= viewport.contentY + viewport.height + 1, 600)
        }
        function test_selection_animates_without_delaying_activation() {
            const plate = findChild(list, "candidateSelection")
            const next = findChild(list, "horizontalCandidate-1")
            const initialX = plate.x
            list.cursorIndex = 1
            wait(35)
            verify(plate.x > initialX && plate.x < next.x)
            mouseClick(next, next.width/2, next.height/2)
            compare(selection.count, 1)
            compare(selection.signalArguments[0][0], 1)
            tryCompare(plate, "x", next.x, 600)
        }
        function test_fast_selection_reversal_keeps_current_candidate_visible() {
            list.layoutPreference = "vertical"
            list.candidates = Array.from({length:30}, (_,i) => ({label:String(i+1),text:"候选 "+i,comment:""}))
            wait(30)
            list.cursorIndex = 29
            wait(35)
            list.cursorIndex = 0
            const viewport = findChild(list, "candidateViewport")
            const plate = findChild(list, "candidateSelection")
            tryCompare(viewport, "contentY", 0, 600)
            tryCompare(plate, "y", 0, 600)
        }
        function test_reduced_motion_selection_is_immediate() {
            list.reduceMotion = true
            list.cursorIndex = 2
            const plate = findChild(list, "candidateSelection")
            const selected = findChild(list, "horizontalCandidate-2")
            tryCompare(plate, "x", selected.x, 100)
        }
    }
}
