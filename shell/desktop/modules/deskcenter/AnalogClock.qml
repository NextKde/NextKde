import QtQuick
import qs.desktop.modules.common

Canvas {
    id: analogClock
    objectName: "desktop-clock-analog"
    required property date currentDate
    onCurrentDateChanged: requestPaint()
    anchors.fill: parent
    anchors.margins: 14
    onPaint: {
        const ctx = getContext("2d")
        const size = Math.min(width, height)
        const center = size / 2
        const radius = Math.max(0, size / 2 - 3)
        if (radius <= 0)
            return
        const date = analogClock.currentDate
        ctx.reset()
        ctx.translate((width - size) / 2 + center, (height - size) / 2 + center)
        // In the shared glass modes the card material is the
        // face: do not paint a second opaque white disc.
        if (!AppearanceTokens.content.onBackdrop) {
            ctx.fillStyle = "#fafafa"
            ctx.beginPath(); ctx.arc(0, 0, radius, 0, Math.PI * 2); ctx.fill()
        }
        if (!AppearanceTokens.isMaterial) {
            ctx.strokeStyle = AppearanceTokens.content.ink("#dedede", 0.42).toString()
            ctx.lineWidth = 1
            ctx.beginPath(); ctx.arc(0, 0, radius, 0, Math.PI * 2); ctx.stroke()
        }
                        ctx.strokeStyle = AppearanceTokens.content.ink("#171717").toString()
        ctx.lineCap = "round"
        for (let mark = 0; mark < 12; mark++) {
            const angle = mark * Math.PI / 6
            ctx.lineWidth = mark % 3 === 0 ? 1.8 : 0.8
            ctx.beginPath()
            ctx.moveTo(Math.sin(angle) * (radius - 4), -Math.cos(angle) * (radius - 4))
            ctx.lineTo(Math.sin(angle) * (radius - (mark % 3 === 0 ? 10 : 7)), -Math.cos(angle) * (radius - (mark % 3 === 0 ? 10 : 7)))
            ctx.stroke()
        }
        // Full hour numerals make the small analogue clock
        // readable at a glance, rather than relying on ticks
        // alone. Their radius leaves a clear channel for the
        // hands in this one-cell tile.
                        ctx.fillStyle = AppearanceTokens.content.ink("#242126").toString()
        ctx.font = "bold " + Math.max(7, Math.round(radius * 0.18)) + "px sans-serif"
        ctx.textAlign = "center"
        ctx.textBaseline = "middle"
        for (let number = 1; number <= 12; number++) {
            const angle = number * Math.PI / 6
            const numberRadius = radius * 0.68
            ctx.fillText(String(number),
                Math.sin(angle) * numberRadius,
                -Math.cos(angle) * numberRadius)
        }
        const hour = (date.getHours() % 12 + date.getMinutes() / 60) * Math.PI / 6
        const minute = date.getMinutes() * Math.PI / 30
        const second = date.getSeconds() * Math.PI / 30
        if (AppearanceTokens.isMaterial)
            ctx.strokeStyle = AppearanceTokens.colors.primary.toString()
        ctx.lineWidth = 2.5; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(Math.sin(hour) * radius * 0.48, -Math.cos(hour) * radius * 0.48); ctx.stroke()
        if (AppearanceTokens.isMaterial)
            ctx.strokeStyle = AppearanceTokens.colors.tertiary.toString()
        ctx.lineWidth = 1.8; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(Math.sin(minute) * radius * 0.70, -Math.cos(minute) * radius * 0.70); ctx.stroke()
                        ctx.strokeStyle = AppearanceTokens.content.accent(AppearanceTokens.colors.secondary.toString(), "#ee7659").toString(); ctx.lineWidth = 1; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(Math.sin(second) * radius * 0.76, -Math.cos(second) * radius * 0.76); ctx.stroke()
                        ctx.fillStyle = AppearanceTokens.content.accent(AppearanceTokens.colors.primary.toString(), "#ee7659").toString(); ctx.beginPath(); ctx.arc(0, 0, 2.2, 0, Math.PI * 2); ctx.fill()
    }
    // A Canvas reads the scheme only when it paints, so a
    // shell-style switch (material -> macos) or a colour-source
    // switch has to ask for a repaint explicitly, independently
    // of both the date tick and the widget surface switch.
    Connections {
        target: AppearanceTokens
        function onColorRevisionChanged() { analogClock.requestPaint() }
        function onIsMaterialChanged() { analogClock.requestPaint() }
    }
                    Connections {
                        target: AppearanceTokens.content
                        function onOnBackdropChanged() { analogClock.requestPaint() }
    }
}
