import QtQuick
import qs.desktop.modules.common

// IslandWidgetSlot — one widget card inside the island's widget column.
//
// Ported from the NookX Dynamic Island. The original maps each catalogue
// entry onto a native view class (TodoView, WeatherCurrentTempView,
// PomodoroMainView, NoteView, CalendarView, BatteryLevelView, ClockView);
// here the same mapping is a Loader over the ported widget components. The
// catalogue (IslandConfigService.catalogue) decides which ids exist and the
// persisted enabled order decides their sequence, exactly like the
// original's IslandWidgetCatalog + enabledWidgetOrder.
//
// The card is the shell's layered IslandCard: a plate floating above a small
// stack, with a cast shadow and a turn when it is lifted.
//
// This component deliberately owns no pointer input. Picking a card up is
// motion of the whole row -- the card has to move, its neighbours have to
// make room, and the landing marker has to follow -- so the island's content
// layer tracks the pointer once and moves the card through its position
// binding. A per-card MouseArea could not do that without fighting the
// container for the position, and its local mouse coordinates would depend
// on the very offset it was setting.
IslandCard {
    id: root

    required property string widgetId

    // A widget that owns an editor of its own (the notes card) needs the
    // content layer to open a panel; the card itself cannot take the press,
    // because the island keeps exactly one pointer source.
    signal openNotesRequested()
    required property string widgetName

    property bool hovered: false
    property bool dragging: false

    width: 168
    height: 112
    cornerRadius: 24
    depth: 0.7

    bodyColor: Qt.rgba(1, 1, 1, 0.075)
    bodyBorderColor: dragging ? Qt.rgba(0.29, 0.87, 0.5, 0.45)
        : (hovered ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.10))

    lift: dragging ? 1.0 : (hovered ? 0.34 : 0)

    // The title strip doubles as the card's grab handle: the widget body
    // below it belongs to the widget (checkboxes, day cells, transport
    // buttons) and must keep its own clicks.
    Item {
        id: handle
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 24

        Text {
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                      leftMargin: 10; rightMargin: 10 }
            text: root.widgetName
            color: root.hovered ? Qt.rgba(1, 1, 1, 0.78) : Qt.rgba(1, 1, 1, 0.52)
            font.pixelSize: 10
            elide: Text.ElideRight
        }

        // Two short rules at the left: the card's own grab affordance, the
        // same "this can be picked up" hint the editor rows carry.
        Column {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 10 }
            spacing: 2
            visible: root.hovered || root.dragging
            Repeater {
                model: 2
                delegate: Rectangle {
                    width: 9
                    height: 1
                    radius: 0.5
                    color: Qt.rgba(1, 1, 1, 0.38)
                }
            }
        }
    }

    // The widget bodies are drawn at fixed pixel sizes (a seven-column habit
    // grid, a month grid), so on a small output they can be larger than the
    // card they sit in. Clipping here keeps that overflow inside its own card
    // instead of painting over the title strip and the next card.
    Item {
        id: widgetBody
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: parent.bottom
            topMargin: Math.round(root.height * 0.16)
            bottomMargin: Math.round(root.height * 0.06)
            leftMargin: Math.round(root.width * 0.05)
            rightMargin: Math.round(root.width * 0.05)
        }
        clip: true

        Loader {
            anchors.fill: parent
            sourceComponent: {
                switch (root.widgetId) {
                case "todo": return todoComponent
                case "weather": return weatherComponent
                case "clock": return clockComponent
                case "pomodoro": return pomodoroComponent
                case "notes": return notesComponent
                case "battery": return batteryComponent
                case "system": return systemComponent
                case "lyrics": return lyricsComponent
                case "usage": return usageComponent
                case "displays": return displaysComponent
                case "actions": return actionsComponent
                case "calendar": return calendarComponent
                default: return null
                }
            }
        }
    }

    Component {
        id: todoComponent
        IslandTodoWidget { anchors.fill: parent; widgetId: root.widgetId }
    }
    Component {
        id: weatherComponent
        IslandWeatherWidget { anchors.fill: parent }
    }
    Component {
        id: clockComponent
        IslandClockWidget { anchors.fill: parent }
    }
    Component {
        id: pomodoroComponent
        IslandPomodoroWidget { anchors.fill: parent; widgetId: root.widgetId }
    }
    Component {
        id: notesComponent
        IslandNotesWidget {
            anchors.fill: parent
            widgetId: root.widgetId
            onOpenRequested: root.openNotesRequested()
        }
    }
    Component {
        id: batteryComponent
        IslandBatteryWidget { anchors.fill: parent }
    }
    Component {
        id: systemComponent
        IslandSystemWidget { anchors.fill: parent; widgetId: root.widgetId }
    }
    Component {
        id: lyricsComponent
        IslandLyricsWidget { anchors.fill: parent; widgetId: root.widgetId }
    }
    Component {
        id: usageComponent
        IslandUsageWidget { anchors.fill: parent; widgetId: root.widgetId }
    }
    Component {
        id: displaysComponent
        IslandDisplaysWidget { anchors.fill: parent; widgetId: root.widgetId }
    }
    Component {
        id: actionsComponent
        IslandActionsWidget { anchors.fill: parent; widgetId: root.widgetId }
    }
    Component {
        id: calendarComponent
        IslandCalendarWidget { anchors.fill: parent; widgetId: root.widgetId }
    }
}
