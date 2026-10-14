import QtQuick
import QtTest
import "../../../../shared/qml/controls" as Controls
import "../../../../shared/qml/i18n"

Item {
    width: 760
    height: 160
    TestCase {
        name: "SegmentedLabelLayout"
        when: windowShown
        visible: true

        Component {
            id: navigation
            Controls.LiquidNavBar {
                size: "tiny"
                labelFontPixelSize: 10
                labelFontWeight: Font.DemiBold
                itemWidthOverride: 76
                sizeToLabels: true
                currentIndex: 1
                model: [
                    {id: "full", label: "Full-width edge to edge"},
                    {id: "floating", label: "Floating capsule"},
                    {id: "transparent", label: "Fully transparent"}
                ]
            }
        }

        function assertLabelBounds(control) {
            for (let index = 0; index < control.model.length; ++index) {
                const label = findChild(control, "liquid-nav-label-" + index)
                verify(label !== null)
                const left = label.mapToItem(control, 0, 0).x
                const right = label.mapToItem(control, label.width, 0).x
                verify(left >= index * control.itemWidth - 0.5, "Label crossed its left segment edge")
                verify(right <= (index + 1) * control.itemWidth + 0.5, "Label crossed its right segment edge")
                compare(label.elide, Text.ElideRight)
            }
        }

        function test_englishUsesMeasuredWidth() {
            const control = createTemporaryObject(navigation, this)
            verify(control !== null)
            wait(120)
            verify(control.width > 3 * 76)
            assertLabelBounds(control)
            for (let index = 0; index < 3; ++index)
                verify(!findChild(control, "liquid-nav-label-" + index).truncated)
        }

        function test_constrainedWidthKeepsLabelsAndSelectionInside() {
            const control = createTemporaryObject(navigation, this, {width: 228})
            wait(120)
            assertLabelBounds(control)
            verify(findChild(control, "liquid-nav-label-0").truncated)
            mouseClick(control, control.itemWidth * 2.5, control.height / 2)
            compare(control.currentIndex, 2)
            control.width = 420
            wait(160)
            assertLabelBounds(control)
            verify(Math.abs(control._currentThumbX - control.targetX(2)) < 0.5)
        }

        function test_chineseToEnglishReflows() {
            const control = createTemporaryObject(navigation, this, {
                model: [{id: "full", label: "全宽贴边"},
                        {id: "floating", label: "悬浮胶囊"},
                        {id: "transparent", label: "全透明"}]
            })
            const before = control.implicitWidth
            control.model = [{id: "full", label: "Full-width edge to edge"},
                             {id: "floating", label: "Floating capsule"},
                             {id: "transparent", label: "Fully transparent"}]
            wait(160)
            verify(control.implicitWidth > before)
            assertLabelBounds(control)
            verify(Math.abs(control._currentThumbX - control.targetX(1)) < 0.5)
        }

        function test_settingsBarPageAtMinimumWidth() {
            const previous = I18n.language
            let app = null
            try {
                I18n.language = "en"
                const component = Qt.createComponent("../../main.qml")
                compare(component.status, Component.Ready, component.errorString())
                app = component.createObject(null, {currentPage: 2, width: 1030, height: 720})
                verify(app !== null)
                tryVerify(() => findChild(app.contentItem, "bar-layout-picker") !== null)
                const layout = findChild(app.contentItem, "bar-layout-picker")
                const visibility = findChild(app.contentItem, "bar-visibility-picker")
                verify(visibility !== null)
                verify(waitForRendering(layout))
                wait(180)
                assertLabelBounds(layout)
                assertLabelBounds(visibility)
                for (let i = 0; i < layout.model.length; ++i)
                    verify(!findChild(layout, "liquid-nav-label-" + i).truncated)

                let captured = false
                const scroll = findChild(app.contentItem, "settings-page-scroll")
                scroll.parent.grabToImage(result => {
                    captured = result.saveToFile("/tmp/kos-settings-english-bar-layout.png")
                })
                tryVerify(() => captured)
            } finally {
                if (app) app.destroy()
                I18n.language = previous
            }
        }
    }
}
