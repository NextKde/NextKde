import QtQuick
import QtTest
import "../../pages"
Item {
    width: 700; height: 450
    QtObject {
        id: fakePower
        property var state: ({ profiles:["power-saver","balanced","performance"], activeProfile:"balanced", busy:false })
        property string requested: ""
        function refresh() {}
        function setProfile(mode) { requested=mode; state={profiles:state.profiles,activeProfile:state.activeProfile,busy:true,pendingProfile:mode} }
    }
    PowerSettingsPage {
        id: page; width: parent.width
        backend: fakePower
        colors: ({primaryText:"#111111",secondaryText:"#666666",card:"#ffffff",separator:"#dddddd",accent:"#0088ff"})
    }
    TestCase {
        name: "PowerSettingsInteractions"
        when: windowShown
        function test_actual_selection_only() {
            const balanced=findChild(page,"powerMode-balanced")
            const saver=findChild(page,"powerMode-power-saver")
            verify(balanced.selected)
            mouseClick(saver,40,30)
            compare(fakePower.requested,"power-saver")
            verify(balanced.selected, "pending write must not change the selected mode")
            verify(!saver.selected)
            verify(!saver.enabled)
            fakePower.state={profiles:["balanced","power-saver"],activeProfile:"power-saver",busy:false}
            verify(saver.selected)
            verify(!findChild(page,"powerMode-performance").enabled)
        }
    }
}
