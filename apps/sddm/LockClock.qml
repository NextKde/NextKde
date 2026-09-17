/*
    SPDX-FileCopyrightText: 2026 KOS

    SPDX-License-Identifier: GPL-2.0-or-later
*/

// LockClock.qml exists twice, byte-for-byte:
//     apps/sddm/LockClock.qml
//     apps/lockscreen/contents/lockscreen/LockClock.qml
// The SDDM theme and the Plasma lock screen are separate greeter processes, and
// each loads its package from its own directory, so neither can import the
// other's copy -- the duplication is structural, not an oversight. Keep the two
// files identical: edit one, then copy it over the other.

import QtQuick

// The oversized clock the lock screen puts at the top: the date in a small line
// above, the time in a very large one below.
//
// The numerals are glass. What that means here is not a metaphor, it is a
// recipe with numbers in it, and the numbers were measured off a photograph of
// the real thing rather than guessed. A horizontal scan through a vertical
// stroke of the reference, from the backdrop inwards, reads:
//
//   backdrop (76,138,174) -> edge (151,206,233) -> body (142,189,222) -> ...
//
// Two things follow, and both of them are the opposite of what this file used
// to do. The body is *lighter* than the wallpaper, not darker: the material is
// a translucent white laid over the picture, so the digits must be white at low
// alpha rather than black at low alpha. And the edge is only about 20 levels
// above the body -- a hairline of light along the contour, not the 4px solid
// white stroke that turns a numeral into a sticker. The earlier revision was a
// black fill under a fat outline, which is a caricature of glass: it reads as a
// hole cut in the wallpaper with a chalk line around it.
//
// So the material is a vertical gradient of white, and the rim is a one-pixel
// line whose own gradient runs from bright at the top of the glyphs to dim at
// the bottom, because the light in the reference falls from above.
//
// What is NOT here, and why
// -------------------------
// Real Liquid Glass refracts: it samples the backdrop through the glyph, blurs
// it, and displaces it near the edges. That needs a mask of the glyph shape,
// and on this Qt there is no way to make one that survives contact with the
// renderer. Measured, not assumed (see .build/glassprobe):
//
//   - `Canvas.drawImage` is a no-op for every source: a URL, the object
//     `Canvas.loadImage()` returns (which comes back with no size at all), and
//     a QML `Image` item. Nothing is drawn, and nothing is reported.
//   - `globalCompositeOperation = "destination-in"` is a no-op too, so a glyph
//     drawn with `fillText` cannot mask anything.
//   - `ctx.filter` is `undefined`; there is no blur.
//   - `QtQuick.Effects` (MultiEffect, which does have a `maskSource` and would
//     do the whole thing in ten lines) is a shader, and therefore invisible
//     under a software renderer -- which is both how this clock is previewed
//     and a state a greeter can legitimately come up in.
//
// A lock screen is the one window a user cannot get around, so nothing in it
// may be allowed to render as "probably fine". The material below is built out
// of primitives that paint identically under every backend.
//
// The fill is a plain `Text` and the rim is a `Canvas` on top of it. That split
// is about failure, not about drawing: the part that has to be there -- the
// numbers themselves -- is the part built out of the most basic type in
// QtQuick. If the canvas never paints its gradient, a flat white time is still
// on screen. The canvas only ever adds to it.
//
// Why not do the numerals in `Text` alone, as the first revisions did?
//
//   - `Text.Outline` is not an outline. Qt draws it by stamping the *filled*
//     glyph at eight one-pixel offsets in the style colour, so any white
//     treatment wide enough to see also floods the interior white.
//   - QtQuick has no text shadow, and no way to give a `Text` a gradient.
//
// Nothing moves: no drifting highlight, no parallax.
Item {
    id: clock

    property date now: new Date()

    // 0 on the first frame, 1 once the clock has settled. Drives the entry
    // animation: a lock screen that is simply there on the first frame reads as
    // a screenshot rather than as something the session just put in front of
    // you.
    property real reveal: 0

    // Mirrors LockScreen.dismiss. It is subtracted from `reveal` rather than
    // fading `opacity` on its own, so the entry curve and the exit fade
    // compose instead of the second one restarting the first.
    property real dismiss: 0

    property real spacingV: Math.round(clock.screenHeight * 0.004)

    // The panel the sizes below are derived from. Normally just `Screen`, but
    // spelled out and writable because an offscreen render has no panel: Qt's
    // offscreen platform reports a fixed 800x800, so a harness that wants to
    // preview this clock at 16:9 has to say so. Nothing in the greeter ever
    // writes these.
    property real screenHeight: Screen.height
    property real screenWidth: Screen.width

    // Formatted once, here, rather than inside each piece. The Canvas lays the
    // same string out again glyph by glyph; letting the two format their own is
    // how one of them ends up a minute behind the other.
    readonly property string timeString: Qt.formatTime(clock.now, "HH:mm")

    // Both sizes are read from here rather than computed at the `font` group,
    // because `font.letterSpacing` cannot derive from `font.pixelSize`: the two
    // are the same group and the read-back loops.
    //
    // The time is clamped by width as well as height -- on a portrait or a
    // narrow screen the height-derived size alone runs the numerals off the
    // sides.
    readonly property int datePixelSize: Math.round(clock.screenHeight * 0.028)

    // The date's own breathing room for its glass. A fraction of the date's
    // type, not the numerals': at 30px the numerals' pad would be a third of
    // the line height again.
    readonly property int datePad: Math.max(4, Math.round(clock.datePixelSize * 0.35))
    readonly property int timePixelSize: Math.min(Math.round(clock.screenHeight * 0.19),
                                                  Math.round(clock.screenWidth * 0.25))

    // Weight and width of the numerals.
    //
    // Both were measured off the reference rather than chosen, because "the
    // glass looks crude" turned out to be a complaint about the letterforms.
    // Its strokes are 30px wide against a 406px cap height -- a ratio of
    // 0.074. Inter Display runs 0.124 at Light through 0.295 at Bold, so the
    // weight the file used to ship was four times too heavy; Light is the
    // lightest cut installed, and it lands on 0.080 once the line is squeezed
    // to four fifths of its width.
    //
    // Measured against the reference it is still too heavy, and deliberately
    // so: at 300 the strokes could not carry the bevel below, and a numeral
    // that cannot show its own thickness reads as flat print rather than as
    // glass. Medium is the point where the bevel has an edge to sit on and the
    // counters of the 8 and the 9 have not started closing up at 200px. Drop
    // it to Font.Normal (400) for the reference's weight, or Font.Light (300)
    // for what this shipped with.
    //
    // The width itself is a compromise and cannot be closed. The reference's
    // glyphs are 0.24 as wide as they are tall; Inter Display's are 0.65 at
    // any weight. No installed face is anywhere near that narrow, and it is
    // worth saying why rather than chasing it: no typeface reaches 0.24, so
    // the reference is a render with its type squeezed, not a screenshot of a
    // font someone could install. Matching it exactly would mean scaling the
    // numerals to a third of their width, which stops looking like a clock.
    // 0.85 was what that reference implied; it also left the numerals looking
    // like they were holding their breath. 0.95 is as wide as the line goes
    // before it stops reading as a clock and starts reading as bold text, and
    // it keeps the counters of the 8 and the 9 open at 200px.
    //
    // `timeCondense` is a horizontal scale on the whole line rather than
    // `font.stretch`, which only selects a face the family already ships -- a
    // static Inter has no condensed cut to select, and Qt does not synthesise
    // one. Scaling the item scales the fill and the rim together, so the two
    // cannot drift apart.
    property int timeWeight: Font.Medium
    property real timeCondense: 0.95

    // iOS sets its lock clock tight. At this size the default tracking reads as
    // loose and thin next to the real thing. Both renderers read this, so the
    // fill and the rim cannot drift apart.
    readonly property int timeTracking: -Math.round(clock.timePixelSize * 0.022)

    // The font both renderers use. Spelled out rather than left to each default,
    // because the Canvas sets its font through a CSS string and has to name a
    // family explicitly -- an empty name there would silently fall back to a
    // different face than the Text above it.
    //
    // Inter Display is preferred where it exists: it is the same skeleton as
    // Inter, cut for the optical size this clock is drawn at, which is what
    // keeps the counters from closing up at 200px.
    readonly property string fontFamily: {
        const families = Qt.fontFamilies()
        for (let i = 0; i < families.length; ++i) {
            if (families[i] === "Inter Display")
                return "Inter Display"
        }
        return Qt.application.font.family.length > 0
            ? Qt.application.font.family
            : "sans-serif"
    }

    // Rim thickness and the room the drop needs. Both are fractions of the
    // numeral, so the clock keeps its proportions on any screen.
    //
    // The rim is a hairline on purpose. Measured against the reference, the lit
    // edge is roughly half a percent of the numeral's own height -- at 205px
    // that is barely more than one pixel, and it has to be left fractional, or
    // rounding to whole pixels either erases it or doubles it.
    readonly property real rimWidth: Math.max(1, clock.timePixelSize * 0.007)
    readonly property int rimPad: Math.round(clock.timePixelSize * 0.26)

    // Pinned rather than inherited. The format string below is written in
    // Chinese anyway, so a session that ended up with an English locale would
    // render "9月17日 Thursday" -- half of it in the wrong language.
    readonly property var dateLocale: Qt.locale("zh_CN")

    width: textStack.width
    height: textStack.height
    opacity: Math.max(0, clock.reveal - clock.dismiss)
    // The clock grows into place on the way in, and keeps growing a little as
    // the screen hands over to the desktop on the way out.
    scale: 0.96 + 0.04 * clock.reveal + 0.05 * clock.dismiss

    NumberAnimation on reveal {
        from: 0
        to: 1
        duration: 700
        easing.type: Easing.OutCubic
    }

    // The canvas is not repainted for us: its contents depend on the string, and
    // the string changes without the canvas changing size.
    onTimeStringChanged: rim.requestPaint()
    onTimePixelSizeChanged: rim.requestPaint()
    onTimeTrackingChanged: rim.requestPaint()
    onTimeWeightChanged: rim.requestPaint()

    Column {
        id: textStack
        width: Math.max(dateText.implicitWidth, timeLine.width)
        spacing: clock.spacingV

        // The date, in the same glass as the numerals. Weekday first -- "星期四
        // 9月17日", the order the reference reads in -- and built like the time
        // line: a Text for the fallback and a Canvas for the material, with
        // `mapFromItem` supplying where the glyphs actually landed.
        Item {
            id: dateLine
            anchors.horizontalCenter: parent.horizontalCenter
            width: dateText.implicitWidth + clock.datePad * 2
            height: dateText.implicitHeight + clock.datePad * 2

            property real paintOriginX: 0
            property real paintOriginY: 0

            Text {
                id: dateText
                // Named for the harness, which has no other way to reach into
                // the column and read what the date actually formatted to.
                objectName: "clockDateText"
                anchors.centerIn: parent
                // Formatted through the locale object rather than through
                // `Qt.formatDate(date, locale, format)`. That overload exists,
                // but it ignores the format string and answers with the
                // locale's long date -- "2026年9月17日星期四" where "星期四
                // 9月17日" was asked for. `Locale.toString` honours both.
                text: clock.dateLocale.toString(clock.now, "dddd M月d日")
                color: dateGlass.painted ? "transparent" : Qt.rgba(1, 1, 1, 0.92)
                font.family: clock.fontFamily
                font.pixelSize: clock.datePixelSize
                font.weight: Font.Medium

                onTextChanged: dateGlass.requestPaint()
            }

            Canvas {
                id: dateGlass

                readonly property real ratio: Math.max(1, Screen.devicePixelRatio)

                property bool painted: false

                anchors.centerIn: parent
                width: Math.round((dateLine.width + clock.datePad) * dateGlass.ratio)
                height: Math.round((dateLine.height + clock.datePad) * dateGlass.ratio)

                transform: Scale {
                    origin.x: dateGlass.width / 2
                    origin.y: dateGlass.height / 2
                    xScale: 1 / dateGlass.ratio
                    yScale: 1 / dateGlass.ratio
                }

                onPaint: timeLine.paintGlassInto(getContext("2d"), {
                    ratio: dateGlass.ratio,
                    canvas: dateGlass,
                    textItem: dateText,
                    text: clock.dateLocale.toString(clock.now, "dddd M月d日"),
                    pixelSize: clock.datePixelSize,
                    weight: Font.Medium,
                    tracking: 0,
                    target: dateLine,
                    alphaBoost: 1.15
                })
            }
        }

        // The numerals. The Text is the fallback and the Canvas is everything
        // happening on the surface of the glass; both are centred on this item,
        // which is the item the column lays out.
        Item {
            id: timeLine
            anchors.horizontalCenter: parent.horizontalCenter
            width: timeText.implicitWidth + clock.rimWidth * 2
            height: timeText.implicitHeight + clock.rimWidth * 2

            // Where the last paint put the numerals, in canvas pixels. Nothing
            // in the theme reads these; the headless harness does. The glass
            // and the Text are two renderers of one string, and the only way
            // to prove they agree on where that string is -- which a 1x render
            // cannot show, because at ratio 1 every wrong formula agrees --
            // is to compare them from outside.
            property real paintOriginX: 0
            property real paintOriginY: 0

            transform: Scale {
                origin.x: timeLine.width / 2
                origin.y: timeLine.height / 2
                xScale: clock.timeCondense
                yScale: 1
            }

            // The fallback: near-solid white, which is legible over anything.
            // It is only ever seen if the canvas below fails to paint, and the
            // canvas says so by setting its own `painted` flag. The colour is
            // taken to transparent rather than the item hidden, because a
            // positioner skips invisible children and this Text is what the
            // column above sizes itself from.
            Text {
                id: timeText
                objectName: "clockTimeText"
                anchors.centerIn: parent
                text: clock.timeString
                color: rim.painted ? "transparent" : Qt.rgba(1, 1, 1, 0.88)
                font.family: clock.fontFamily
                font.pixelSize: clock.timePixelSize
                font.weight: clock.timeWeight
                font.letterSpacing: clock.timeTracking
            }

            // The material. Drawn larger than the item and scaled back down by
            // `ratio`: a Canvas draws at its own size in logical pixels and its
            // texture is then stretched by the screen's scale factor, which on a
            // 2x panel is exactly the difference between a crisp numeral and a
            // soft one. Drawing into a canvas that is `ratio` times too big and
            // shrinking it with a transform puts the extra pixels where they
            // belong. The obvious knob for this, `canvasSize`, takes the canvas
            // off screen entirely on this Qt, so it is not used.
            Canvas {
                id: rim
                objectName: "clockTimeRim"

                readonly property real ratio: Math.max(1, Screen.devicePixelRatio)

                // Set by the paint below. Doubles as the flag that says the
                // fallback Text may go away.
                property bool painted: false

                anchors.centerIn: parent
                width: Math.round((timeLine.width + clock.rimPad * 2) * rim.ratio)
                height: Math.round((timeLine.height + clock.rimPad * 2) * rim.ratio)

                transform: Scale {
                    origin.x: rim.width / 2
                    origin.y: rim.height / 2
                    xScale: 1 / rim.ratio
                    yScale: 1 / rim.ratio
                }

                onPaint: timeLine.paintGlassInto(getContext("2d"), {
                    ratio: rim.ratio,
                    canvas: rim,
                    textItem: timeText,
                    text: clock.timeString,
                    pixelSize: clock.timePixelSize,
                    weight: clock.timeWeight,
                    tracking: clock.timeTracking,
                    target: timeLine
                })
            }

            // Stroke each glyph where the Text drew it, rather than laying the
            // string out again: the two renderers share a font, a size and a
            // tracking value, but only one of them knows where the baseline
            // actually landed. Taking the origin from the Text and the advances
            // from the same font keeps the rim on the numerals instead of
            // approximately near them.
            // One material, every line of the clock. The spec names the canvas
            // that will be painted into, the Text whose glyphs are being
            // restroked, and the type -- so the date line asks for exactly the
            // same recipe the numerals get, at its own size.
            function paintGlassInto(ctx, spec) {
                const ratio = spec.ratio
                const w = spec.canvas.width
                const h = spec.canvas.height

                ctx.setTransform(1, 0, 0, 1, 0, 0)
                ctx.clearRect(0, 0, w, h)

                const size = spec.pixelSize * ratio
                const track = spec.tracking * ratio
                // Same face and weight as the Text above it. The weight goes in
                // as the number QML uses, which is also what CSS takes.
                ctx.font = spec.weight + " " + size + "px \"" + clock.fontFamily + "\""
                ctx.textAlign = "left"
                ctx.textBaseline = "alphabetic"
                ctx.lineJoin = "round"

                // The Text's baseline origin, in this canvas's own coordinates.
                //
                // The canvas is drawn `ratio` times too big and scaled back
                // down about its own centre, so the box it covers is not
                // `rim.x .. rim.x + rim.width`: those are untransformed
                // coordinates, in which the canvas is `ratio` times bigger
                // than the box it paints. `mapFromItem` is the only thing that
                // knows where that box really is, so the origin is taken from
                // it -- and a canvas's own units *are* its pixel grid, so the
                // answer needs no further scaling.
                //
                // Reading `rim.x`/`rim.y` instead, as this did, is right by
                // accident at ratio 1 (there the transform is the identity)
                // and pushes the numerals out of the canvas at every ratio
                // above it. Measured off a 1200x800 render: at 1.5x the last
                // glyph is cut off, at 2x every numeral loses its right side
                // and its foot -- while the canvas still reports itself
                // painted, so the fallback Text goes transparent and the clock
                // reads as missing rather than as broken.
                const origin = spec.canvas.mapFromItem(spec.textItem.parent,
                                                       spec.textItem.x,
                                                       spec.textItem.y + spec.textItem.baselineOffset)
                const originX = origin.x
                const originY = origin.y
                if (spec.target) {
                    spec.target.paintOriginX = originX
                    spec.target.paintOriginY = originY
                }

                const chars = spec.text.split("")
                const widths = []
                for (let i = 0; i < chars.length; ++i)
                    widths[i] = ctx.measureText(chars[i]).width

                // The light in the reference falls from above: the material is
                // brighter along the top of the numerals and settles as it
                // descends, and the rim follows it, from a nearly solid edge at
                // the top to a suggestion at the foot. Cap height is about 0.72
                // of the pixel size, which is where the gradient is pinned
                // rather than at the item's box -- the box also holds the
                // descender space no digit ever uses.
                const capTop = originY - size * 0.72

                // The body is a pale, faintly cool white rather than a neutral
                // one. Solving the reference for "overlay colour over alpha"
                // against three different points of its sky gives a colour near
                // (186,223,254) at about 0.6 -- an ice blue, not white. That is
                // what a *blurred* blue sky does to a white tint, and since the
                // blur is the one part of this that cannot be reproduced here,
                // the tint is where its effect is kept: the same colour at a
                // slightly lower alpha, so the digits still sit on a wallpaper
                // they can be seen through.
                //
                // The numbers were checked against the reference on a backdrop
                // of exactly its own sky (76,138,174): the body lands on
                // (142,188,214) where the reference reads (142,189,222).
                // Small type cannot carry the alphas 200px numerals carry: at
                // 30px the material is a much larger share of each stroke, so
                // the caller can ask for a boost and still land on the same
                // perceived glass.
                const boost = spec.alphaBoost ?? 1.0

                const body = ctx.createLinearGradient(0, capTop, 0, originY)
                body.addColorStop(0.0, "rgba(210,239,255," + Math.min(1, 0.54 * boost).toFixed(3) + ")")
                body.addColorStop(0.55, "rgba(210,239,255," + Math.min(1, 0.48 * boost).toFixed(3) + ")")
                body.addColorStop(1.0, "rgba(210,239,255," + Math.min(1, 0.42 * boost).toFixed(3) + ")")

                // The drop is short and faint. The reference has almost none --
                // the backdrop measured clean right up against the contour --
                // but a lock screen cannot count on a dark wallpaper, and a
                // little separation under the glyphs is what keeps pale glass
                // readable on a pale picture. Faint enough that it reads as
                // thickness rather than as a shadow.
                ctx.shadowColor = "rgba(0, 0, 0, 0.18)"
                ctx.shadowBlur = size * 0.07
                ctx.shadowOffsetY = size * 0.014
                ctx.fillStyle = body

                let x = originX
                for (let i = 0; i < chars.length; ++i) {
                    ctx.fillText(chars[i], x, originY)
                    x += widths[i] + track
                }

                // ---- thickness ------------------------------------------
                //
                // The glass is a slab with a side to it, not a decal, and that
                // is two more passes over the same glyphs: one dark, dropped a
                // little, for the far wall; one bright, lifted a little, for
                // the near edge catching the light from above.
                //
                // Offsetting whole copies is the only way to get this out of a
                // context2d that cannot mask: there is no path for a glyph
                // here, so an inner bevel cannot be clipped to the shape
                // (`destination-in` is a no-op on this Qt, `ctx.filter` does
                // not exist, and MultiEffect is a shader). What is left is
                // drawing the shape again, somewhere else, in a colour that
                // belongs to one side of it.
                //
                // Both offsets are fractions of the numeral so they scale with
                // it, and small: at 205px that is about three pixels down and
                // two up, which is the difference between thickness and a drop
                // shadow.
                const sink = size * 0.016
                const lift = size * 0.010

                ctx.shadowColor = "rgba(0, 0, 0, 0)"

                // The far wall. Transparent over the top of the glyphs and
                // dark only at the foot, so it does not tint the whole numeral
                // -- the body above is translucent, and a flat copy underneath
                // it would show through as a general darkening. Dropped below
                // the contour, it also leaves the few pixels of darker glass
                // under the foot that read as the slab's own thickness.
                const wall = ctx.createLinearGradient(0, capTop, 0, originY + sink)
                wall.addColorStop(0.0, "rgba(14,34,52,0.00)")
                wall.addColorStop(0.55, "rgba(14,34,52,0.10)")
                wall.addColorStop(1.0, "rgba(14,34,52,0.42)")
                ctx.fillStyle = wall

                x = originX
                for (let i = 0; i < chars.length; ++i) {
                    ctx.fillText(chars[i], x, originY + sink)
                    x += widths[i] + track
                }

                // The near edge. Same trick lifted instead of dropped, and
                // short: bright at the crown, gone by a third of the way down,
                // so only the top contour picks it up. The fringe it leaves
                // above the glyph is a pixel or two of extra light along the
                // edge, which is what a lit bevel looks like from the front.
                const bevel = ctx.createLinearGradient(0, capTop - lift, 0,
                                                       capTop + size * 0.30)
                bevel.addColorStop(0.0, "rgba(255,255,255,0.40)")
                bevel.addColorStop(0.45, "rgba(255,255,255,0.15)")
                bevel.addColorStop(1.0, "rgba(255,255,255,0.00)")
                ctx.fillStyle = bevel

                x = originX
                for (let i = 0; i < chars.length; ++i) {
                    ctx.fillText(chars[i], x, originY - lift)
                    x += widths[i] + track
                }

                // The rim, without the shadow the body carried.
                //
                // Faint on purpose, and the numbers came off the same scan as
                // the body: against the reference, the lit edge sits only about
                // twenty levels above the body it wraps, where a rim at the
                // alpha this started at measured almost seventy above it. A
                // bright outline around a dim glyph is a sticker no matter how
                // thin it is.
                const edge = ctx.createLinearGradient(0, capTop, 0, originY)
                edge.addColorStop(0.0, "rgba(255,255,255," + Math.min(1, 0.30 * boost).toFixed(3) + ")")
                edge.addColorStop(0.45, "rgba(255,255,255," + Math.min(1, 0.20 * boost).toFixed(3) + ")")
                edge.addColorStop(1.0, "rgba(255,255,255," + Math.min(1, 0.12 * boost).toFixed(3) + ")")

                ctx.shadowColor = "rgba(0, 0, 0, 0)"
                ctx.lineWidth = clock.rimWidth * ratio
                ctx.strokeStyle = edge

                x = originX
                for (let i = 0; i < chars.length; ++i) {
                    ctx.strokeText(chars[i], x, originY)
                    x += widths[i] + track
                }

                if (!spec.canvas.painted)
                    spec.canvas.painted = true
            }
        }
    }
}
