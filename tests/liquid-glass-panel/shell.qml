import QtQuick
import Quickshell
import qs.desktop.modules.common
import qs.desktop.modules.dock

// Smoke host for LiquidGlassPanel.qml. Loaded offscreen by run.mjs.
//
// No pixel assertion is possible here: this environment has no GPU context
// (QOffscreenIntegration's QRhiGles2 cannot create one without DRM, a display
// or Xvfb), so the masked path is built but never rasterised. What this does
// cover is the wiring that breaks silently while editing -- a property the
// panel forwards to the body under the wrong name, a mask that stops turning on
// with the exponent, the body still rounding itself under the mask, or the
// default content alias swallowing the component's own children. Those are all
// load-time errors that no other test in the suite would see.
//
// The dock's Home Indicator is loaded too, because it is the panel's smallest
// and least forgiving consumer: a six-pixel capsule whose radius is half its
// height, so the mask has no straight edge to hide behind. If the panel's
// properties are renamed, this is where it shows up first.
Item {
    id: root

    width: 480
    height: 220

    // ---- the shipping default: exponent 2, every masked path off ---------

    LiquidGlassPanel {
        id: round
        x: 20
        y: 20
        width: 200
        height: 60
        radius: 18

        Text { anchors.centerIn: parent; text: "round" }
    }

    // ---- the opt-in: exponent above 2 hands the shape to the mask --------

    LiquidGlassPanel {
        id: continuous
        x: 20
        y: 100
        width: 200
        height: 60
        radius: 18
        cornerExponent: 4

        Text { anchors.centerIn: parent; text: "continuous" }
    }

    // ---- another independent shaped surface -----------------------------

    LiquidGlassPanel {
        id: flat
        x: 260
        y: 20
        width: 200
        height: 60
        radius: 12
    }

    // ---- caller content is re-parented ------------------------------------

    // The default alias moves everything the caller writes into the panel's
    // host item, which is a different object in a different subtree. Ids the
    // caller declares there have to keep resolving from the caller's own file
    // anyway -- DockWindowPreview reads `backgroundHover.hovered` from its
    // window root exactly this way, so a broken alias would be a load-time
    // ReferenceError in one popup and nowhere else.
    LiquidGlassPanel {
        id: aliased
        x: 260
        y: 100
        width: 200
        height: 60
        radius: 12

        Item { id: aliasedChild; objectName: "aliasedChild" }
    }

    // ---- a real consumer, wired to the shape token -----------------------

    // The Dock's Home Indicator. It reads the token rather than a literal, so
    // these assertions follow the token instead of pinning a value: flipping
    // cornerExponent must move this surface and nothing else has to be edited.
    DockRevealHandle {
        id: handle
        position: "bottom"
        windowWidth: root.width
        windowHeight: root.height
        dockWidth: 300
        dockHeight: 40
        fadeOpacity: 1.0
        active: true
    }

    // A PanelWindow combines independent panel declarations exactly as the
    // Dock does. This also makes the list-property reference syntax load in
    // the offscreen fixture rather than only in the live Dock.
    Region {
        id: combinedRegions
        regions: [round.blurRegion, handle.blurRegion]
    }

    readonly property real tokenExponent: AppearanceTokens.shape.cornerExponent

    property var failures: []

    // Text stays outside the background's corner texture when the content is
    // inset. Exercise both masks so disabling the content mask cannot leave
    // a square Material/fallback background behind sharp text.
    LiquidGlassPanel {
        id: insetPanel
        width: 200
        height: 60
        radius: 18
        cornerExponent: 4
        maskContent: false
        useKwinEffect: false
        ShellText { text: "应用程序 Applications"; x: 24; y: 20 }
    }

    ShellText { id: stationaryLabel; text: "菜单 Menu" }
    Item {
        id: textFrame
        Item {
            id: textHost
            ShellText { id: movingLabel; text: "启动器 Launcher" }
            GlassText { id: movingGlassLabel; text: "通知 Notification" }
        }
    }
    Item { id: scaledHost; scale: 0.8 }

    property int renderingStage: 0
    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            switch (root.renderingStage++) {
            case 0:
                root.check("stationary text uses platform rasterization",
                    stationaryLabel.renderType === Text.NativeRendering
                    && movingLabel.renderType === Text.NativeRendering
                    && movingGlassLabel.renderType === Text.NativeRendering)
                root.check("inset content bypasses the offscreen mask",
                    !insetPanel.layer.enabled && insetPanel.glass.layer.enabled)
                textFrame.scale = 0.9
                break
            case 1:
                root.check("ancestor scaling keeps text scalable",
                    movingLabel.renderType === Text.QtRendering
                    && movingGlassLabel.renderType === Text.QtRendering
                    && stationaryLabel.renderType === Text.NativeRendering)
                textFrame.scale = 1
                textFrame.rotation = 8
                break
            case 2:
                root.check("ancestor rotation keeps text scalable",
                    movingLabel.renderType === Text.QtRendering)
                textFrame.rotation = 0
                break
            case 3:
                root.check("settled text returns to native rendering",
                    movingLabel.renderType === Text.NativeRendering
                    && movingGlassLabel.renderType === Text.NativeRendering)
                movingLabel.parent = scaledHost
                break
            case 4:
                root.check("reparenting observes the new ancestor transform",
                    movingLabel.renderType === Text.QtRendering)
                movingLabel.parent = textHost
                break
            case 5:
                root.check("reparenting back restores native rendering",
                    movingLabel.renderType === Text.NativeRendering)
                movingLabel.scalableRendering = true
                break
            case 6:
                root.check("explicit transform-list opt-in stays scalable",
                    movingLabel.renderType === Text.QtRendering)
                movingLabel.scalableRendering = false
                stationaryLabel.x = 10.5
                insetPanel.maskContent = true
                break
            case 7:
                root.check("fractional placement alone stays native",
                    stationaryLabel.renderType === Text.NativeRendering
                    && movingLabel.renderType === Text.NativeRendering)
                root.check("whole-content masking avoids a duplicate body layer",
                    insetPanel.layer.enabled && !insetPanel.glass.layer.enabled)
                insetPanel.maskContent = false
                insetPanel.cornerExponent = 2
                break
            case 8:
                root.check("circular fallback needs neither offscreen mask",
                    !insetPanel.layer.enabled && !insetPanel.glass.layer.enabled
                    && insetPanel.glass.radius === 18)
                stop()
                break
            }
        }
    }

    function check(name, condition) {
        if (!condition)
            failures.push(name)
    }

    Component.onCompleted: {
        // Exponent 2 must render exactly what LiquidGlassSurface does on its
        // own, so the mask stays off and both the corner and the outline are
        // plain Rectangle properties.
        check("round stays unmasked", round.layer.enabled === false)
        check("round body keeps the radius", round.glass.radius === 18)
        check("round inset tracks radius", round.glass.cornerInset === 18)
        // The rim is KWin's job now: the panel zeroes the QML border in every
        // corner mode so a client-side edge cannot double up on the liquid rim.
        check("round outline is deferred to the compositor",
            round.glass.border.width === 0)

        // Above 2 the mask takes over. The body has to render square or the two
        // arcs disagree near the corner, the inset lines still need the visual
        // radius, and a straight border would be cut off by the mask.
        check("continuous turns the mask on", continuous.layer.enabled === true)
        check("continuous body renders square", continuous.glass.radius === 0)
        check("continuous inset keeps the radius",
            continuous.glass.cornerInset === 18)
        check("continuous keeps the same border posture",
            continuous.glass.border.width === 0)
        check("caller content reaches the host", continuous.content.length === 1)

        // contentRadius is what a full-bleed child inside the panel needs: the
        // panel's own radius while it rounds itself, zero once the mask owns
        // the outline.
        check("contentRadius follows the mask",
            continuous.contentRadius === 0 && round.contentRadius === 18)

        // In a glass theme KWin is the only material renderer. The QML body
        // exists solely for the tonal fallback, so it must be invisible here.
        check("glass panels have no QML material layer",
            round.glass.visible === AppearanceTokens.isMaterial
            && flat.glass.visible === AppearanceTokens.isMaterial)

        // Foreground roles are forwarded from the body; content reads against
        // them, so an undefined one is a silent invisible-text bug.
        check("foreground roles are forwarded",
            round.foregroundColor.a > 0 && round.secondaryForegroundColor.a > 0
            && round.tertiaryForegroundColor.a >= 0)

        // ---- caller content is re-parented ------------------------------
        check("caller content ids still resolve",
            aliasedChild.objectName === "aliasedChild")
        check("caller content ids reach the panel",
            aliasedChild.parent !== null && aliasedChild.parent !== aliased)

        // ---- the dock consumer ------------------------------------------
        // barLength is round(windowWidth * 0.5) = 240, so the capsule
        // radius is half the 6px thickness.
        check("dock pill exists", handle.visualPill !== null
            && handle.visualPill !== undefined)
        check("dock hint length follows the screen", handle.visualBar.width === 240)
        check("dock hint has its own stronger adaptive scrim",
            handle.visualPill._effectiveScrimCap === 0.90
            && handle.visualPill._effectiveScrimDecay === 1.0)
        handle.fadeOpacity = 0
        check("faded hint retires its compositor region", handle.blurRegion === null)
        handle.fadeOpacity = 1
        check("visible hint restores its compositor region", handle.blurRegion !== null)
        check("dock pill keeps its capsule profile",
            handle.visualPill.cornerExponent === 2.35)
        check("dock pill capsule radius", handle.visualPill.radius === 3)
        check("dock pill mask follows its profile",
            handle.visualPill.layer.enabled === true)
        check("panels expose compositor regions",
            round.blurRegion !== null && handle.blurRegion !== null
            && combinedRegions !== null)
        check("dock pill content radius follows the token",
            handle.visualPill.contentRadius
                === (root.tokenExponent > 2 ? 0 : 3))

        // Nothing above should have moved the exponent defaults.
        check("exponent defaults to circular",
            round.cornerExponent === 2 && round.continuousCorners === false)
    }

    // Let the scene graph attempt the layer pipelines so a failure inside the
    // effect surfaces before the shell exits.
    Timer {
        interval: 400
        running: true
        repeat: true
        onTriggered: {
            // Slow CI render loops may need more than 400ms for the staged
            // binding checks. The independent watchdog still bounds the run.
            if (root.renderingStage < 9)
                return
            if (root.failures.length > 0)
                console.error("LIQUID_GLASS_PANEL_FAIL: "
                    + root.failures.join("; "))
            else
                console.log("LIQUID_GLASS_PANEL_PASS")
            Qt.quit()
        }
    }

    Timer {
        interval: 6000
        running: true
        onTriggered: {
            console.error("LIQUID_GLASS_PANEL_FAIL: timeout")
            Qt.quit()
        }
    }
}
