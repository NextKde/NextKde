import QtQuick
import Kos.Ui

// Palette for the calculator. Dark values are measured from the reference
// screenshots (tmp/ui-replication/calculator/reference/) with the display's
// wallpaper cast neutralised; see LEDGER.md for the per-swatch provenance.
// Light values are an extrapolation — no light reference exists — and keep the
// same role ordering with the lightness ramp inverted.
QtObject {
    id: palette

    readonly property bool dark: AppTheme.dark

    // --- planes -------------------------------------------------------
    // The keypad sits on the window's own plane; the history column is a
    // second, slightly deeper plane flush against it. There is no third one:
    // the landscape reference's display band was the phone's wallpaper showing
    // through its glass, not a plane of its own, so the scientific view reads
    // on this same plane.
    readonly property color plane: dark ? "#484846" : "#F2F2F0"
    readonly property color historyPlane: dark ? "#3C3C3A" : "#E2E2E0"
    readonly property color historySeam: dark ? "#232321" : "#C6C6C4"
    readonly property color historyDivider: dark ? Qt.rgba(1, 1, 1, 0.12)
                                                 : Qt.rgba(0, 0, 0, 0.10)

    // --- keys ---------------------------------------------------------
    // Basic / history keypad: dark round keys on the plane, a light grey
    // function group, and the orange operator column.
    readonly property color keyNumber: dark ? "#383838" : "#FFFFFF"
    readonly property color keyFunction: dark ? "#A2A2A2" : "#D4D4D2"
    readonly property color keyOperator: "#FF9F0A"

    // Scientific keypad: capsule keys. The landscape reference lights three
    // groups over a black page — the function columns at 36, the number block
    // at 52, and AC and % at 96 — and those three are carried as the measured
    // hexes rather than as washes. A wash would have to be read against that
    // black page to mean anything, and our plane is not black: re-derived over
    // it the three tones land 98/109/141 and the ramp flattens to nothing.
    // Copying them keeps the step between the groups, which is what the
    // reference is actually showing; the cost is that its keys sit above its
    // page and ours sit below it.
    readonly property color sciKey: dark ? "#242424" : "#D4D4D2"
    readonly property color sciKeyNumber: dark ? "#343434" : "#FFFFFF"
    readonly property color sciKeyLight: dark ? "#606060" : "#BEBEBC"

    // --- labels -------------------------------------------------------
    // The function keys are the light grey group in either mode, so their label
    // is black in either mode. The digits are the dark group in the dark
    // palette and the light one in the light palette, so their label flips with
    // the plane — and it is also the label the whole scientific keypad uses.
    readonly property color textOnNumber: dark ? "#FFFFFF" : "#000000"
    readonly property color textOnFunction: "#000000"
    readonly property color textOnOperator: "#FFFFFF"
    readonly property color displayText: dark ? "#FFFFFF" : "#000000"
    // The expression line above the result. Measured off the iOS reference at
    // #8F8F92 on pure black — i.e. 58% white — and copied as the wash rather
    // than the hex, for the same reason the chrome buttons are: our display
    // strip is #3A3A38, not black, and the absolute value would read dimmer
    // here than it does there.
    readonly property color displayExpression: dark ? Qt.rgba(1, 1, 1, 0.58)
                                                    : Qt.rgba(0, 0, 0, 0.58)

    // --- convert view -------------------------------------------------
    // The unit codes beside each of the two numbers, and the chevrons that open
    // the picker: measured off the reference at (145,145,146) on black, i.e.
    // 57% white — a shade darker than the expression line above it, and carried
    // as the wash for the same reason.
    readonly property color convertUnit: dark ? Qt.rgba(1, 1, 1, 0.57)
                                              : Qt.rgba(0, 0, 0, 0.57)
    // The hairline between the two rows. Measured at (41,41,41) on black, 16%
    // white, and it is the same weight as the menu's own border — a rule, not a
    // divider between two surfaces.
    readonly property color convertRule: dark ? Qt.rgba(1, 1, 1, 0.16)
                                              : Qt.rgba(0, 0, 0, 0.12)

    // --- history column ----------------------------------------------
    readonly property color historyHeader: dark ? Qt.rgba(1, 1, 1, 0.62)
                                                 : Qt.rgba(0, 0, 0, 0.55)
    readonly property color historyExpression: dark ? Qt.rgba(1, 1, 1, 0.42)
                                                     : Qt.rgba(0, 0, 0, 0.45)
    readonly property color historyResult: dark ? "#FFFFFF" : "#000000"
    readonly property color iconTint: dark ? Qt.rgba(1, 1, 1, 0.55)
                                           : Qt.rgba(0, 0, 0, 0.55)
    readonly property color iconTintActive: dark ? "#FFFFFF" : "#000000"

    // --- history edit bar ---------------------------------------------
    // The iOS history sheet's "Edit" and "Clear All" pills are a flat wash over
    // its own plane — #39383B on #1B1B1B, i.e. 13% white — so that is what is
    // copied, not the hex. Its destructive label measures #BF3B3D, well short
    // of the system red, and that is the red used here.
    readonly property color historyPill: dark ? Qt.rgba(1, 1, 1, 0.13)
                                              : Qt.rgba(0, 0, 0, 0.08)
    readonly property color historyPillText: dark ? "#FFFFFF" : "#000000"
    readonly property color destructive: dark ? "#BF3B3D" : "#C0392B"
    // The hollow circles on each line while editing: a thin 30% white ring,
    // measured off the reference.
    readonly property color selectionRing: dark ? Qt.rgba(1, 1, 1, 0.30)
                                                : Qt.rgba(0, 0, 0, 0.26)

    // --- chrome -------------------------------------------------------
    // The reference's menu is #1F1F1F against a #333333 key, i.e. it is the
    // deepest thing on screen — a recess, not a lift — and that is how it reads
    // where it actually appears, over the keypad. Carried over at the same
    // ratio to our key (#383838).
    readonly property color menuSurface: dark ? "#262624" : "#FFFFFF"
    readonly property color menuBorder: dark ? Qt.rgba(1, 1, 1, 0.16)
                                             : Qt.rgba(0, 0, 0, 0.12)
    // The reference lights the row under the finger at 19.6% white over the
    // panel. That wash is not carried as a colour: the row's feedback is the
    // shared SelectionHighlight plate — the same one the shell's context menu
    // uses — which builds its own gradient, rim and top glint. See
    // CalculatorMenuItem.
    readonly property color menuText: dark ? "#FFFFFF" : "#000000"
    // The menu's tick is the same white as its label (measured off the iOS
    // reference); the accent is spent on the operator column alone.
    readonly property color menuCheck: dark ? "#FFFFFF" : "#000000"
    // The hairline between the calculator modes and "Convert". Not measured —
    // the reference's separator sits on a black sheet rather than on this panel
    // — so it borrows the menu's own border, which is the same kind of edge.
    readonly property color menuSeparator: menuBorder

    // --- unit picker --------------------------------------------------
    // The sheet's three bands. The reference runs a header at (43,42,45), a list
    // at (34,34,34) and a footer back up at (43,42,45) — so the list is the
    // recessed one and the bands above and below it are the sheet's own tone.
    // Our sheet is glass rather than a flat fill, so the two bands are carried
    // as washes over it: the deltas are the reference's, applied to whatever the
    // blur underneath happens to be.
    readonly property color pickerListShade: Qt.rgba(0, 0, 0, 0.18)
    readonly property color pickerFooterShade: Qt.rgba(1, 1, 1, 0.035)
    // The hairline under the chip row and between the list's rows: measured at
    // 59 on the list's own 34, i.e. a 16% white wash, the same weight as the
    // convert view's rule.
    readonly property color pickerRule: dark ? Qt.rgba(1, 1, 1, 0.16)
                                             : Qt.rgba(0, 0, 0, 0.10)
    readonly property color pickerText: dark ? "#FFFFFF" : "#000000"
    // The unit code under each name, and the footer's source and date. Measured
    // off the reference's own glyph cores and corrected for how much a thin
    // stroke under-reads — the same 57% white the convert view's unit codes use.
    readonly property color pickerCode: convertUnit
    // The selected row's name and code, the tick beside it, the chip pill and
    // the unselected chip labels are all the one accent — the reference spends
    // it here exactly as it does on the operator column.
    readonly property color pickerAccent: keyOperator
    readonly property color pickerChipText: "#FFFFFF"
    // The search field: (69,68,71) over the footer's (43,42,45), i.e. a 26%
    // white lift, carried as a wash for the same reason.
    readonly property color pickerField: dark ? Qt.rgba(1, 1, 1, 0.10)
                                              : Qt.rgba(0, 0, 0, 0.06)
    readonly property color pickerFieldText: dark ? Qt.rgba(1, 1, 1, 0.55)
                                                  : Qt.rgba(0, 0, 0, 0.45)

    // --- title-strip buttons ------------------------------------------
    // The round history and mode buttons. The reference paints them as a flat
    // white wash — #1F1F1F over pure black — so what is copied here is the
    // wash, not the colour: our window sits on glass at #484846 rather than on
    // black, and an absolute value lifted from the phone reads as a lighter
    // disc here than it does there. That wash is the resting state only; the
    // hover is the shared SelectionHighlight plate, as on the menu rows.
    readonly property color chromeButton: dark ? Qt.rgba(1, 1, 1, 0.12)
                                               : Qt.rgba(0, 0, 0, 0.07)
    readonly property color chromeButtonIcon: dark ? "#FFFFFF" : "#000000"
    // An open button goes solid accent with the glyph knocked out, which is
    // extrapolated: the reference only ever shows the closed state.
    readonly property color chromeButtonActive: keyOperator
}
