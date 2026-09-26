import QtQuick
import QtTest
import "../../shared/qml/foundation"

TestCase {
    name: "MusicLyricTransition"
    when: windowShown
    visible: true
    width: 600
    height: 120
    Component { id: lyric; KosLyricLine { width: 500; height: 32; font.pixelSize: 24 } }

    function test_slideAndFade() {
        const line = createTemporaryObject(lyric, this, { text: "上一句" })
        verify(line !== null)
        line.text = "下一句"
        verify(line.transitioning)
        const previous = findChild(line, "previousLine")
        const current = findChild(line, "currentLine")
        wait(80)
        compare(previous.text, "上一句")
        compare(current.text, "下一句")
        verify(previous.opacity > 0 && previous.opacity < 1)
        verify(current.opacity > 0 && current.opacity < 1)
        verify(previous.y < 0 && current.y > 0)
        tryCompare(line, "transitioning", false)
        compare(current.y, 0)
        compare(current.opacity, 1)
        compare(previous.opacity, 0)
    }
    function test_rapidSeekAndHide() {
        const line = createTemporaryObject(lyric, this, { text: "第一句" })
        line.text = "第二句"
        wait(50)
        line.text = "第十句"
        tryCompare(line, "transitioning", false)
        compare(findChild(line, "currentLine").text, "第十句")
        line.text = "第十一句"
        verify(line.transitioning)
        line.visible = false
        verify(!line.transitioning)
        line.text = ""
        line.visible = true
        verify(!line.transitioning)
        compare(findChild(line, "currentLine").text, "")
        compare(findChild(line, "previousLine").opacity, 0)
    }
}
