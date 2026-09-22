import QtQuick

// Outer shadow for a squircle card.
//
//   KosCardShadow {
//       cardWidth: card.width
//       cardHeight: card.height
//       cornerRadius: card.radius
//       cornerExponent: card.cornerExponent
//       x: card.x - margin
//       y: card.y - margin
//   }
//
// This is an outer-only effect: the shader cuts the card's own outline out of
// the field before painting, so no pixel is ever drawn *under* the card. A
// translucent surface cannot carry a shadow underneath it -- the glass would
// show the darkening through itself and read grey, worst along its own edge --
// which also rules out DropShadow and MultiEffect.shadowEnabled: both composite
// their shadow below the source by construction, with no way to subtract the
// source from it.
//
// Painted by shaders/card_shadow.frag, which evaluates the same superelliptical
// field as SquircleMask, so the card's edge and the shadow's hole describe one
// curve rather than two that agree only by convention.
ShaderEffect {
    id: root

    // The card's size and shape, passed in so the shadow follows a resizing or
    // animating card without a second source of truth for the outline.
    property real cardWidth: 0
    property real cardHeight: 0
    property real cornerRadius: 0
    // 2.0, not the squircle token's 3.0: at 2 the shader's distance field is
    // the classic rounded-box SDF (one length(), no pow()), and a host that
    // does not say otherwise pays the cheap path. KosFloatPanel still passes
    // AppearanceTokens.shape.cornerExponent explicitly, so a squircle card
    // keeps a squircle hole -- the field has to match the mask's curve or the
    // two edges split around 45 degrees.
    property real cornerExponent: 2.0

    // Cast direction in pixels. Positive Y casts downwards, so the usual "light
    // from the top left" is a positive pair.
    property real offsetX: 8
    property real offsetY: 10
    // How far the shadow fades past its own edge, and how much it is grown
    // before fading so it stays solid right up to the card.
    // 24, not 56: softness also feeds `margin`, so the old default grew the
    // item ~130px past the card on every side and ran the SDF over all of it.
    // 24 still reads as a soft cast shadow and roughly halves the shaded
    // area. KosFloatPanel sets its own value, so only future default users
    // see this change.
    property real softness: 24
    property real spread: 0
    // Retained for source compatibility -- nothing reads it anymore. The
    // shader replaced pow(alpha, falloff) with a fixed alpha*alpha curve: the
    // per-pixel pow() cost an exp2/log2 pair on every fragment while no host
    // ever tuned the knob. The uniform stays in the block because the vertex
    // stage shares this buffer's layout.
    property real falloff: 1.0
    property color shadowColor: Qt.rgba(0, 0, 0, 0.50)

    // 0 in normal use. Anything else paints a probe instead of a shadow:
    //   1 = the card's coverage (white inside the outline, black outside),
    //       which shows whether the hole lands where the card actually is;
    //   2 = the cast shape (red inside the shadow's own outline, blue outside);
    //   3 = flat green over the item's full extent -- if that green block stops
    //       at the card's edge, something outside this shader is clipping the
    //       surface, not mis-shaping the shadow.
    property real debugMode: 0

    // Hidden until there is a card to cast from. A dialog measures its card
    // through its content, and that content is empty for a frame or two while the
    // layer surface maps (an unmapped surface reports width 0, so the content's
    // width comes out 0 as well). A shadow drawn from that reading has halfSize 0
    // and radius 0, so it degenerates into a block of shading over the whole item
    // instead of a shadow around a card.
    property bool castEnabled: true
    readonly property bool castReady: castEnabled && cardWidth > 1 && cardHeight > 1
    visible: castReady

    // The item is grown around the card, which stays centred inside it -- the
    // shader works from that shared centre, so a host only has to offset its
    // position by `margin` on both axes.
    readonly property real margin: Math.ceil(
        Math.max(Math.abs(offsetX), Math.abs(offsetY)) + softness + spread + 1)
    width: cardWidth + margin * 2
    height: cardHeight + margin * 2

    // Explicit, like SquircleMask's maskWidth/maskHeight: a qualified reference
    // cannot silently pick up the wrong object at a nested call site.
    property real shadowWidth: width
    property real shadowHeight: height

    // Qt's built-in vertex shader only carries 150/120/100 variants, while a
    // fragment stage baked with a wider set comes back as #version 440 and Mesa
    // refuses to link the pair (see shaders/compile.sh). Pairing our own two
    // stages keeps them on the same profile -- and the vertex stage is what
    // hands the fragment its item-local coordinate, so it does not depend on
    // texture coordinates a sourceless ShaderEffect may never receive.
    vertexShader: Qt.resolvedUrl("../../shaders/card_shadow.vert.qsb")
    fragmentShader: Qt.resolvedUrl("../../shaders/card_shadow.frag.qsb")

    // Logged at creation *and* on every geometry change: creation happens before
    // the card's content has been laid out (the dialog is still unmapped and
    // narrow then), so the creation line alone reports a transient size.
    Component.onCompleted: _log("created")
    onCardWidthChanged: _log("resized")
    onCardHeightChanged: _log("resized")

    function _log(tag) {
        // Silent in normal use: these lines exist to diagnose a mis-wired or
        // mis-sized host, which is exactly what the probes above are for.
        if (debugMode === 0)
            return
        console.log("[KosCardShadow] " + tag + " card=" + cardWidth + "x"
            + cardHeight + " margin=" + margin + " item=" + width + "x" + height
            + " offset=" + offsetX + "," + offsetY + " softness=" + softness
            + " spread=" + spread + " falloff=" + falloff
            + " color=" + shadowColor + " debug=" + debugMode)
        // Read again once the event loop has turned: bindings derived from
        // cardWidth still report their previous value inside the change handler,
        // so this second line is the one that carries the settled geometry --
        // and `expect` is what `item` must equal if the binding is alive at all.
        Qt.callLater(function() {
            console.log("[KosCardShadow] " + tag + "-settled card=" + cardWidth + "x"
                + cardHeight + " item=" + width + "x" + height
                + " expect=" + (cardWidth + margin * 2) + "x"
                + (cardHeight + margin * 2) + " debug=" + debugMode)
        })
    }
}
