import QtQuick
import QtQuick.Controls
import QtTest
import "ui/controls" as Demo
Item {
    ApplicationWindow { id: host; width: 960; height: 660; visible: true
        Item { id: anchor; x: 460; y: 310; width: 40; height: 40 }
        Demo.LiquidContentPopover { id: panel; anchorItem: anchor; width: 200; height: 180 }
    }
    width: 960; height: 660; visible: true

    TestCase {
        name: "PopoverArrows"; when: windowShown
        function test_directions() {
            panel.open(); wait(100)
            for (const side of ["right", "left", "top", "bottom"]) {
                panel.preferredSide = side; panel.updatePosition(); wait(20)
                compare(panel.resolvedSide, side); verify(panel.arrowVisible)
                verify(panel.arrowPosition >= panel.cornerRadius + panel.arrowWidth / 2)
            }
            panel.close()
        }
        function test_largeEditor() {
            panel.arrowEnabled = false; panel.height = 640; panel.open(); wait(100)
            verify(!panel.arrowVisible); compare(panel.arrowHeight, 0)
            compare(panel.leftPadding, panel.padding); compare(panel.topPadding, panel.padding)
            panel.close(); panel.arrowEnabled = true; panel.height = 180
        }
        function test_cornerAndOutside() {
            anchor.x = 0; anchor.y = 0; panel.open(); wait(100)
            verify(!panel.arrowVisible)
            anchor.x = -200; panel.updatePosition(); verify(!panel.arrowVisible)
            panel.close(); anchor.x = 460; anchor.y = 310
        }
    }
}
