import QtQuick

// Frameless window title bar.  The content shell is placed below this bar by
// Main.qml, so the chrome never intercepts page controls.
Rectangle {
    id: chrome

    property var targetWindow
    property color backgroundColor: AppTheme.topBarStart
    property color foregroundColor: AppTheme.textPrimary

    height: 36
    color: backgroundColor
    border.color: AppTheme.border
    border.width: 1

    // Keep the entire title-bar area draggable except the three controls.
    MouseArea {
        id: dragArea
        anchors.fill: parent
        anchors.rightMargin: controls.width
        acceptedButtons: Qt.LeftButton
        onPressed: {
            if (chrome.targetWindow && chrome.targetWindow.startSystemMove)
                chrome.targetWindow.startSystemMove()
        }
        onDoubleClicked: {
            // The first release is intentionally a no-op: the shell is fixed
            // at 1280x720 for the first UI phase.  Keeping this handler makes
            // the title bar compatible with a future resizable build.
            if (chrome.targetWindow && chrome.targetWindow.visibility === Window.Maximized)
                chrome.targetWindow.showNormal()
            else if (chrome.targetWindow && chrome.targetWindow.visibility === Window.Windowed)
                chrome.targetWindow.showMaximized()
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        text: "ListenFree"
        color: foregroundColor
        font.pixelSize: 12
        font.weight: Font.DemiBold
        opacity: 0.9
    }

    Row {
        id: controls
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        ChromeButton {
            label: "—"
            accessibleName: "Minimize"
            onClicked: if (chrome.targetWindow) chrome.targetWindow.showMinimized()
        }
        ChromeButton {
            label: "□"
            accessibleName: "Maximize"
            enabled: false
            opacity: 0.35
        }
        ChromeButton {
            label: "×"
            accessibleName: "Close"
            hoverColor: "#e25555"
            onClicked: if (chrome.targetWindow) chrome.targetWindow.close()
        }
    }

    component ChromeButton: Rectangle {
        property string label: ""
        property string accessibleName: ""
        property color hoverColor: AppTheme.controlHover
        signal clicked()

        width: 46
        height: chrome.height - 2
        color: buttonMouse.containsMouse ? hoverColor : "transparent"

        Text {
            anchors.centerIn: parent
            text: parent.label
            color: chrome.foregroundColor
            font.pixelSize: parent.label === "×" ? 22 : 16
            font.weight: Font.Normal
        }
        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: parent.enabled
            onClicked: parent.clicked()
        }
    }
}
