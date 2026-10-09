import QtQuick
import QtTest
import "pages"

Item {
    id: fixture
    width: 1066; height: 709
    property string route: "library/songs"
    property int saves: 0
    property bool saveAllowed: true
    property var savedValues: ({})
    function testTrack(title) { return {title:title, artist:"测试艺术家", album:"测试专辑", artwork:"", lyrics:"[00:01.00]原歌词"} }
    Rectangle {
        width: 233; height: parent.height; color: "#52606a"
        TapHandler { onTapped: route = "my-lists" }
    }
    MusicEditorDialog {
        id: editor
        anchors.fill: parent; z: 250
        track: ({title:"测试歌曲", artist:"测试艺术家", album:"测试专辑", artwork:""})
        reduceMotion: true
        onSaveRequested: values => { ++saves; savedValues = values; if (saveAllowed) open = false }
        onCloseRequested: open = false
    }
    Component { id: initialEditor; MusicEditorDialog { width: 1066; height: 709 } }
    TestCase {
        name: "EditorModalNavigation"
        when: windowShown
        function initTestCase() { compare(findChild(editor,"musicEditorContent"), null) }
        function waitForEditor() { tryVerify(() => editor.opacity > 0 && findChild(editor,"musicEditorContent") !== null) }
        function init() {
            route = "library/songs"; saves = 0; saveAllowed = true; savedValues = ({})
            editor.reduceMotion = true; editor.track = testTrack("测试歌曲"); editor.open = true
            waitForEditor()
            wait(50)
        }
        function cleanup() {
            editor.reduceMotion = true; editor.open = false
            tryVerify(() => findChild(editor,"musicEditorContent") === null)
        }
        function test_tabClicksThenSave() {
            for (let tab of [1,2,0]) {
                mouseClick(findChild(editor,"musicEditorTab"+tab))
                compare(editor.selectedTab,tab)
                compare(route,"library/songs","Editor tab must not activate the sidebar beneath it")
            }
            mouseClick(findChild(editor,"musicEditorSaveButton"))
            compare(saves,1)
            compare(editor.open,false)
            compare(route,"library/songs","Saving must leave the original page selected")
        }
        function test_tabThenCancel() {
            mouseClick(findChild(editor,"musicEditorTab1"))
            mouseClick(findChild(editor,"musicEditorCloseButton"))
            compare(editor.open,false)
            compare(saves,0)
            compare(route,"library/songs")
        }
        function test_draftAndMatchSurviveFailedSave() {
            findChild(editor,"musicEditorTitle").text = "手工标题"
            editor.fillMetadata({title:" ",artist:"匹配艺术家",album:"匹配专辑"})
            compare(editor.metadataDraft().title,"手工标题")
            compare(editor.metadataDraft().artist,"匹配艺术家")
            editor.setLyrics("[00:02.00]新歌词")
            compare(editor.selectedTab,1)
            saveAllowed = false
            mouseClick(findChild(editor,"musicEditorSaveButton"))
            compare(saves,1); compare(editor.open,true)
            compare(savedValues.title,"手工标题")
            compare(savedValues.lyrics,"[00:02.00]新歌词")
            compare(editor.metadataDraft().album,"匹配专辑")
            saveAllowed = true
            mouseClick(findChild(editor,"musicEditorSaveButton"))
            compare(editor.open,false)
        }
        function test_keyboardInputAndEscape() {
            const input = findChild(findChild(editor,"musicEditorTitle"),"musicEditorInput")
            mouseClick(input)
            verify(input.activeFocus)
            keyClick(Qt.Key_A,Qt.ControlModifier)
            for (let key of [Qt.Key_E,Qt.Key_D,Qt.Key_I,Qt.Key_T]) keyClick(key)
            compare(editor.metadataDraft().title,"edit")
            keyClick(Qt.Key_Escape)
            compare(editor.open,false); compare(saves,0)
        }
        function test_closeReleasesAndIgnoresLateMatches() {
            editor.open = false
            tryVerify(() => findChild(editor,"musicEditorContent") === null)
            editor.fillMetadata({title:"迟到的标题"}); editor.setLyrics("迟到歌词")
            compare(findChild(editor,"musicEditorContent"),null)
            editor.track = testTrack("另一首歌"); editor.open = true
            waitForEditor()
            compare(editor.metadataDraft().title,"另一首歌")
            mouseClick(findChild(editor,"musicEditorSaveButton"))
            compare(savedValues.lyrics,"[00:01.00]原歌词")
        }
        function test_closeAnimationAndRapidReopen() {
            const surface = findChild(editor,"musicEditorSurface")
            editor.reduceMotion = false; editor.open = false
            wait(40)
            verify(editor.opacity > 0 && editor.opacity < 1)
            compare(findChild(editor,"musicEditorSurface"),surface)
            editor.track = testTrack("快速重开"); editor.open = true
            compare(findChild(editor,"musicEditorSurface"),surface)
            compare(editor.metadataDraft().title,"快速重开")
            tryCompare(editor,"opacity",1,1000)
            editor.open = false
            tryVerify(() => findChild(editor,"musicEditorContent") === null,1000)
        }
        function test_firstOpenKeepsScaleAnimation() {
            editor.open = false
            tryVerify(() => findChild(editor,"musicEditorContent") === null)
            editor.reduceMotion = false; editor.open = true
            waitForEditor()
            const surface = findChild(editor,"musicEditorSurface")
            verify(surface !== null)
            verify(surface.scale < 1,"First open must keep the original scale animation")
            tryCompare(surface,"scale",1,1000)
        }
        function test_initiallyOpenHasPopulatedFields() {
            const opened = createTemporaryObject(initialEditor,fixture,{open:true,reduceMotion:true,track:testTrack("初始打开")})
            verify(opened !== null)
            tryVerify(() => opened.opacity > 0 && findChild(opened,"musicEditorContent") !== null)
            compare(opened.metadataDraft().title,"初始打开")
            opened.open = false
        }
        function test_repeatedOpenClose() {
            for (let i=0;i<20;++i) {
                editor.open=false
                tryVerify(() => findChild(editor,"musicEditorContent") === null)
                editor.track=testTrack("循环歌曲 "+i); editor.open=true
                waitForEditor()
                compare(editor.metadataDraft().title,"循环歌曲 "+i)
            }
        }
        function test_cancelBeforeContentReady() {
            editor.open=false
            tryVerify(() => findChild(editor,"musicEditorContent") === null)
            editor.open=true; editor.open=false
            wait(300)
            compare(findChild(editor,"musicEditorContent"),null)
            compare(editor.opacity,0); compare(editor.visible,false)
        }
    }
}
