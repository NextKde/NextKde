import QtQuick
import QtTest
import "pages"

Item {
    width: 1066; height: 709
    QtObject {
        id: store
        property int revision: 0
        property bool bili: false
        function value(key, fallback) { return key === "account.bilibili.sourceEnabled" ? bili : fallback }
        function setValue(key, value) { if (key === "account.bilibili.sourceEnabled") bili = value; ++revision }
    }
    QtObject {
        id: online
        property bool bilibiliSourceEnabled: store.bili
        property string platform: "kw"
        property string searchCategory: "songs"
        property int searchPage: 1
        property int searchPageCount: 1
        property bool busy: false
        property var searchResults: []
    }
    Loader {
        id: settings
        anchors.fill: parent
        sourceComponent: SettingsPage {
            selectedCategory: 6
            settingsStore: store
            onSettingChanged: (key, value) => store.setValue(key, value)
        }
    }
    SearchPage { id: search; anchors.fill: parent; visible: !settings.active; onlineController: online }
    TestCase {
        name: "BilibiliSettingsSignal"
        when: windowShown
        function test_clickPersistsAndExposesSearchPlatform() {
            const toggle = findChild(settings.item, "settingSwitch/account.bilibili.sourceEnabled")
            verify(toggle !== null)
            mouseClick(toggle)
            compare(store.bili, true, "Account group must forward the toggle to SettingsPage.settingChanged")
            settings.active = false
            tryVerify(() => search.platformIds.indexOf("bili") >= 0)
            online.platform = "bili"
            compare(search.categoryIds.length, 2)
            settings.active = true
            tryVerify(() => settings.item !== null)
            const reopened = findChild(settings.item, "settingSwitch/account.bilibili.sourceEnabled")
            compare(reopened.checked, true, "Reopening settings must preserve the enabled switch")
            mouseClick(reopened)
            compare(store.bili, false)
            tryVerify(() => search.platformIds.indexOf("bili") < 0)
        }
    }
}
