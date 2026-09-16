import QtQuick
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
        outlineWidth: 1

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
        outlineWidth: 1

        Text { anchors.centerIn: parent; text: "continuous" }
    }

    // ---- both switches off ----------------------------------------------

    LiquidGlassPanel {
        id: flat
        x: 260
        y: 20
        width: 200
        height: 60
        radius: 12
        liquidEnabled: false
        blurEnabled: false
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

    readonly property real tokenExponent: AppearanceTokens.shape.cornerExponent

    property var failures: []

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
        check("round outline is a native border", round.glass.border.width === 1)

        // Above 2 the mask takes over. The body has to render square or the two
        // arcs disagree near the corner, the inset lines still need the visual
        // radius, and a straight border would be cut off by the mask.
        check("continuous turns the mask on", continuous.layer.enabled === true)
        check("continuous body renders square", continuous.glass.radius === 0)
        check("continuous inset keeps the radius",
            continuous.glass.cornerInset === 18)
        check("continuous native border off", continuous.glass.border.width === 0)
        check("caller content reaches the host", continuous.content.length === 1)

        // contentRadius is what a full-bleed child inside the panel needs: the
        // panel's own radius while it rounds itself, zero once the mask owns
        // the outline.
        check("contentRadius follows the mask",
            continuous.contentRadius === 0 && round.contentRadius === 18)

        // Strength zero is how LiquidGlassSurface disables a layer, so these
        // two assert the forwarding, not a reimplementation of the switch.
        check("liquidEnabled false zeroes the finish",
            flat.glass.liquidStrength === 0)
        check("blurEnabled false zeroes the fill", flat.glass.blurStrength === 0)

        // The body must not be hidden just because a host turned the blur off:
        // in a glass theme the fill is already transparent at blurStrength 0,
        // and the fallback below is what a host's own tonal identity rides on.
        // Only the tonal branch (where the body would paint an opaque material
        // layer over that fallback) makes it stand down, and that branch cannot
        // be reached from here -- flipping AppearanceConfigService.shellStyle
        // would persist a real user setting.
        check("body survives a host turning the blur off",
            flat.glass.visible === true)
        check("body shows while the backdrop is live", round.glass.visible === true)

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
        // barLength is max(28, round(dockWidth * 0.8)) = 240, so the capsule
        // radius is half the 6px thickness.
        check("dock pill exists", handle.visualPill !== null
            && handle.visualPill !== undefined)
        check("dock pill takes the token",
            handle.visualPill.cornerExponent === root.tokenExponent)
        check("dock pill capsule radius", handle.visualPill.radius === 3)
        check("dock pill mask follows the token",
            handle.visualPill.layer.enabled === (root.tokenExponent > 2))
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
        onTriggered: {
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
