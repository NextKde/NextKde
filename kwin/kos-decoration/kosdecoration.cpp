#include "kosdecoration.h"
#include "nativebutton.h"
#include "../kos-bridge/windowappearance/appearanceprotocol.h"
#include "../kos-bridge/windowappearance/contour.h"

#include <KDecoration3/DecoratedWindow>
#include <KDecoration3/DecorationSettings>
#include <KDecoration3/ScaleHelpers>

#include <QFontMetricsF>
#include <QPainter>
#include <QDynamicPropertyChangeEvent>
#include <QPainterPath>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QScopedValueRollback>

namespace KOS
{

namespace
{
// Logical pixels; native decoration painting follows the output scale.
constexpr qreal TitleBarHeight = 34.0;
// The window has no visible side or bottom frame, so resizing relies entirely
// on this invisible grab margin.
constexpr qreal ResizeGrab = 4.0;
// Minimum caption clearance; button groups reserve additional space.
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

    const auto factory = [](KDecoration3::DecorationButtonType type, KDecoration3::Decoration *decoration, QObject *parent) {
        return new NativeButton(type, decoration, parent);
    };
    m_leftButtons = new KDecoration3::DecorationButtonGroup(KDecoration3::DecorationButtonGroup::Position::Left, this, factory);
    m_rightButtons = new KDecoration3::DecorationButtonGroup(KDecoration3::DecorationButtonGroup::Position::Right, this, factory);
    for (auto *group : {m_leftButtons, m_rightButtons}) {
        group->setSpacing(0);
        connect(group, &KDecoration3::DecorationButtonGroup::geometryChanged, this, &KosDecoration::updateDerivedGeometry);
    }
    setProperty(WindowAppearance::DecorationControlsProperty, true);
    connect(&m_buttonWatcher, &QFileSystemWatcher::fileChanged, this, &KosDecoration::refreshButtonPreferences);
    connect(&m_buttonWatcher, &QFileSystemWatcher::directoryChanged, this, &KosDecoration::refreshButtonPreferences);
    refreshButtonPreferences();
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
    setBorders(QMarginsF(0, snap(TitleBarHeight), 0, 0));
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
    if (!window() || m_updatingGeometry) return;
    const QScopedValueRollback guard(m_updatingGeometry, true);
    if (m_leftButtons) m_leftButtons->setPos(QPointF(7.5, (borderTop()-28)/2));
    if (m_rightButtons) m_rightButtons->setPos(QPointF(size().width()-7.5-m_rightButtons->geometry().width(), (borderTop()-28)/2));

    setTitleBar(QRectF(0, 0, size().width(), borderTop()));
    update();
}

void KosDecoration::refreshButtonPreferences()
{
    const QString directory = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)+"/kos";
    const QString path = directory+"/window-buttons.json";
    for (const auto &dir : {QFileInfo(directory).path(), directory})
        if (QFileInfo::exists(dir) && !m_buttonWatcher.directories().contains(dir)) m_buttonWatcher.addPath(dir);
    if (QFileInfo::exists(path) && !m_buttonWatcher.files().contains(path)) m_buttonWatcher.addPath(path);
    QFile file(path);
    if (file.exists() && !file.open(QIODevice::ReadOnly)) return;
    const auto doc = file.isOpen() ? QJsonDocument::fromJson(file.readAll()) : QJsonDocument(QJsonObject{});
    if (!doc.isObject()) return;
    const bool hover = doc.object().value("default").toObject().value("glyphMode").toString() == "hover";
    if (hover != m_hoverGlyphs) { m_hoverGlyphs = hover; update(); }
}
bool KosDecoration::showButtonGlyphs() const
{
    if (!m_hoverGlyphs) return true;
    for (auto *group : {m_leftButtons,m_rightButtons})
        if (group) for (auto *button : group->buttons()) if (button->isHovered()) return true;
    return false;
}

QColor KosDecoration::barColor() const
{
    auto *client = window();
    if (!client) {
        return QColor(0x2b, 0x2f, 0x36);
    }

    // The native controls share this titlebar; no background sampling.
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

    // Keep the caption centered and elide before either native button group.
    const qreal margin = std::max({CaptionSideMargin,
        m_leftButtons ? m_leftButtons->geometry().width()+16 : 0.,
        m_rightButtons ? m_rightButtons->geometry().width()+16 : 0.});
    const qreal available = size().width() - 2.0 * margin;
    if (available <= 0.0) {
        return;
    }

    const QRectF bar(margin, 0, available, borderTop());
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
    if (m_leftButtons) m_leftButtons->paint(painter, repaintArea);
    if (m_rightButtons) m_rightButtons->paint(painter, repaintArea);

    painter->restore();
}

} // namespace KOS
