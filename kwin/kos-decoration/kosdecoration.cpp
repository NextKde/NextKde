#include "kosdecoration.h"
#include "../kos-bridge/windowappearance/appearanceprotocol.h"
#include "../kos-bridge/windowappearance/contour.h"

#include <KDecoration3/DecoratedWindow>
#include <KDecoration3/DecorationSettings>
#include <KDecoration3/ScaleHelpers>

#include <QFontMetricsF>
#include <QPainter>
#include <QDynamicPropertyChangeEvent>
#include <QPainterPath>

namespace KOS
{

namespace
{
// Logical pixels. KWin scales them per output.
//
// TitleBarHeight is tied to the effect that draws the three-dot panel: with
// the shipped defaults in ~/.config/kos/window-buttons.json (offset.y = 6,
// buttonSize = 14, panelPadding = 4.5) the dots are centred at
// offset.y + (buttonSize + 2 * panelPadding) / 2 = 17.5, while this bar's
// centre is TitleBarHeight / 2 = 17. Changing this height therefore moves the
// bar away from the dots, so check that file before touching it.
constexpr qreal TitleBarHeight = 34.0;
// The window has no visible side or bottom frame, so resizing relies entirely
// on this invisible grab margin.
constexpr qreal ResizeGrab = 4.0;
// The caption is inset symmetrically so a long title stops short of the
// corners. It cannot reserve room for the effect's button panel: that panel
// can be configured onto either end of the bar, while this plugin only ever
// sees the title bar itself.
constexpr qreal CaptionSideMargin = 8.0;
}

KosDecoration::KosDecoration(QObject *parent, const QVariantList &args)
    : KDecoration3::Decoration(parent, args)
{
}

KosDecoration::~KosDecoration() = default;

bool KosDecoration::event(QEvent *event)
{
    if (event->type() == QEvent::DynamicPropertyChange) {
        const auto *change = static_cast<QDynamicPropertyChangeEvent *>(event);
        if (change->propertyName() == WindowAppearance::DecorationRadiiProperty) {
            update();
        } else if (change->propertyName() == WindowAppearance::DecorationShadowProperty) {
            const QVariant value = property(WindowAppearance::DecorationShadowProperty);
            if (value.canConvert<std::shared_ptr<KDecoration3::DecorationShadow>>()) {
                if (!m_bridgeShadowActive) {
                    m_shadowBeforeBridge = shadow();
                    m_bridgeShadowActive = true;
                }
                setShadow(value.value<std::shared_ptr<KDecoration3::DecorationShadow>>());
            } else if (m_bridgeShadowActive) {
                setShadow(m_shadowBeforeBridge);
                m_shadowBeforeBridge.reset();
                m_bridgeShadowActive = false;
            }
        }
    }
    return KDecoration3::Decoration::event(event);
}

bool KosDecoration::init()
{
    auto *client = window();
    if (!client) {
        return false;
    }

    setOpaque(false);
    setProperty(WindowAppearance::DecorationAppearanceSupportedProperty, true);

    updateLayout();

    // Geometry-affecting changes.
    connect(client, &KDecoration3::DecoratedWindow::maximizedChanged,
            this, &KosDecoration::updateLayout);
    connect(client, &KDecoration3::DecoratedWindow::shadedChanged,
            this, &KosDecoration::updateLayout);
    connect(client, &KDecoration3::DecoratedWindow::widthChanged,
            this, &KosDecoration::updateLayout);
    connect(client, &KDecoration3::DecoratedWindow::heightChanged,
            this, &KosDecoration::updateLayout);
    connect(client, &KDecoration3::DecoratedWindow::scaleChanged,
            this, &KosDecoration::updateLayout);
    // The borders are snapped against nextScale(), so a pending scale change
    // has to re-run the layout even before it becomes current.
    connect(client, &KDecoration3::DecoratedWindow::nextScaleChanged,
            this, &KosDecoration::updateLayout);

    // setBorders() only reaches borders() once the compositor applies the next
    // state, so the title bar rect is refreshed from the applied value rather
    // than from the requested one.
    connect(this, &KDecoration3::Decoration::bordersChanged,
            this, &KosDecoration::updateDerivedGeometry);

    // Repaint-only changes. Activation greys the caption and the outline, so
    // the whole decoration is invalidated rather than just the caption.
    connect(client, &KDecoration3::DecoratedWindow::activeChanged,
            this, qOverload<>(&KosDecoration::update));
    connect(client, &KDecoration3::DecoratedWindow::paletteChanged,
            this, qOverload<>(&KosDecoration::update));
    connect(client, &KDecoration3::DecoratedWindow::captionChanged,
            this, qOverload<>(&KosDecoration::update));

    if (auto config = settings()) {
        connect(config.get(), &KDecoration3::DecorationSettings::fontChanged,
                this, &KosDecoration::updateLayout);
    }

    return true;
}

void KosDecoration::updateLayout()
{
    auto *client = window();
    if (!client) {
        return;
    }

    const bool maximized = client->isMaximized();

    // Borders must land on whole device pixels. Under fractional scaling they
    // otherwise do not: 34 logical px at scale 1.25 is 42.5 device px, and the
    // boundary row shared between the title bar and the client surface is then
    // covered by neither of them in full, which reads as a seam. These are the
    // buffered properties, so they are snapped against the scale they will be
    // applied with, not the current one.
    const qreal scale = client->nextScale();
    const auto snap = [scale](qreal value) {
        return KDecoration3::snapToPixelGrid(value, scale);
    };

    // No visible side or bottom frame in either state.
    setBorders(QMarginsF(0, client->isShaded() ? 0 : snap(TitleBarHeight), 0, 0));
    setResizeOnlyBorders(maximized
        ? QMarginsF(0, 0, 0, 0)
        : QMarginsF(snap(ResizeGrab), 0, snap(ResizeGrab), snap(ResizeGrab)));

    // Geometry policy belongs to kos-bridge. The resolved corner property
    // shapes the titlebar, and the shadow property relays DecorationShadow.
    // Do not write another native radius or outline here.

    // Runs again on bordersChanged() when the new borders are actually
    // applied; calling it here as well covers the changes that move nothing
    // buffered, such as the window being resized.
    updateDerivedGeometry();
}

void KosDecoration::updateDerivedGeometry()
{
    if (!window()) {
        return;
    }

    setTitleBar(QRectF(0, 0, size().width(), borderTop()));
    update();
}

QColor KosDecoration::barColor() const
{
    auto *client = window();
    if (!client) {
        return QColor(0x2b, 0x2f, 0x36);
    }

    // Fully opaque on purpose: the kos-bridge effect reads this strip back to
    // choose the button panel's tint, so a translucent bar over the
    // compositor's blur would tint the panel from a blend of the bar and
    // whatever sits behind the window.
    return client->palette().color(QPalette::Window);
}

QColor KosDecoration::captionColor() const
{
    auto *client = window();
    if (!client) {
        return Qt::white;
    }
    QColor text = client->palette().color(QPalette::WindowText);
    if (!client->isActive()) {
        text.setAlphaF(0.55);
    }
    return text;
}

void KosDecoration::paintTitleBar(QPainter *painter)
{
    const QRectF bar(0, 0, size().width(), borderTop());
    if (bar.isEmpty()) {
        return;
    }

    // The bridge resolves one contour for content, decoration and shadow.
    // Without the bridge property this decoration retains its square bar.
    painter->save();
    painter->setPen(Qt::NoPen);
    painter->setBrush(barColor());
    const QVariant resolved = property(WindowAppearance::DecorationRadiiProperty);
    if (resolved.canConvert<QVector4D>()) {
        const QVector4D radius = resolved.value<QVector4D>();
        const WindowAppearance::CornerRadii corners{
            radius.x(), radius.y(), radius.z(), radius.w()};
        QPainterPath strip;
        strip.addRect(bar);
        // Fill the intersection instead of applying an aliased painter
        // clip: the atlas must retain antialiased, transparent top corners.
        painter->drawPath(WindowAppearance::contourPath(
            QRectF(QPointF(), size()), corners, 0.0).intersected(strip));
    } else {
        painter->drawRect(bar);
    }
    painter->restore();

    // Neither edge of the title bar gets a hairline of its own: the bottom is
    // left bare because macOS runs the title bar into the content as one
    // continuous surface, and a hairline there reads as a crack between the
    // decoration and the client. The top edge is similarly bare -- KWin is not
    // asked for a frame around the window either (see updateLayout), so there
    // is nothing for one to line up with.
}

void KosDecoration::paintCaption(QPainter *painter)
{
    auto *client = window();
    auto config = settings();
    if (!client || !config) {
        return;
    }

    const QString caption = client->caption();
    if (caption.isEmpty()) {
        return;
    }

    // Centred on the window, macOS-style. The inset is symmetric, so the
    // caption stays centred whichever end of the bar the effect's panel is
    // configured onto, and a long title elides instead of running to the edge.
    const qreal available = size().width() - 2.0 * CaptionSideMargin;
    if (available <= 0.0) {
        return;
    }

    const QRectF bar(CaptionSideMargin, 0, available, borderTop());
    const QFontMetricsF metrics(config->font());
    const QString elided = metrics.elidedText(caption, Qt::ElideMiddle, available);

    painter->save();
    painter->setFont(config->font());
    painter->setPen(captionColor());
    const QVariant resolved = property(WindowAppearance::DecorationRadiiProperty);
    if (resolved.canConvert<QVector4D>()) {
        const QVector4D r = resolved.value<QVector4D>();
        painter->setClipPath(WindowAppearance::contourPath(QRectF(QPointF(), size()),
            WindowAppearance::CornerRadii{r.x(), r.y(), r.z(), r.w()}, 0.0),
            Qt::IntersectClip);
    }
    painter->drawText(bar, Qt::AlignCenter | Qt::TextSingleLine, elided);
    painter->restore();
}

void KosDecoration::paint(QPainter *painter, const QRectF &repaintArea)
{
    if (!window() || size().isEmpty()) {
        return;
    }

    // repaintArea is deliberately not used as a clip. KWin hands it over in
    // whole logical pixels, so under fractional scaling its bottom edge lands
    // mid-pixel: 34 logical at scale 1.25 is 42.5 device px, and clipping an
    // antialiasing painter there leaves the title bar's last device row only
    // partly covered, which reads as a seam against the client below it. The
    // compositor already limits what it takes from this painter, so the clip
    // only did harm.
    Q_UNUSED(repaintArea)

    painter->save();
    painter->setRenderHint(QPainter::Antialiasing, true);

    paintTitleBar(painter);
    paintCaption(painter);

    painter->restore();
}

} // namespace KOS
