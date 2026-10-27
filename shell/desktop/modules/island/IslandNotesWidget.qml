import QtQuick
import "../../../shared/qml/i18n"

// IslandNotesWidget — the island side of the notes store.
//
// The card shows the three most recent note titles, the way a memo list
// behaves: a note is a Markdown file on disk (IslandNotesService) and the
// island is only an index of what exists. Clicking opens the notes panel; the
// "new" affordance creates a note without leaving the island.
//
// The previous version of this widget was a scratch pad whose text went into
// the bounded state store. That is not a memo: nothing was a document, and the
// card had no list to be a preview of.
Rectangle {
    id: root

    required property string widgetId

    // Raised so the content layer can open the notes panel. The island keeps
    // one pointer source, so the card cannot take a press itself.
    signal openRequested()

    readonly property var notes: IslandNotesService.recent
    readonly property bool empty: notes.length === 0

    color: "transparent"

    Text {
        id: heading
        anchors { left: parent.left; right: newButton.left; top: parent.top }
        width: Math.max(20, parent.width - newButton.width - 4)
        text: I18n.tr("Notes")
        color: Qt.rgba(1, 1, 1, 0.45)
        font.pixelSize: 10
        elide: Text.ElideRight
    }

    Rectangle {
        id: newButton
        anchors { right: parent.right; top: parent.top }
        width: 18
        height: 18
        radius: 9
        color: newTarget.hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07)

        Text {
            anchors.centerIn: parent
            text: "+"
            color: Qt.rgba(1, 1, 1, 0.7)
            font.pixelSize: 12
        }

        IslandPointerTarget {
            id: newTarget
            anchors.fill: parent
            pointerOrigin: root
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                IslandNotesService.createNote()
                root.openRequested()
            }
        }
    }

    Column {
        anchors {
            left: parent.left
            right: parent.right
            top: heading.bottom
            bottom: parent.bottom
            topMargin: 4
        }
        spacing: 2

        // Only three rows fit a card, which is exactly why the panel exists:
        // this is a preview of the store, not the store.
        Repeater {
            model: root.notes

            delegate: Rectangle {
                required property var modelData

                width: parent.width
                height: 18
                radius: 5
                color: rowTarget.hovered ? Qt.rgba(1, 1, 1, 0.07) : "transparent"

                Rectangle {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    width: 2
                    height: 10
                    radius: 1
                    color: Qt.rgba(1, 1, 1, 0.45)
                }

                Text {
                    anchors {
                        left: parent.left
                        right: parent.right
                        leftMargin: 8
                        rightMargin: 2
                        verticalCenter: parent.verticalCenter
                    }
                    // A note with no heading yet still needs a row: the title
                    // is derived from the first non-empty line, so an empty
                    // note shows the placeholder rather than a blank line.
                    text: (modelData.title && String(modelData.title).length > 0)
                        ? modelData.title : I18n.tr("Untitled note")
                    color: Qt.rgba(1, 1, 1, 0.82)
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                IslandPointerTarget {
                    id: rowTarget
                    anchors.fill: parent
                    pointerOrigin: root
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        IslandNotesService.openNote(modelData.id)
                        root.openRequested()
                    }
                }
            }
        }

        Text {
            width: parent.width
            visible: root.empty
            text: I18n.tr("No notes yet")
            color: Qt.rgba(1, 1, 1, 0.32)
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }

    // The whole card opens the panel too: a card whose only target is an 18px
    // plus button is a card nobody finds.
    IslandPointerTarget {
        anchors.fill: parent
        pointerOrigin: root
        onClicked: root.openRequested()
    }
}