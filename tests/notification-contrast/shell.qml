import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.bar
import qs.desktop.modules.deskcenter
ShellRoot {
    id: test
    property int stage: 0
    property bool configured: false
    property var cases: [
        ["macos","color","light"], ["macos","color","dark"],
        ["macos","color","light"], ["macos","color","dark"],
        ["macos","glass","light"], ["macos","glass","dark"],
        ["macos","color","light"],
        ["material","color","light"], ["material","color","dark"]
    ]
    FloatingWindow {
        id: window
        visible: true; width: 390; height: 460
        color: test.stage % 2 === 0 ? "black" : "white"
        DeskWidgetCard {
            id: card
            anchors.fill: parent
            startColor: "#434b58"; endColor: "#2a313d"
            DeskNotificationWidget { id: widget }
        }
    }
    function find(item, text) {
        if (item.text === text) return item
        for (const child of item.children || []) {
            const found = find(child, text)
            if (found) return found
        }
        return null
    }
    function named(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const match = named(child,name)
            if (match) return match
        }
        return null
    }
    function blend(fg, bg) {
        return Qt.rgba(fg.r*fg.a+bg.r*(1-fg.a), fg.g*fg.a+bg.g*(1-fg.a), fg.b*fg.a+bg.b*(1-fg.a), 1)
    }
    function luminance(c) {
        const linear = v => v <= .04045 ? v/12.92 : Math.pow((v+.055)/1.055,2.4)
        return .2126*linear(c.r)+.7152*linear(c.g)+.0722*linear(c.b)
    }
    function contrast(fg,bg) {
        const a=luminance(blend(fg,bg)),b=luminance(bg)
        return (Math.max(a,b)+.05)/(Math.min(a,b)+.05)
    }
    function check(ok,message) { if(!ok) throw new Error(message) }
    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            try {
                if (!AppearanceConfigService.ready) return
                if (!test.configured) {
                    const c = test.cases[test.stage]
                    AppearanceConfigService.shellStyle = c[0]
                    AppearanceConfigService.widgetStyle = c[1]
                    AppearanceConfigService.themeMode = c[2]
                    AppearanceConfigService.glassFollowsAppearanceMode = true
                    if (!ControlCenterService.notificationHistory.count)
                        ControlCenterService.notificationHistory.append({notifId:1,appName:"QQ",desktopEntry:"qq",appIcon:"",image:"",summary:"主题切换测试",body:"消息正文在深浅色模式都应该清晰",timestamp:new Date(2026,9,10,12,34).getTime(),actionLabel:"查看",hasAction:true})
                    ControlCenterService.rebuildHistoryGroups()
                    test.configured = true
                    return
                }
                const c = test.cases[test.stage]
                const row = find(widget,"主题切换测试").parent.parent
                check(card.usesColorArtwork === (c[1] === "color"), "card follows the selected artwork/glass mode")
                check(card.blurRegion !== null || (c[1] === "color" && !card.tonalSurface), "glass/tonal mode owns native blur while colour artwork does not")
                const fill = card.tonalSurface
                    ? Qt.rgba(card.materialSurfaceColor.r,card.materialSurfaceColor.g,card.materialSurfaceColor.b,AppearanceTokens.surface.widgetOpacity)
                    : (c[1] === "color" ? card.startColor : "transparent")
                const backing = blend(fill,window.color)
                const bg = blend(row.color,backing)
                for (const text of ["主题切换测试","消息正文在深浅色模式都应该清晰","QQ","12:34"]) {
                    const item = find(row,text)
                    check(item && item.visible,"rendered label " + text)
                    const ratio = contrast(item.color,bg)
                    check(ratio >= 4.5, c.join("/") + " low text contrast " + text + "=" + ratio)
                }
                const header = find(widget,"通知中心")
                check(header.style === Text.Normal, "title uses clean text without an outline")
                if (widget.onGlass) check(header.color.toString() === "#ffffff", "glass header keeps white ink")
                else check(contrast(header.color,backing) >= 4.5, "artwork/tonal title contrast")
                const selectedBackground = AppearanceTokens.content.onBackdrop ? AppearanceTokens.colors.primaryContainer : blend(widget.ink(.20),backing)
                check(contrast(find(widget,"全部").color,selectedBackground) >= 4.5, "selected category contrast")
                const icon = named(widget,"notification-centre-icon")
                check(icon && icon.name === "notification-bell" && icon.source.length > 0, "title has a bundled vector bell rather than a font character")
                check(icon.children[0].status === Image.Ready, "bell SVG actually loaded")
                check(contrast(widget.actionInk,widget.actionFill) >= 4.5,"open button contrast")
                if (Quickshell.env("PREVIEW_DIR")) {
                    const path = Quickshell.env("PREVIEW_DIR") + "/" + test.stage + "-" + c.join("-") + ".png"
                    window.contentItem.grabToImage(result => result.saveToFile(path))
                }
                console.log("NOTIFICATION_CONTRAST_PASS " + c.join("/") + " all message labels >=4.5")
                if (++test.stage === test.cases.length) { Qt.quit(); return }
                test.configured = false
            } catch(error) { console.error("NOTIFICATION_CONTRAST_FAIL " + error); Qt.quit() }
        }
    }
    Timer {interval:12000;running:true;onTriggered:{console.error("NOTIFICATION_CONTRAST_FAIL timeout");Qt.quit()}}
}
