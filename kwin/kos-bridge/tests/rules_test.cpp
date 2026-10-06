// Tests for the parts of the effect that decide where a panel goes: the
// geometry the adjust gesture works in, the tiling menu that hangs from it, the
// rule list, and the four-step resolution that picks between them.
//
// These three are deliberately free of KWin headers -- panelgeometry.h,
// tilemenu.h and windowrules.h use their own value types and a window type as an
// int -- so they can be exercised here without a compositor. Everything that
// needs a compositor (the painting, the tint, the pointer) is manual
// verification.
//
// Built with -DKOS_BRIDGE_BUILD_TESTS=ON, and run through ctest.

#include <QCoreApplication>
#include <QDateTime>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>

#include <cmath>
#include <cstdio>

#include "windowbuttons/buttonconfig.h"
#include "windowbuttons/panelgeometry.h"
#include "windowbuttons/tilemenu.h"
#include "windowbuttons/windowrules.h"

using namespace KOS;

namespace
{

int g_checks = 0;
int g_failures = 0;
QTemporaryDir *g_dir = nullptr;

void check(bool condition, const char *expression, int line)
{
    ++g_checks;
    if (condition) {
        return;
    }
    ++g_failures;
    std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, line, expression);
}

// The values here come out of JSON and out of pointer motion, so they are
// compared with a tolerance rather than exactly.
bool near(qreal a, qreal b)
{
    return std::abs(a - b) <= 0.01;
}

#define CHECK(condition) check((condition), #condition, __LINE__)

QString dataHome()
{
    return g_dir->path() + QStringLiteral("/data");
}

QString configHome()
{
    return g_dir->path() + QStringLiteral("/config");
}

QString rulesPath()
{
    return dataHome() + QStringLiteral("/kos/window-buttons-rules.json");
}

void writeFile(const QString &path, const QByteArray &bytes)
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        std::fprintf(stderr, "FAIL cannot write %s\n", qPrintable(path));
        ++g_failures;
        return;
    }
    file.write(bytes);
}

QByteArray readFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return {};
    }
    return file.readAll();
}

void writeUserConfig(const QByteArray &json)
{
    writeFile(configHome() + QStringLiteral("/kos/window-buttons.json"), json);
}

void writeKwinrc(const QByteArray &decoration)
{
    writeFile(configHome() + QStringLiteral("/kwinrc"),
              "[org.kde.kdecoration2]\nlibrary=" + decoration + "\n");
}

void removeRulesFile()
{
    QFile::remove(rulesPath());
}

WindowQuery query(const QString &windowClass, const QString &caption = {},
                  int type = 0, const QString &role = {})
{
    WindowQuery q;
    q.windowClass = windowClass;
    q.caption = caption;
    q.type = type;
    q.role = role;
    return q;
}

WindowMatcher classMatcher(const QString &windowClass)
{
    WindowMatcher matcher;
    matcher.className = windowClass;
    return matcher;
}

QRectF unclipped(const PanelGeometry &geometry, qreal width = 1200, qreal height = 700)
{
    return panelRectUnclipped(geometry, QSizeF(width, height));
}

// ---------------------------------------------------------------------------
// What a rule matches
// ---------------------------------------------------------------------------

void testMatchers()
{
    // A rule that names nothing would match every window, which no rule ever
    // means. It is a mistake, and it is dropped rather than widened.
    const WindowMatcher empty;
    CHECK(empty.isEmpty());
    CHECK(!empty.matches(query(QStringLiteral("firefox"))));

    // A class is matched whole, or as any one of its whitespace-separated
    // tokens: WM_CLASS arrives as "instance class" and a key of "code" has
    // always matched "code code".
    const WindowMatcher code = classMatcher(QStringLiteral("code"));
    CHECK(code.matches(query(QStringLiteral("code"))));
    CHECK(code.matches(query(QStringLiteral("code code"))));
    CHECK(!code.matches(query(QStringLiteral("vscodium"))));
    CHECK(!code.matches(query(QStringLiteral(""))));
    CHECK(code.specificity() == 1);

    WindowMatcher titled = code;
    titled.title = QStringLiteral("Untitled — 1");
    CHECK(titled.matches(query(QStringLiteral("code"), QStringLiteral("Untitled — 1"))));
    CHECK(!titled.matches(query(QStringLiteral("code"), QStringLiteral("other"))));
    CHECK(titled.specificity() == 2);

    // The regex is a key of its own, so a title that contains a bracket cannot
    // silently turn into a broken pattern.
    WindowMatcher regex;
    regex.titleRegex = QStringLiteral("^Picture-in-Picture");
    CHECK(regex.matches(query(QStringLiteral("firefox"),
                              QStringLiteral("Picture-in-Picture — video"))));
    CHECK(!regex.matches(query(QStringLiteral("firefox"), QStringLiteral("Mozilla"))));

    // The role is empty on every Wayland window, so a rule that sets one simply
    // never matches there.
    WindowMatcher roled;
    roled.role = QStringLiteral("mainwindow");
    CHECK(!roled.matches(query(QStringLiteral("code"))));
    CHECK(roled.matches(query(QStringLiteral("code"), {}, 0,
                              QStringLiteral("mainwindow"))));

    // The type is compared only when the rule names one.
    WindowMatcher typed;
    typed.hasType = true;
    typed.type = 5; // dialog
    CHECK(typed.matches(query(QStringLiteral("dolphin"), {}, 5)));
    CHECK(!typed.matches(query(QStringLiteral("dolphin"), {}, 0)));

    // Specificity is how many things a rule says about a window, and it is what
    // orders two rules that both match.
    CHECK(!moreSpecific(code, titled));
    CHECK(moreSpecific(titled, code));

    // Parsing.
    bool ok = false;
    WindowMatcher parsed = WindowMatcher::fromJson(
        QJsonObject{{"class", "firefox"}, {"type", "dialog"}}, &ok);
    CHECK(ok);
    CHECK(parsed.matches(query(QStringLiteral("firefox"), {}, 5)));
    CHECK(!parsed.matches(query(QStringLiteral("firefox"), {}, 0)));

    WindowMatcher::fromJson(QJsonObject{{"type", "not-a-type"}}, &ok);
    CHECK(!ok);
    WindowMatcher::fromJson(QJsonObject{{"titleRegex", "([unclosed"}}, &ok);
    CHECK(!ok);
    WindowMatcher::fromJson(QJsonObject{{"class", "firefox"}}, &ok);
    CHECK(ok);

    // The key is what makes two rules the same rule.
    CHECK(classMatcher(QStringLiteral("a")).canonicalKey()
          != classMatcher(QStringLiteral("b")).canonicalKey());
    CHECK(classMatcher(QStringLiteral("a")).canonicalKey()
          != titled.canonicalKey());
}

// ---------------------------------------------------------------------------
// Where the panel is
// ---------------------------------------------------------------------------

void testGeometry()
{
    PanelGeometry geometry;
    geometry.offset.x = 10;
    geometry.offset.y = 6;

    const QSizeF window(1200, 700);
    const QRectF rect = unclipped(geometry);
    CHECK(near(rect.width(), 3 * 14 + 2 * 14 + 2 * 4.5));
    CHECK(near(rect.height(), 14 + 2 * 4.5));
    // Pinned to the right edge by `offset.x`, measured from that edge.
    CHECK(near(rect.right(), window.width() - 10));

    // The gesture derives the geometry from a top-left corner, and the two have
    // to agree: this is what makes a drag and a nudge the same operation.
    const PanelGeometry round =
        panelGeometryFromTopLeft(geometry, window, panelOrigin(geometry, window));
    CHECK(round.position == ButtonPosition::Right);
    CHECK(near(round.offset.x, geometry.offset.x));
    CHECK(near(round.offset.y, geometry.offset.y));
    CHECK(sameGeometry(round, geometry));

    // Across the middle of the window the side flips, and it flips without a
    // jump: both branches meet at x = (windowWidth - panelWidth) / 2, so the
    // panel moves continuously through the middle even though the field that
    // describes it does not.
    const qreal middle = (window.width() - rect.width()) / 2.0;
    const PanelGeometry justLeft = panelGeometryFromTopLeft(
        geometry, window, QPointF(middle - 0.5, 6));
    const PanelGeometry justRight = panelGeometryFromTopLeft(
        geometry, window, QPointF(middle + 0.5, 6));
    CHECK(justLeft.position == ButtonPosition::Left);
    CHECK(justRight.position == ButtonPosition::Right);
    CHECK(near(unclipped(justLeft).x(), middle - 0.5));
    CHECK(near(unclipped(justRight).x(), middle + 0.5));
    // The two branches meet at the middle: the offset that describes the panel
    // is the same on both sides of the flip, so nothing jumps.
    CHECK(near(justLeft.offset.x, justRight.offset.x));

    // Off the window, the panel stops at the edge rather than leaving it.
    const PanelGeometry far = panelGeometryFromTopLeft(geometry, window,
                                                       QPointF(5000, 5000));
    CHECK(near(unclipped(far).right(), window.width()));
    CHECK(near(unclipped(far).bottom(), window.height()));
    const PanelGeometry negative = panelGeometryFromTopLeft(geometry, window,
                                                            QPointF(-50, -50));
    CHECK(near(unclipped(negative).x(), 0));
    CHECK(near(unclipped(negative).y(), 0));

    // A nudge is a drag by a delta, through the same path.
    const PanelGeometry nudgedGeometry = nudged(geometry, window, QPointF(-20, 4));
    CHECK(near(unclipped(nudgedGeometry).x(), rect.x() - 20));
    CHECK(near(unclipped(nudgedGeometry).y(), rect.y() + 4));

    // Resizing leaves `offset` alone, so the panel grows away from the edge it
    // is pinned to rather than away from its own middle.
    const PanelGeometry bigger =
        resized(geometry, GeometryField::DotSize, 4);
    CHECK(near(bigger.buttonSize, 18));
    CHECK(near(bigger.offset.x, geometry.offset.x));
    CHECK(near(bigger.offset.y, geometry.offset.y));
    CHECK(near(unclipped(bigger).right(), window.width() - 10));

    // And it clamps.
    CHECK(near(resized(geometry, GeometryField::DotSize, 1000).buttonSize,
               MaxButtonSize));
    CHECK(near(resized(geometry, GeometryField::DotSize, -1000).buttonSize,
               MinButtonSize));
    CHECK(near(resized(geometry, GeometryField::Spacing, -1000).buttonSpacing,
               0.0));
    CHECK(near(resized(geometry, GeometryField::Padding, 1000).panelPadding,
               MaxPanelPadding));

    // The horizontal padding's sentinel means "the same as the vertical one",
    // and follows it.
    PanelGeometry paddingGeometry = geometry;
    paddingGeometry.panelPaddingX = -1;
    CHECK(near(effectivePanelPaddingX(paddingGeometry), paddingGeometry.panelPadding));
    paddingGeometry.panelPadding = 8;
    CHECK(near(effectivePanelPaddingX(paddingGeometry), 8));
    // Set explicitly, it is a decision of its own and does not follow.
    paddingGeometry.panelPaddingX = 2;
    paddingGeometry.panelPadding = 12;
    CHECK(near(effectivePanelPaddingX(paddingGeometry), 2));

    // What "the same" means: the sentinel is resolved first, so -1 and an
    // explicit value equal to panelPadding are the same panel.
    PanelGeometry sentinel = geometry;
    sentinel.panelPaddingX = -1;
    PanelGeometry explicitPadding = sentinel;
    explicitPadding.panelPaddingX = explicitPadding.panelPadding;
    CHECK(sameGeometry(sentinel, explicitPadding));
    CHECK(!sameGeometry(sentinel, resized(sentinel, GeometryField::DotSize, 1)));

    // Values that came from a text file go through the same clamp the gesture
    // does, sentinel and all.
    PanelGeometry absurd;
    absurd.buttonSize = 1e6;
    absurd.panelPaddingX = -1;
    absurd.offset.x = -20;
    const PanelGeometry bounded = clamped(absurd);
    CHECK(near(bounded.buttonSize, MaxButtonSize));
    CHECK(near(bounded.offset.x, 0));
    CHECK(near(bounded.panelPaddingX, -1));

    // The three lights sit inside the panel, in the middle of its height.
    const QSizeF panelSize(rect.width(), rect.height());
    const QRectF close = dotRect(panelSize, geometry, 0);
    const QRectF maximize = dotRect(panelSize, geometry, 2);
    CHECK(close.left() >= 0 && maximize.right() <= panelSize.width());
    CHECK(near(close.center().y(), panelSize.height() / 2.0));
    CHECK(close.left() < close.right());
    CHECK(close.right() <= maximize.left());
}

// ---------------------------------------------------------------------------
// Dragging an edge
// ---------------------------------------------------------------------------

// The panel's rect in window coordinates, so a test can state the promise the
// edge grips make directly: the edge that was dragged follows the pointer, the
// opposite edge does not move at all.
QRectF windowRect(const PanelGeometry &geometry)
{
    return unclipped(geometry);
}

// The rect the grips are expressed in: the panel's own, with its top-left at the
// origin, which is where the renderer paints them.
QRectF panelBox(const PanelGeometry &geometry)
{
    return QRectF(QPointF(0, 0), windowRect(geometry).size());
}

void testEdgeResize()
{
    const QSizeF window(1200, 700);

    PanelGeometry geometry;  // right-pinned, 100 px in from the right
    geometry.offset.x = 100;
    geometry.offset.y = 6;

    const QRectF before = windowRect(geometry);

    // Width is the horizontal padding -- how much of the panel is not lights --
    // and it sits at both ends of the panel, so the edge moves by twice what the
    // padding does.
    const PanelGeometry rightEdge =
        resizedByEdge(geometry, PanelEdge::Right, QPointF(40, 0));
    CHECK(near(windowRect(rightEdge).right(), before.right() + 40));
    CHECK(near(windowRect(rightEdge).left(), before.left()));
    CHECK(near(rightEdge.buttonSize, geometry.buttonSize));
    CHECK(near(rightEdge.buttonSpacing, geometry.buttonSpacing));
    CHECK(near(rightEdge.panelPadding, geometry.panelPadding));

    // The other edge of the same panel is the width too, and dragging it leaves
    // the edge the panel is pinned by where it is.
    const PanelGeometry leftEdge =
        resizedByEdge(geometry, PanelEdge::Left, QPointF(-40, 0));
    CHECK(near(windowRect(leftEdge).left(), before.left() - 40));
    CHECK(near(windowRect(leftEdge).right(), before.right()));
    CHECK(near(leftEdge.offset.x, geometry.offset.x));

    // A left-pinned panel is the mirror image: the left edge is what the offset
    // holds, the right edge is the width.
    PanelGeometry leftPinned = geometry;
    leftPinned.position = ButtonPosition::Left;
    const QRectF leftBefore = windowRect(leftPinned);
    CHECK(near(leftBefore.left(), 100));

    const PanelGeometry pinnedLeft =
        resizedByEdge(leftPinned, PanelEdge::Left, QPointF(-30, 0));
    CHECK(near(windowRect(pinnedLeft).left(), leftBefore.left() - 30));
    CHECK(near(windowRect(pinnedLeft).right(), leftBefore.right()));
    const PanelGeometry pinnedRight =
        resizedByEdge(leftPinned, PanelEdge::Right, QPointF(30, 0));
    CHECK(near(windowRect(pinnedRight).right(), leftBefore.right() + 30));
    CHECK(near(windowRect(pinnedRight).left(), leftBefore.left()));

    // Height is the vertical padding. The bottom edge is the free one...
    const PanelGeometry taller =
        resizedByEdge(geometry, PanelEdge::Bottom, QPointF(0, 20));
    CHECK(near(taller.panelPadding, geometry.panelPadding + 10));
    CHECK(near(windowRect(taller).bottom(), before.bottom() + 20));
    CHECK(near(windowRect(taller).top(), before.top()));
    // ...and the top edge is what `offset.y` holds, so dragging it down moves the
    // panel's top down instead of growing it upwards off the window.
    const PanelGeometry shorter =
        resizedByEdge(geometry, PanelEdge::Top, QPointF(0, 6));
    CHECK(near(windowRect(shorter).top(), before.top() + 6));
    CHECK(near(windowRect(shorter).bottom(), before.bottom()));

    // A width that was still following the vertical padding is pinned to what it
    // resolves to before the height moves: dragging an edge of the panel is not a
    // reason for the other dimension to change as well.
    PanelGeometry sentinel = geometry;
    sentinel.panelPaddingX = -1;
    const PanelGeometry sentinelTaller =
        resizedByEdge(sentinel, PanelEdge::Bottom, QPointF(0, 20));
    CHECK(near(sentinelTaller.panelPaddingX, sentinel.panelPadding));
    CHECK(near(windowRect(sentinelTaller).width(), windowRect(sentinel).width()));
    // The same on the width grip, where the sentinel is what is left behind.
    const PanelGeometry sentinelWider =
        resizedByEdge(sentinel, PanelEdge::Right, QPointF(20, 0));
    CHECK(!near(sentinelWider.panelPaddingX, -1));
    CHECK(near(windowRect(sentinelWider).height(), windowRect(sentinel).height()));

    // The width has an absolute bound, and the edge that ran into it stops there.
    const PanelGeometry wide =
        resizedByEdge(geometry, PanelEdge::Left, QPointF(-1000, 0));
    CHECK(near(wide.panelPaddingX, MaxPanelPaddingX));
    CHECK(near(windowRect(wide).width(),
               3 * 14 + 2 * 14 + 2 * MaxPanelPaddingX));
    // Narrower than the lights plus the gaps is not a panel: the edge stops there
    // and the offset takes up the slack the width refused, which is what makes
    // the panel shrink away from the window's edge rather than off it.
    const PanelGeometry narrow =
        resizedByEdge(geometry, PanelEdge::Right, QPointF(-1000, 0));
    CHECK(near(narrow.panelPaddingX, 0.0));
    CHECK(near(windowRect(narrow).width(), 3 * 14 + 2 * 14));
    CHECK(near(windowRect(narrow).right(), before.right() - 9));
    CHECK(near(windowRect(narrow).left(), before.left()));

    // An edge that is pinned stops at the edge of the window, and the panel stops
    // with it: the offset is the whole of the room between the two, and a drag
    // that goes on past the window must not push the panel's *other* edge out
    // instead, which is what letting the width go on growing would do.
    PanelGeometry nearEdge = geometry;
    nearEdge.offset.x = 4;
    nearEdge.offset.y = 4;
    const QRectF nearRect = windowRect(nearEdge);
    const PanelGeometry pushed =
        resizedByEdge(nearEdge, PanelEdge::Right, QPointF(200, 0));
    CHECK(near(pushed.offset.x, 0));
    CHECK(near(windowRect(pushed).right(), window.width()));
    CHECK(near(windowRect(pushed).width(), nearRect.width() + 4));
    CHECK(near(windowRect(pushed).left(), nearRect.left()));

    const PanelGeometry pulledUp =
        resizedByEdge(nearEdge, PanelEdge::Top, QPointF(0, -200));
    CHECK(near(pulledUp.offset.y, 0));
    CHECK(near(windowRect(pulledUp).top(), 0));
    CHECK(near(windowRect(pulledUp).height(), nearRect.height() + 4));
    CHECK(near(windowRect(pulledUp).bottom(), nearRect.bottom()));

    // All of it goes through the same clamp a text file's values do, so a drag
    // cannot produce a geometry the store would refuse to read back.
    for (const PanelEdge edge : {PanelEdge::Left, PanelEdge::Right,
                                 PanelEdge::Top, PanelEdge::Bottom}) {
        for (const QPointF delta : {QPointF(-900, -900), QPointF(900, 900),
                                    QPointF(0, 0)}) {
            const PanelGeometry dragged = resizedByEdge(geometry, edge, delta);
            CHECK(sameGeometry(clamped(dragged), dragged));
        }
    }

    // The grips: one per edge, inside the panel, and hit-testing finds the edge a
    // point is on.
    for (const PanelEdge edge : {PanelEdge::Left, PanelEdge::Right,
                                 PanelEdge::Top, PanelEdge::Bottom}) {
        const QRectF grip = gripRect(geometry, edge);
        CHECK(!grip.isEmpty());
        CHECK(gripHitRect(geometry, edge).contains(grip.center()));
        CHECK(panelBox(geometry).contains(grip));
        CHECK(gripAt(geometry, grip.center()) == edge);
    }
    // The middle of the panel is not an edge: a press there moves the panel.
    CHECK(!gripAt(geometry, panelBox(geometry).center()).has_value());
    // And neither is a point well outside it.
    CHECK(!gripAt(geometry, QPointF(-40, -40)).has_value());

    // The grips follow the panel: a wider panel has its side grips further out,
    // and the lights themselves are untouched by any of it.
    const PanelGeometry wider = resizedByEdge(geometry, PanelEdge::Right, QPointF(40, 0));
    CHECK(near(gripRect(wider, PanelEdge::Right).right(),
               gripRect(geometry, PanelEdge::Right).right() + 40));
    CHECK(near(dotRect(panelBox(wider).size(), wider, 0).size().width(), 14));
    CHECK(near(dotRect(panelBox(wider).size(), wider, 1).x()
                   - dotRect(panelBox(wider).size(), wider, 0).x(),
               wider.buttonSize + wider.buttonSpacing));
    CHECK(gripAt(wider, gripRect(wider, PanelEdge::Right).center())
          == PanelEdge::Right);
    // Where the old grip was is no longer an edge of the new panel.
    CHECK(!gripAt(wider, gripRect(geometry, PanelEdge::Right).center()).has_value());
}

// ---------------------------------------------------------------------------
// The tiling menu
// ---------------------------------------------------------------------------

bool isRect(const QRectF &rect, qreal x, qreal y, qreal width, qreal height)
{
    return near(rect.x(), x) && near(rect.y(), y) && near(rect.width(), width)
        && near(rect.height(), height);
}

void testTileMenu()
{
    // The table the whole menu follows: which preset each cell holds, in
    // reading order. Reordering the menu is reordering this table, so this is
    // the assertion that says where every cell is.
    const TilePreset order[TilePresetCount] = {
        TilePreset::Fill,           TilePreset::LeftHalf,
        TilePreset::RightHalf,      TilePreset::Restore,
        TilePreset::LeftThird,      TilePreset::LeftTwoThirds,
        TilePreset::RightTwoThirds, TilePreset::RightThird,
    };
    CHECK(TilePresetCount == TileMenuColumns * TileMenuRows);
    for (int i = 0; i < TilePresetCount; ++i) {
        CHECK(tilePresetAt(i) == order[i]);
        // Each preset is in the menu exactly once, so no cell is drawn twice and
        // none of the eight is unreachable.
        int seen = 0;
        for (int j = 0; j < TilePresetCount; ++j) {
            seen += order[j] == order[i] ? 1 : 0;
        }
        CHECK(seen == 1);
    }
    // A cell number that came out of a hit test is answered with a preset rather
    // than run off the end of the table.
    CHECK(tilePresetAt(-1) == TilePreset::Fill);
    CHECK(tilePresetAt(TilePresetCount) == TilePreset::Fill);
    CHECK(tilePresetAt(1000) == TilePreset::Fill);

    // The box: the cells, the padding around them, and the gaps between them.
    const QSizeF menuSize = tileMenuSize();
    CHECK(near(menuSize.width(),
               TileMenuPadding * 2 + TileMenuColumns * TileMenuCell
                   + (TileMenuColumns - 1) * TileMenuGap));
    CHECK(near(menuSize.height(),
               TileMenuPadding * 2 + TileMenuRows * TileMenuCell
                   + (TileMenuRows - 1) * TileMenuGap));
    CHECK(menuSize.width() > 0 && menuSize.height() > 0);

    // What each preset does to the window, on a work area a third of which is a
    // whole number of pixels.
    const QRectF area(0, 0, 1200, 800);
    CHECK(isRect(tilePresetRect(TilePreset::LeftThird, area), 0, 0, 400, 800));
    CHECK(isRect(tilePresetRect(TilePreset::LeftTwoThirds, area), 0, 0, 800, 800));
    CHECK(isRect(tilePresetRect(TilePreset::RightTwoThirds, area), 400, 0, 800, 800));
    CHECK(isRect(tilePresetRect(TilePreset::RightThird, area), 800, 0, 400, 800));

    // The placements are expressed against the work area's own edges, not the
    // screen's: a window on a work area that does not start at the origin is
    // placed against where that work area actually is.
    const QRectF offArea(100, 50, 1200, 800);
    CHECK(isRect(tilePresetRect(TilePreset::LeftThird, offArea), 100, 50, 400, 800));
    CHECK(isRect(tilePresetRect(TilePreset::RightThird, offArea), 900, 50, 400, 800));
    CHECK(isRect(tilePresetRect(TilePreset::RightTwoThirds, offArea), 500, 50, 800, 800));

    // The presets that are not placements come back empty. An empty rectangle is
    // what keeps them from being placed: the caller reaches for a rectangle only
    // where the answer is one.
    for (const TilePreset preset : {TilePreset::Fill, TilePreset::LeftHalf,
                                    TilePreset::RightHalf, TilePreset::Restore,
                                    TilePreset::Count}) {
        CHECK(tilePresetRect(preset, area).isEmpty());
        CHECK(tilePresetRect(preset, offArea).isEmpty());
    }

    // The invariant the rounding is for: a third and the complement of a third
    // tile the work area exactly, for widths that divide evenly and for widths
    // that do not.
    for (const qreal width : {1000.0, 1001.0, 1002.0, 7.0, 1.0}) {
        const QRectF work(0, 0, width, 800);
        const QRectF leftThird = tilePresetRect(TilePreset::LeftThird, work);
        const QRectF leftTwoThirds = tilePresetRect(TilePreset::LeftTwoThirds, work);
        const QRectF rightTwoThirds = tilePresetRect(TilePreset::RightTwoThirds, work);
        const QRectF rightThird = tilePresetRect(TilePreset::RightThird, work);

        // They meet: the first one's right edge is the second one's left edge...
        CHECK(near(leftThird.right(), rightTwoThirds.left()));
        CHECK(near(leftTwoThirds.right(), rightThird.left()));
        // ...and they do not overlap, which with the edge above means no seam
        // and no double-covered pixel either.
        CHECK(!leftThird.intersects(rightTwoThirds));
        CHECK(!leftTwoThirds.intersects(rightThird));
        // Together they are the whole width, and each is inside the work area.
        CHECK(near(leftThird.width() + rightTwoThirds.width(), width));
        CHECK(near(leftTwoThirds.width() + rightThird.width(), width));
        CHECK(near(leftThird.left(), work.left()));
        CHECK(near(rightTwoThirds.right(), work.right()));
        CHECK(near(leftTwoThirds.left(), work.left()));
        CHECK(near(rightThird.right(), work.right()));
        for (const QRectF &rect : {leftThird, leftTwoThirds, rightTwoThirds, rightThird}) {
            // A width too small to hold three pixels gives a third that rounds
            // to none, and a rect with no width is not "inside" anything as far
            // as Qt is concerned -- it is a line on the work area's edge, which
            // is as placed as it can be. Everything a real window produces is
            // checked properly.
            CHECK(rect.isEmpty() || work.contains(rect));
        }
    }

    // A window with room for the menu under its panel.
    const QRectF window(100, 40, 1200, 700);
    const QRectF panel(1100, 46, 180, 28);
    const QPointF anchor(1108, 60);  // the centre of the light that opens it
    const std::optional<QRectF> menu = tileMenuRect(panel, window, anchor);
    CHECK(menu.has_value());
    if (!menu) {
        return;
    }

    // It hangs from the panel's bottom edge with nothing in between: the pointer
    // walking down from the light never crosses a gap, which is what lets the
    // menu take over the pointer from the panel without the menu closing first.
    CHECK(near(menu->top(), panel.bottom()));
    CHECK(near(menu->width(), menuSize.width()));
    CHECK(near(menu->height(), menuSize.height()));
    // And it is inside the window, inset from its edges like the panel is.
    CHECK(menu->left() >= window.left() + TileMenuInset);
    CHECK(menu->right() <= window.right() - TileMenuInset);
    CHECK(menu->bottom() <= window.bottom() - TileMenuInset);

    // Centred on the light, and inside the window: an anchor near either edge
    // leaves the menu as close to that edge as the inset allows and the anchor
    // still under it.
    const QRectF leftMenu = tileMenuRect(panel, window, QPointF(120, 60)).value();
    CHECK(near(leftMenu.left(), window.left() + TileMenuInset));
    const QRectF rightMenu = tileMenuRect(panel, window, QPointF(1290, 60)).value();
    CHECK(near(rightMenu.right(), window.right() - TileMenuInset));
    for (const qreal x : {106.0, 120.0, 700.0, 1280.0, 1294.0}) {
        const QRectF placed = tileMenuRect(panel, window, QPointF(x, 60)).value();
        CHECK(placed.left() <= x + 0.01 && placed.right() >= x - 0.01);
    }

    // No room is no menu rather than a clipped one. The window is too short for
    // the menu to fit under the panel...
    CHECK(!tileMenuRect(panel, QRectF(100, 40, 1200, 100), anchor).has_value());
    // ...and one pixel short of the room it needs, where the room needed is the
    // panel's bottom edge, the menu, and the inset it keeps from the window's
    // own bottom edge.
    const qreal needed = panel.bottom() + menuSize.height() + TileMenuInset;
    const QRectF justShort(100, 0, 1200, needed - 1);
    CHECK(!tileMenuRect(panel, justShort, anchor).has_value());
    const QRectF exact(100, 0, 1200, needed);
    const std::optional<QRectF> sitting = tileMenuRect(panel, exact, anchor);
    CHECK(sitting.has_value());
    if (sitting) {
        CHECK(near(sitting->bottom(), exact.bottom() - TileMenuInset));
    }
    // And a window too narrow to hold the menu has none either, however much
    // room there is under the panel: with the 6 px inset at each side, the menu
    // needs 151 px of window and a 150 px one cannot give them.
    CHECK(!tileMenuRect(panel, QRectF(100, 40, 150, 700), anchor).has_value());
    const QRectF narrow(100, 40, 151, 700);
    const std::optional<QRectF> narrowMenu = tileMenuRect(panel, narrow, anchor);
    CHECK(narrowMenu.has_value());
    if (narrowMenu) {
        CHECK(near(narrowMenu->width(), narrow.width() - 2 * TileMenuInset));
        CHECK(near(narrowMenu->left(), narrow.left() + TileMenuInset));
    }

    // The cells: eight of them, square, inside the box, in reading order, and
    // each one belonging to the preset the table says.
    const TileMenuCells cells = tileMenuCells(*menu);
    for (int i = 0; i < TilePresetCount; ++i) {
        CHECK(near(cells[i].width(), TileMenuCell));
        CHECK(near(cells[i].height(), TileMenuCell));
        CHECK(menu->contains(cells[i]));
        CHECK(tileMenuPresetAt(*menu, cells[i].center()) == order[i]);
        // Inside its own cell is that cell: the whole cell is the target, not
        // just its middle.
        CHECK(tileMenuPresetAt(*menu, cells[i].topLeft() + QPointF(0.5, 0.5))
              == order[i]);
        for (int j = i + 1; j < TilePresetCount; ++j) {
            CHECK(!cells[i].intersects(cells[j]));
        }
        // Reading order: cell i is on the row i / columns and the column i %
        // columns, so a later cell is never above or to the left of an earlier
        // one.
        CHECK(near(cells[i].top(),
                   menu->top() + TileMenuPadding
                       + (i / TileMenuColumns) * (TileMenuCell + TileMenuGap)));
        CHECK(near(cells[i].left(),
                   menu->left() + TileMenuPadding
                       + (i % TileMenuColumns) * (TileMenuCell + TileMenuGap)));
    }
    // The box is exactly the cells plus their padding and the gaps.
    CHECK(near(cells[0].left() - menu->left(), TileMenuPadding));
    CHECK(near(cells[0].top() - menu->top(), TileMenuPadding));
    CHECK(near(menu->right() - cells[TilePresetCount - 1].right(), TileMenuPadding));
    CHECK(near(menu->bottom() - cells[TilePresetCount - 1].bottom(), TileMenuPadding));

    // The padding and the gaps are part of the menu but not of any cell, and
    // nothing outside the box is in it at all.
    CHECK(!tileMenuPresetAt(*menu, QPointF(menu->left() + 1, menu->top() + 1))
               .has_value());
    CHECK(!tileMenuPresetAt(*menu, QPointF(cells[0].right() + TileMenuGap / 2.0,
                                           cells[0].center().y()))
               .has_value());
    CHECK(!tileMenuPresetAt(*menu, QPointF(cells[0].center().x(),
                                           cells[0].bottom() + TileMenuGap / 2.0))
               .has_value());
    CHECK(!tileMenuPresetAt(*menu, QPointF(menu->left() - 1, menu->top() - 1))
               .has_value());
    CHECK(!tileMenuPresetAt(*menu, QPointF(menu->right() + 1, menu->top() + 1))
               .has_value());
    CHECK(!tileMenuPresetAt(*menu, QPointF(menu->left() + 1, menu->bottom() + 1))
               .has_value());
    // A menu with no box is no menu, and no cell of it is anywhere.
    CHECK(!tileMenuPresetAt(QRectF(), QPointF(0, 0)).has_value());
}

// ---------------------------------------------------------------------------
// Which configuration a window gets
// ---------------------------------------------------------------------------

void testResolution()
{
    removeRulesFile();
    writeKwinrc("kos_decoration");
    writeUserConfig(R"({
        "default": {
            "offset": { "x": 10, "y": 6 },
            "buttonSize": 14,
            "interceptMargin": 7,
            "background": "auto"
        },
        "apps": {
            "firefox": { "background": "dark" },
            "code": { "panelPadding": 6 }
        },
        "rules": [
            { "match": { "titleRegex": "^Picture-in-Picture" },
              "position": "left", "offset": { "x": 4, "y": 4 } },
            { "match": { "class": "org.kde.dolphin", "type": "dialog" },
              "showButtons": false }
        ]
    })");

    ButtonConfig config;

    // 1. The default.
    const AppConfig plain = config.getAppConfig(query(QStringLiteral("konsole")));
    CHECK(near(plain.geometry.offset.x, 10));
    CHECK(near(plain.geometry.buttonSize, 14));
    CHECK(near(plain.interceptMargin, 7));
    CHECK(plain.background == PanelBackground::Auto);
    CHECK(plain.showButtons);

    // 2. The app entry, merged key by key over the default. The class arrives
    // as "instance class" and the key may name either of them.
    const AppConfig firefox =
        config.getAppConfig(query(QStringLiteral("Navigator firefox")));
    CHECK(firefox.background == PanelBackground::Dark);
    CHECK(near(firefox.geometry.offset.x, 10));
    const AppConfig code = config.getAppConfig(query(QStringLiteral("code code")));
    CHECK(near(code.geometry.panelPadding, 6));
    CHECK(near(code.geometry.buttonSize, 14));
    CHECK(code.background == PanelBackground::Auto);

    // 3. The hand-written rules, by the first that matches.
    const AppConfig dialog =
        config.getAppConfig(query(QStringLiteral("org.kde.dolphin"), {}, 5));
    CHECK(!dialog.showButtons);
    const AppConfig normalDolphin =
        config.getAppConfig(query(QStringLiteral("org.kde.dolphin")));
    CHECK(normalDolphin.showButtons);
    const AppConfig pip = config.getAppConfig(
        query(QStringLiteral("firefox"), QStringLiteral("Picture-in-Picture")));
    CHECK(pip.geometry.position == ButtonPosition::Left);
    CHECK(pip.background == PanelBackground::Dark);
    const AppConfig plainFirefox = config.getAppConfig(
        query(QStringLiteral("firefox"), QStringLiteral("Mozilla Firefox")));
    CHECK(plainFirefox.geometry.position == ButtonPosition::Right);

    // A machine rule replaces the geometry whole and touches nothing else: what
    // was dragged is what is drawn, and whether the panel is drawn at all is
    // still the user's answer.
    WindowMatcher firefoxMatcher = classMatcher(QStringLiteral("firefox"));
    PanelGeometry dragged;
    dragged.position = ButtonPosition::Left;
    dragged.offset = AppOffset{12, 8};
    dragged.buttonSize = 17;
    CHECK(config.storeGeometry(firefoxMatcher, dragged));

    const AppConfig adjusted = config.getAppConfig(query(QStringLiteral("firefox")));
    CHECK(sameGeometry(adjusted.geometry, dragged));
    // `interceptMargin` and `background` survive the geometry being replaced.
    CHECK(near(adjusted.interceptMargin, 7));
    CHECK(adjusted.background == PanelBackground::Dark);
    CHECK(adjusted.showButtons);
    // The user's own offset lost, and lost for good: it is the panel that is
    // drawn that the drag positioned.
    CHECK(!near(adjusted.geometry.offset.x, 10));

    // A hand-written `showButtons: false` still wins over the drag, because it
    // is not a geometry key: the machine rule replaces the geometry and nothing
    // else.
    WindowMatcher dolphinMatcher = classMatcher(QStringLiteral("org.kde.dolphin"));
    CHECK(config.storeGeometry(dolphinMatcher, dragged));
    const AppConfig adjustedDialog = config.getAppConfig(
        query(QStringLiteral("org.kde.dolphin"), {}, 5));
    CHECK(!adjustedDialog.showButtons);
    CHECK(sameGeometry(adjustedDialog.geometry, dragged));

    // `drawOnDecoratedWindows: "auto"` follows the decoration in use. With our
    // own decoration selected there are no other window controls to leave
    // alone, so the panel is drawn.
    CHECK(config.kosDecorationSelected());
    CHECK(plain.drawOnDecoratedWindows);

    // And it is overridable either way.
    writeUserConfig(R"({
        "default": { "drawOnDecoratedWindows": "never" },
        "apps": { "firefox": { "drawOnDecoratedWindows": "always" } }
    })");
    ButtonConfig overridden;
    CHECK(!overridden.getAppConfig(query(QStringLiteral("konsole")))
               .drawOnDecoratedWindows);
    CHECK(overridden.getAppConfig(query(QStringLiteral("firefox")))
              .drawOnDecoratedWindows);
    // The hand-written JSON is the only place this can come from, so a
    // machine-written rule never changes it.
    CHECK(overridden.getAppConfig(query(QStringLiteral("firefox")))
              .drawOnDecoratedWindows);

    writeKwinrc("breeze");
    ButtonConfig breeze;
    CHECK(!breeze.kosDecorationSelected());
    writeUserConfig(R"({ "default": {} })");
    ButtonConfig autoConfig;
    CHECK(!autoConfig.getAppConfig(query(QStringLiteral("konsole")))
               .drawOnDecoratedWindows);
}

// ---------------------------------------------------------------------------
// The machine-written file
// ---------------------------------------------------------------------------

void testStore()
{
    removeRulesFile();

    WindowRuleStore store;
    CHECK(store.count() == 0);
    CHECK(store.path() == rulesPath());

    PanelGeometry geometry;
    geometry.offset = AppOffset{12, 8};
    PanelGeometry other = geometry;
    other.buttonSize = 18;

    CHECK(store.store(classMatcher(QStringLiteral("code")), geometry));
    CHECK(store.count() == 1);
    CHECK(QFile::exists(rulesPath()));

    PanelGeometry found;
    CHECK(store.found(query(QStringLiteral("code")), &found));
    CHECK(sameGeometry(found, geometry));
    CHECK(!store.found(query(QStringLiteral("konsole")), &found));

    const QByteArray first = readFile(rulesPath());
    CHECK(!first.isEmpty());

    // The same window adjusted again replaces its rule rather than adding a
    // second one, and the entry moves to the front.
    CHECK(store.store(classMatcher(QStringLiteral("konsole")), other));
    CHECK(store.count() == 2);
    CHECK(store.store(classMatcher(QStringLiteral("code")), other));
    CHECK(store.count() == 2);
    CHECK(store.found(query(QStringLiteral("code")), &found));
    CHECK(sameGeometry(found, other));
    CHECK(readFile(rulesPath()) != first);

    // The geometry the whole drag positioned is what is stored, and a store
    // that changes nothing does not rewrite the file.
    const QByteArray stable = readFile(rulesPath());
    const QDateTime stableTime = QFileInfo(rulesPath()).lastModified();
    CHECK(store.store(classMatcher(QStringLiteral("code")), other));
    CHECK(store.count() == 2);
    CHECK(readFile(rulesPath()) == stable);
    CHECK(QFileInfo(rulesPath()).lastModified() == stableTime);

    // A store that does change something does rewrite it.
    PanelGeometry third = other;
    third.buttonSize = 21;
    CHECK(store.store(classMatcher(QStringLiteral("code")), third));
    CHECK(readFile(rulesPath()) != stable);

    // A file that was written by hand -- or by a version that had a bug -- is
    // read through the same clamp the gesture goes through.
    writeFile(rulesPath(), R"({
        "version": 1,
        "rules": [
            { "match": { "class": "absurd" },
              "geometry": { "buttonSize": 100000, "buttonSpacing": -50,
                            "panelPadding": 900, "offset": { "x": -3, "y": 2 } } },
            { "match": {}, "geometry": { "buttonSize": 20 } },
            { "match": { "type": "not-a-type" }, "geometry": { "buttonSize": 20 } }
        ]
    })");
    WindowRuleStore loaded;
    CHECK(loaded.count() == 1);
    PanelGeometry bounded;
    CHECK(loaded.found(query(QStringLiteral("absurd")), &bounded));
    CHECK(near(bounded.buttonSize, MaxButtonSize));
    CHECK(near(bounded.buttonSpacing, 0));
    CHECK(near(bounded.panelPadding, MaxPanelPadding));
    CHECK(near(bounded.offset.x, 0));
    CHECK(near(bounded.offset.y, 2));
    // The rule that matched nothing is not a rule that matches everything.
    CHECK(!loaded.found(query(QStringLiteral("anything")), &bounded));

    // Writing a rule through the store leaves the bytes the reader can read
    // back: a round trip through the file is lossless.
    WindowRuleStore writing;
    PanelGeometry written;
    written.position = ButtonPosition::Left;
    written.offset = AppOffset{3, 4};
    written.buttonSize = 16;
    written.buttonSpacing = 9;
    written.panelPadding = 5;
    written.panelPaddingX = 7;
    CHECK(writing.store(classMatcher(QStringLiteral("roundtrip")), written));
    WindowRuleStore reading;
    PanelGeometry readBack;
    CHECK(reading.found(query(QStringLiteral("roundtrip")), &readBack));
    CHECK(readBack.position == ButtonPosition::Left);
    CHECK(near(readBack.offset.x, 3));
    CHECK(near(readBack.offset.y, 4));
    CHECK(near(readBack.buttonSize, 16));
    CHECK(near(readBack.buttonSpacing, 9));
    CHECK(near(readBack.panelPadding, 5));
    CHECK(near(readBack.panelPaddingX, 7));

    // A matcher that says nothing about a window is refused rather than stored:
    // it would apply to every window there is.
    CHECK(!writing.store(WindowMatcher{}, written));
}

} // namespace

int main(int argc, char **argv)
{
    QTemporaryDir dir;
    if (!dir.isValid()) {
        std::fprintf(stderr, "FAIL could not create a temporary directory\n");
        return 1;
    }
    g_dir = &dir;

    // Everything the plugin reads from the user's environment is redirected
    // into the temporary directory before anything looks at it: the hand-written
    // configuration, kwinrc, and the machine-written rules file.
    qputenv("XDG_DATA_HOME", dataHome().toUtf8());
    qputenv("XDG_CONFIG_HOME", configHome().toUtf8());
    qputenv("XDG_CONFIG_DIRS", (configHome() + "/system").toUtf8());
    qputenv("XDG_DATA_DIRS", (dataHome() + "/system").toUtf8());

    QCoreApplication app(argc, argv);
    QDir().mkpath(dataHome());
    QDir().mkpath(configHome());

    testMatchers();
    testGeometry();
    testEdgeResize();
    testTileMenu();
    testResolution();
    testStore();

    std::printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
