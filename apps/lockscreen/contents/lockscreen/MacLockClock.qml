// SPDX-FileCopyrightText: 2026 KOS
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick

// Deliberately separate from LockClock.qml, also shipped by the SDDM theme.
// Plain Text remains legible with software rendering and missing optional effects.
Column {
    id: clock
    property date now: new Date()
    property real unit: 1
    property real availableWidth: 1000
    readonly property string fontFamily: {
        const families = Qt.fontFamilies()
        for (const family of ["Nunito", "Open Runde", "Inter Display", "Inter", "Noto Sans", "DejaVu Sans"])
            if (families.indexOf(family) >= 0) return family
        return Qt.application.font.family
    }
    readonly property var locale: Qt.locale()
    readonly property string timeString: Qt.formatTime(now, locale.timeFormat(Locale.ShortFormat)).replace(/^0(?=\d:)/, "")
    spacing: -8 * unit
    Text {
        objectName: "clockDateText"
        anchors.horizontalCenter: parent.horizontalCenter
        text: clock.locale.toString(clock.now,
            clock.locale.name.indexOf("zh") === 0 ? "M月d日 dddd" : "dddd, MMMM d")
        textFormat: Text.PlainText
        color: "#d9ffffff"
        font.family: clock.fontFamily
        font.pixelSize: Math.max(14, Math.round(25 * clock.unit))
        font.weight: Font.Medium
    }
    Text {
        objectName: "clockTimeText"
        anchors.horizontalCenter: parent.horizontalCenter
        text: clock.timeString
        textFormat: Text.PlainText
        color: "#dbffffff"
        font.family: clock.fontFamily
        font.pixelSize: Math.min(176 * clock.unit, clock.availableWidth / 4)
        font.weight: Font.Medium
        font.letterSpacing: -3 * clock.unit
    }
}
