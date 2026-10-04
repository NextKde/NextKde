#include "dockwindowanimationeffect.h"

#include <effect/effecthandler.h>
#include <window.h>

#include <KConfigGroup>
#include <KSharedConfig>

#include <QDBusConnection>
#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLoggingCategory>
#include <QPointer>
#include <QTimer>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <numbers>

Q_LOGGING_CATEGORY(KWIN_KOS_DOCK_ANIMATION, "kwin_effect_kos_dock_animation")

namespace KWin
{

namespace
{
constexpr auto dbusPath = "/KOSDockWindowAnimation";

// Fades the glass material of a window this effect is animating. The vendored
// glass effect (see kwin/glass-effect/src/blur.cpp) blurs the backdrop
// where the window's frame is, and that region cannot follow the deformation
// this effect applies. Fading the material out while the window is clearly
// moving and back in while it is coming home keeps a blurred copy of the title
// bar's wallpaper from being left behind in the first place, without the
// material visibly switching on or off. EffectWindow::data() is shared between
// all effects, so both sides read the same role; unset means 1 (fully opaque),
// which is what every other window sees.
constexpr int KosDockAnimationGlassFadeRole = 0x4b4f5342; // "KOSB"
// Share of the timeline used for that fade. Minimizing fades out over the first
// part, restoring and opening fade in over the last one.
constexpr qreal kGlassFadeSpan = 0.35;

QVariant ownerVariant(const Effect *effect)
{
    return QVariant::fromValue(static_cast<void *>(const_cast<Effect *>(effect)));
}

qreal smoothStep(qreal value)
{
    const qreal clamped = std::clamp(value, 0.0, 1.0);
    return clamped * clamped * (3.0 - 2.0 * clamped);
}

qreal smootherStep(qreal value)
{
    const qreal clamped = std::clamp(value, 0.0, 1.0);
    return clamped * clamped * clamped
        * (clamped * (clamped * 6.0 - 15.0) + 10.0);
}

// Maps each horizontal mesh row between the two circular sides of an
// asymmetric rounded rectangle. Keeping every row horizontal and its X
// coordinates monotonic prevents the corner geometry from twisting quads.
QPointF roundedRectCoordinate(qreal u, qreal v, const QSizeF &size,
                              qreal topRadiusRatio,
                              qreal bottomRadiusRatio)
{
    const qreal width = std::max(1.0, size.width());
    const qreal height = std::max(1.0, size.height());
    const qreal shortSide = std::min(width, height);
    const qreal topRadius = shortSide
        * std::clamp(topRadiusRatio, 0.0, 0.5);
    const qreal bottomRadius = shortSide
        * std::clamp(bottomRadiusRatio, 0.0, 0.5);
    const qreal normalizedU = std::clamp(u, 0.0, 1.0);
    const qreal normalizedV = std::clamp(v, 0.0, 1.0);
    const qreal y = normalizedV * height;

    qreal inset = 0.0;
    if (topRadius > 0.0 && y < topRadius) {
        const qreal dy = topRadius - y;
        inset = topRadius - std::sqrt(std::max(
            0.0, topRadius * topRadius - dy * dy));
    } else if (bottomRadius > 0.0 && y > height - bottomRadius) {
        const qreal dy = y - (height - bottomRadius);
        inset = bottomRadius - std::sqrt(std::max(
            0.0, bottomRadius * bottomRadius - dy * dy));
    }

    const qreal rowWidth = std::max(0.0, width - inset * 2.0);
    return QPointF((inset + normalizedU * rowWidth) / width, normalizedV);
}

}

DockWindowAnimationEffect::DockWindowAnimationEffect()
{
    reconfigure(ReconfigureAll);

    connect(effects, &EffectsHandler::windowAdded,
            this, &DockWindowAnimationEffect::handleWindowAdded);
    connect(effects, &EffectsHandler::windowDeleted,
            this, &DockWindowAnimationEffect::handleWindowDeleted);
    for (EffectWindow *window : effects->stackingOrder())
        watchWindow(window);

    // The deformation deliberately keeps sub-pixel vertex positions. Snapping
    // the 40px mesh to device pixels produces visible steps near the icon.
    setVertexSnappingMode(RenderGeometry::VertexSnappingMode::None);

    auto bus = QDBusConnection::sessionBus();
    if (!bus.registerObject(QString::fromLatin1(dbusPath), this,
                            QDBusConnection::ExportScriptableSlots
                                | QDBusConnection::ExportAllSignals)) {
        qCWarning(KWIN_KOS_DOCK_ANIMATION)
            << "Unable to register Dock animation D-Bus endpoint";
    }
}

DockWindowAnimationEffect::~DockWindowAnimationEffect()
{
    QDBusConnection::sessionBus().unregisterObject(QString::fromLatin1(dbusPath));
    // When the effect is unloaded, KWin may already have deleted windows that
    // still key these tables (windowDeleted is not guaranteed to have reached
    // us first). Deleted windows are gone from the stacking order, so only a
    // key that is still listed there may be dereferenced.
    const QList<EffectWindow *> liveWindows =
        effects ? effects->stackingOrder() : QList<EffectWindow *>();
    const auto animatedWindows = m_animations.keys();
    for (EffectWindow *window : animatedWindows) {
        if (liveWindows.contains(window))
            finishAnimation(window);
    }
    // Entries left in m_animations belong to windows that are already gone.
    // They cannot be erased as-is: WindowAnimation::visibleRef stores a raw
    // EffectWindow* and ~EffectWindowVisibleRef() would call unrefVisible()
    // on the freed window. Replace the ref with an empty one first —
    // placement new ends the old object's lifetime without running its
    // destructor, which is exactly the dereference to avoid.
    for (auto it = m_animations.begin(); it != m_animations.end();) {
        new (&it.value().visibleRef) EffectWindowVisibleRef();
        it = m_animations.erase(it);
    }
    const auto windows = m_claimedRoles.keys();
    for (EffectWindow *window : windows) {
        if (liveWindows.contains(window))
            releaseClaim(window);
        else
            m_claimedRoles.remove(window);
    }
}

bool DockWindowAnimationEffect::supported()
{
    return OffscreenEffect::supported() && effects->animationsSupported();
}

void DockWindowAnimationEffect::reconfigure(ReconfigureFlags flags)
{
    Q_UNUSED(flags)
    const KConfigGroup group(KSharedConfig::openConfig(QStringLiteral("kwinrc")),
                             QStringLiteral("Effect-kos_dock_window_animation"));
    m_openDuration = std::clamp(group.readEntry("OpenDuration", 300), 80, 1200);
    // Keep the Dock animation independent from KWin's legacy scale duration.
    m_minimizeDuration = std::clamp(group.readEntry("GenieDuration", 300), 160, 1200);
    m_restoreDuration = std::clamp(group.readEntry("RestoreDuration", 200), 80, 1200);
    m_morphStyle = group.readEntry("AnimationStyle", QStringLiteral("scale"))
        == QLatin1String("genie") ? MorphStyle::Genie : MorphStyle::Scale;
}

QString DockWindowAnimationEffect::normalizedId(const QString &value) const
{
    QString result = value.trimmed().toLower();
    if (result.endsWith(QStringLiteral(".desktop")))
        result.chop(8);
    // Some Electron applications expose a human-readable WM_CLASS while
    // their desktop entry uses hyphens, e.g. "GitHub Desktop" versus
    // "github-desktop". Keep punctuation intact and only canonicalise
    // whitespace so unrelated desktop IDs cannot collapse onto one key.
    result = result.simplified();
    result.replace(QLatin1Char(' '), QLatin1Char('-'));
    return result;
}

void DockWindowAnimationEffect::updateTargets(const QString &payload)
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        qCWarning(KWIN_KOS_DOCK_ANIMATION) << "Invalid Dock target payload" << error.errorString();
        return;
    }

    QHash<QString, Target> nextByApp;
    QHash<QString, Target> nextByWindow;
    const QJsonArray targets = document.object().value(QStringLiteral("targets")).toArray();
    for (const QJsonValue &value : targets) {
        const QJsonObject object = value.toObject();
        Target target;
        target.appId = normalizedId(object.value(QStringLiteral("appId")).toString());
        target.windowId = object.value(QStringLiteral("windowId")).toString();
        target.geometry = QRectF(object.value(QStringLiteral("x")).toDouble(),
                                 object.value(QStringLiteral("y")).toDouble(),
                                 object.value(QStringLiteral("width")).toDouble(),
                                 object.value(QStringLiteral("height")).toDouble());
        if ((!target.appId.isEmpty() || !target.windowId.isEmpty())
                && target.geometry.isValid() && !target.geometry.isEmpty()) {
            if (!target.windowId.isEmpty())
                nextByWindow.insert(target.windowId, target);
            // Prefer the persistent launcher icon as the app-level opening
            // target. Per-window icons remain available through the exact
            // window map for closing and must not overwrite that launcher.
            if (!target.appId.isEmpty()
                    && (target.windowId.isEmpty() || !nextByApp.contains(target.appId)))
                nextByApp.insert(target.appId, target);
        }
    }
    m_targetsByApp = std::move(nextByApp);
    m_targetsByWindow = std::move(nextByWindow);
}

bool DockWindowAnimationEffect::prepareLaunch(const QString &payload)
{
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &error);
    if (error.error != QJsonParseError::NoError || !document.isObject()) {
        qCWarning(KWIN_KOS_DOCK_ANIMATION)
            << "Invalid Dock launch ticket" << error.errorString();
        return false;
    }

    const QJsonObject root = document.object();
    const QJsonObject object = root.value(QStringLiteral("target")).toObject();
    Target target;
    target.appId = normalizedId(object.value(QStringLiteral("appId")).toString());
    target.windowId = object.value(QStringLiteral("windowId")).toString();
    target.geometry = QRectF(object.value(QStringLiteral("x")).toDouble(),
                             object.value(QStringLiteral("y")).toDouble(),
                             object.value(QStringLiteral("width")).toDouble(),
                             object.value(QStringLiteral("height")).toDouble());
    if (target.appId.isEmpty() || !target.geometry.isValid()
            || target.geometry.isEmpty()) {
        qCWarning(KWIN_KOS_DOCK_ANIMATION)
            << "Dock launch ticket has no valid target" << target.appId
            << target.geometry;
        return false;
    }

    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    m_pendingLaunches.removeIf([now](const PendingLaunch &launch) {
        return launch.expiresAt <= now;
    });

    PendingLaunch launch;
    launch.target = target;
    launch.aliases << target.appId;
    const QJsonArray aliases = root.value(QStringLiteral("aliases")).toArray();
    for (const QJsonValue &value : aliases) {
        const QString alias = normalizedId(value.toString());
        if (!alias.isEmpty() && !launch.aliases.contains(alias))
            launch.aliases << alias;
    }
    const int expiresInMs = std::clamp(
        root.value(QStringLiteral("expiresInMs")).toInt(5000), 500, 10000);
    launch.expiresAt = now + expiresInMs;
    m_pendingLaunches.append(std::move(launch));
    while (m_pendingLaunches.size() > 16)
        m_pendingLaunches.removeFirst();
    ++m_launchTicketCount;

    qCInfo(KWIN_KOS_DOCK_ANIMATION)
        << "armed one-shot Dock launch ticket" << target.appId
        << "aliases" << m_pendingLaunches.constLast().aliases
        << "target" << target.geometry;
    return true;
}

QString DockWindowAnimationEffect::status() const
{
    const QJsonObject object{
        {QStringLiteral("targetsByApp"), m_targetsByApp.size()},
        {QStringLiteral("targetsByWindow"), m_targetsByWindow.size()},
        {QStringLiteral("animatingWindows"), m_animations.size()},
        {QStringLiteral("pendingLaunchTickets"), m_pendingLaunches.size()},
        {QStringLiteral("openDuration"), m_openDuration},
        {QStringLiteral("minimizeDuration"), m_minimizeDuration},
        {QStringLiteral("restoreDuration"), m_restoreDuration},
        {QStringLiteral("deformation"), m_morphStyle == MorphStyle::Genie
            ? QStringLiteral("water-drop-mesh-and-fade")
            : QStringLiteral("direct-scale-and-fade")},
        {QStringLiteral("textureHandoff"), QStringLiteral("disabled")},
        {QStringLiteral("openAnimationCount"), static_cast<qint64>(m_openAnimationCount)},
        {QStringLiteral("minimizeAnimationCount"), static_cast<qint64>(m_minimizeAnimationCount)},
        {QStringLiteral("restoreAnimationCount"), static_cast<qint64>(m_restoreAnimationCount)},
        {QStringLiteral("launchTicketCount"), static_cast<qint64>(m_launchTicketCount)},
        {QStringLiteral("launchTicketConsumedCount"), static_cast<qint64>(m_launchTicketConsumedCount)},
        {QStringLiteral("lastAnimatedAppId"), m_lastAnimatedAppId},
    };
    return QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact));
}

bool DockWindowAnimationEffect::eligibleWindow(EffectWindow *window) const
{
    if (!window || effects->hasActiveFullScreenEffect())
        return false;
    if (!window->isNormalWindow() && !window->isDialog())
        return false;
    return true;
}

std::optional<DockWindowAnimationEffect::Target>
DockWindowAnimationEffect::targetForWindow(EffectWindow *window) const
{
    if (!window)
        return std::nullopt;

    const QString internalId = window->internalId().toString(QUuid::WithoutBraces);
    if (const auto it = m_targetsByWindow.constFind(internalId);
        it != m_targetsByWindow.cend()) {
        return *it;
    }

    const QStringList candidates = windowIdentityCandidates(window);
    for (const QString &candidate : std::as_const(candidates)) {
        const QString id = normalizedId(candidate);
        if (const auto it = m_targetsByApp.constFind(id); it != m_targetsByApp.cend())
            return *it;
    }
    return std::nullopt;
}

QStringList DockWindowAnimationEffect::windowIdentityCandidates(
    EffectWindow *window) const
{
    QStringList candidates;
    if (!window)
        return candidates;
    if (window->window()) {
        candidates << window->window()->desktopFileName()
                   << window->window()->resourceClass()
                   << window->window()->resourceName();
    }
    candidates << window->windowClass().split(
        QLatin1Char(' '), Qt::SkipEmptyParts);
    candidates.removeAll(QString());
    return candidates;
}

std::optional<DockWindowAnimationEffect::Target>
DockWindowAnimationEffect::takePendingLaunchForWindow(EffectWindow *window)
{
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    m_pendingLaunches.removeIf([now](const PendingLaunch &launch) {
        return launch.expiresAt <= now;
    });

    QStringList candidates;
    for (const QString &candidate : windowIdentityCandidates(window)) {
        const QString id = normalizedId(candidate);
        if (!id.isEmpty() && !candidates.contains(id))
            candidates << id;
    }
    for (qsizetype index = 0; index < m_pendingLaunches.size(); ++index) {
        const PendingLaunch &launch = m_pendingLaunches.at(index);
        bool matches = false;
        for (const QString &candidate : std::as_const(candidates)) {
            if (launch.aliases.contains(candidate)) {
                matches = true;
                break;
            }
        }
        if (!matches)
            continue;

        const Target target = launch.target;
        m_pendingLaunches.removeAt(index);
        ++m_launchTicketConsumedCount;
        return target;
    }
    return std::nullopt;
}

bool DockWindowAnimationEffect::claim(EffectWindow *window, int role)
{
    const QVariant currentOwner = window->data(role);
    const QVariant mine = ownerVariant(this);
    if (currentOwner.isValid() && currentOwner != mine)
        return false;
    window->setData(role, mine);
    m_claimedRoles.insert(window, role);
    return true;
}

void DockWindowAnimationEffect::releaseClaim(EffectWindow *window)
{
    if (!window)
        return;
    const auto roleIt = m_claimedRoles.find(window);
    if (roleIt != m_claimedRoles.end()) {
        if (window->data(*roleIt) == ownerVariant(this))
            window->setData(*roleIt, QVariant());
        m_claimedRoles.erase(roleIt);
    }
}

void DockWindowAnimationEffect::finishAnimation(EffectWindow *window)
{
    if (!window)
        return;
    // The window is painted normally again, so the glass material is restored
    // for anything that reads the fade after this animation.
    window->setData(KosDockAnimationGlassFadeRole, 1.0);
    if (const auto it = m_animations.find(window); it != m_animations.end()) {
        unredirect(window);
        m_animations.erase(it);
    }
    releaseClaim(window);
}

void DockWindowAnimationEffect::startAnimation(EffectWindow *window,
                                                const Target &target,
                                                Transition transition)
{
    const QRectF windowGeometry = window->frameGeometry();
    if (windowGeometry.width() <= 1 || windowGeometry.height() <= 1)
        return;

    const int role = [transition]() {
        switch (transition) {
        case Transition::Open:
            return WindowAddedGrabRole;
        case Transition::Minimize:
            return WindowMinimizedGrabRole;
        case Transition::Restore:
            return WindowUnminimizedGrabRole;
        }
        return WindowAddedGrabRole;
    }();

    // A rapid second Dock click reverses the same redirected texture. Release
    // the old grab role before claiming the role for the opposite direction.
    if (m_animations.contains(window))
        releaseClaim(window);
    if (!claim(window, role))
        return;

    const TimeLine::Direction direction = transition == Transition::Minimize
        ? TimeLine::Forward : TimeLine::Backward;
    const int durationMs = transition == Transition::Minimize
        ? m_minimizeDuration
        : (transition == Transition::Restore ? m_restoreDuration : m_openDuration);
    const auto duration = std::chrono::milliseconds(durationMs);

    WindowAnimation &animation = m_animations[window];
    const bool reversesRedirectedAnimation = animation.timeLine.running()
        && animation.transition != Transition::Open
        && transition != Transition::Open;
    if (reversesRedirectedAnimation) {
        // Reversing minimize/restore keeps the existing visibility reference
        // and redirected snapshot.
        if (animation.timeLine.direction() != direction)
            animation.timeLine.toggleDirection();
        animation.timeLine.setDuration(duration);
    } else {
        animation.timeLine = TimeLine(duration, direction);
        animation.timeLine.setEasingCurve(QEasingCurve::Linear);
        animation.visibleRef = transition == Transition::Open
            ? EffectWindowVisibleRef()
            : EffectWindowVisibleRef(
                window, EffectWindow::PAINT_DISABLED_BY_MINIMIZE);
    }
    animation.target = target;
    animation.transition = transition;
    // 固化记录 CSD 阴影缓冲区相对偏移量（用于 Wayland 客户端最小化几何补偿）
    if (m_csdOffsets.contains(window)) {
        animation.csdOffset = m_csdOffsets.value(window);
    } else if (window && !window->isMinimized()) {
        const QRectF frame = window->frameGeometry();
        const QRectF buffer = window->bufferGeometry();
        if (frame.isValid() && buffer.isValid()) {
            const QPointF offset = buffer.topLeft() - frame.topLeft();
            if (offset.x() < -1.0 || offset.y() < -1.0) {
                animation.csdOffset = offset;
                m_csdOffsets.insert(window, offset);
            }
        }
    }

    QString action;
    switch (transition) {
    case Transition::Open:
        ++m_openAnimationCount;
        action = QStringLiteral("opening");
        break;
    case Transition::Minimize:
        ++m_minimizeAnimationCount;
        action = QStringLiteral("minimizing");
        break;
    case Transition::Restore:
        ++m_restoreAnimationCount;
        action = QStringLiteral("restoring");
        break;
    }
    m_lastAnimatedAppId = target.appId;
    QString transitionName;
    switch (transition) {
    case Transition::Open:
        transitionName = QStringLiteral("open");
        break;
    case Transition::Minimize:
        transitionName = QStringLiteral("minimize");
        break;
    case Transition::Restore:
        transitionName = QStringLiteral("restore");
        break;
    }
    Q_EMIT animationStarted(target.appId, target.windowId,
                            transitionName, durationMs);
    qCInfo(KWIN_KOS_DOCK_ANIMATION)
        << action << target.appId
        << "window" << window->internalId()
        << "from/to Dock rect" << target.geometry
        << "csdOffset" << animation.csdOffset;

    redirect(window);
    // Repaint only the motion envelope (frame + shadow margins united with the
    // dock-icon target rect) instead of the whole screen for the first
    // transformed frame. Both rects live in global logical coordinates.
    addAnimationRepaint(window, animation.target.geometry);
}

void DockWindowAnimationEffect::addAnimationRepaint(
    EffectWindow *window, const QRectF &targetGeometry)
{
    // expandedGeometry() covers the frame plus shadow margins; the morph
    // target is the dock-icon rect the window deforms into. The animation
    // only ever draws inside the union of the two, so repaint that union
    // (with a 2px safety margin) rather than the entire screen.
    if (!window)
        return;
    const QRectF region = QRectF(window->expandedGeometry())
        .united(targetGeometry).adjusted(-2, -2, 2, 2);
    effects->addRepaint(qFloor(region.x()), qFloor(region.y()),
                        qCeil(region.width()), qCeil(region.height()));
}

void DockWindowAnimationEffect::drawWindow(
    const RenderTarget &renderTarget, const RenderViewport &viewport,
    EffectWindow *window, int mask, const Region &deviceRegion,
    WindowPaintData &data)
{
    auto it = m_animations.find(window);

    if (it != m_animations.end()
        && it->transition != Transition::Open) {
        // 对于存在 CSD 阴影缓冲区跳变的窗口，若其底层缓冲区在最小化瞬间已发生重置，
        // 绘制底层未重定向表面会透出向下偏移的未补偿画面；因此带有 CSD 偏移的窗口直接跳过底层绘制
        const bool hasCsdJump = (it->csdOffset.x() < -1.0 || it->csdOffset.y() < -1.0);
        if (!hasCsdJump) {
            // Cover the real-surface/offscreen-texture seam at progress zero.
            // This is exactly where minimize begins and restore finishes. Keep a
            // normally painted copy underneath for about 40ms so a late client
            // buffer or first redirected snapshot cannot expose the wallpaper.
            // The redirected copy is still painted below and remains fully opaque;
            // this is not an opacity animation.
            const int duration = it->transition == Transition::Minimize
                ? m_minimizeDuration : m_restoreDuration;
            const qreal seamSpan = std::clamp(40.0 / duration, 0.0, 1.0);
            if (it->timeLine.value() <= seamSpan) {
                WindowPaintData backingData = data;
                effects->drawWindow(renderTarget, viewport, window, mask,
                                    deviceRegion, backingData);
            }
        }
    }

    OffscreenEffect::drawWindow(renderTarget, viewport, window, mask,
                                deviceRegion, data);
}

void DockWindowAnimationEffect::applyDockMorph(
    EffectWindow *window, WindowAnimation &animation,
    WindowQuadList &quads) const
{
    const QRectF geometry = window->frameGeometry();
    const QRectF target = animation.target.geometry;
    const qreal progress = animation.timeLine.value();

    // Cache the source quad bounds: the quad list is stable for a redirected
    // window, so rescanning every vertex each frame is wasted work. The edge
    // quad bounds act as a cheap validity key in case the window resizes
    // mid-animation.
    const QRectF firstBounds = quads.isEmpty()
        ? QRectF() : QRectF(quads.constFirst().bounds());
    const QRectF lastBounds = quads.isEmpty()
        ? QRectF() : QRectF(quads.constLast().bounds());
    if (animation.cachedQuadCount != quads.count()
            || animation.cachedFirstQuadBounds != firstBounds
            || animation.cachedLastQuadBounds != lastBounds) {
        animation.cachedQuadCount = quads.count();
        animation.cachedFirstQuadBounds = firstBounds;
        animation.cachedLastQuadBounds = lastBounds;
        animation.cachedSourceBounds = QRectF();
        for (const WindowQuad &quad : std::as_const(quads))
            animation.cachedSourceBounds = animation.cachedSourceBounds.isNull()
                ? QRectF(quad.bounds())
                : animation.cachedSourceBounds.united(QRectF(quad.bounds()));
    }
    const QRectF sourceBounds = animation.cachedSourceBounds;
    if (sourceBounds.width() <= 0.0 || sourceBounds.height() <= 0.0)
        return;

    const QRectF sourceGeometry(
        geometry.topLeft() + sourceBounds.topLeft(), sourceBounds.size());
    const qreal transformProgress = smootherStep(progress);
    const QSizeF currentSize(
        std::lerp(sourceGeometry.width(), target.width(), transformProgress),
        std::lerp(sourceGeometry.height(), target.height(), transformProgress));
    const QPointF sourceCenter = sourceGeometry.center();
    const QPointF targetCenter = target.center();
    const QPointF currentCenter(
        std::lerp(sourceCenter.x(), targetCenter.x(), transformProgress),
        std::lerp(sourceCenter.y(), targetCenter.y(), transformProgress));
    QRectF current(QPointF(), currentSize);
    current.moveCenter(currentCenter);

    for (WindowQuad &quad : quads) {
        for (int index = 0; index < 4; ++index) {
            const qreal normalizedX = std::clamp(
                (quad[index].x() - sourceBounds.left())
                    / sourceBounds.width(), 0.0, 1.0);
            const qreal normalizedY = std::clamp(
                (quad[index].y() - sourceBounds.top())
                    / sourceBounds.height(), 0.0, 1.0);
            quad[index].setX(current.x() - geometry.x()
                             + current.width() * normalizedX);
            quad[index].setY(current.y() - geometry.y()
                             + current.height() * normalizedY);
        }
    }
}

void DockWindowAnimationEffect::applyBottomGenie(
    EffectWindow *window, WindowAnimation &animation,
    WindowQuadList &quads) const
{
    const QRectF geometry = window->frameGeometry();
    const QRectF icon = animation.target.geometry;
    const qreal timelineProgress = std::clamp(
        animation.timeLine.value(), 0.0, 1.0);
    const qreal motionProgress = std::pow(timelineProgress, 1.65);

    // KWin's redirected window texture can include client decoration or
    // shadow margins. Measure the actual quad bounds before making the grid,
    // so position normalization is identical for CSD Electron windows and
    // standard KDE-decorated windows. The quad list is stable for a
    // redirected window, so the makeGrid(40) subdivision, the source bounds
    // and every progress-independent per-vertex constant are cached on the
    // animation and only rebuilt when the quad count, the edge quad bounds
    // or the icon rect change (e.g. a resize mid-animation or a moved dock).
    const QRectF firstBounds = quads.isEmpty()
        ? QRectF() : QRectF(quads.constFirst().bounds());
    const QRectF lastBounds = quads.isEmpty()
        ? QRectF() : QRectF(quads.constLast().bounds());
    if (animation.cachedQuadCount != quads.count()
            || animation.cachedFirstQuadBounds != firstBounds
            || animation.cachedLastQuadBounds != lastBounds
            || animation.cachedIcon != icon) {
        animation.cachedQuadCount = quads.count();
        animation.cachedFirstQuadBounds = firstBounds;
        animation.cachedLastQuadBounds = lastBounds;
        animation.cachedIcon = icon;
        animation.cachedSourceBounds = QRectF();
        for (const WindowQuad &quad : std::as_const(quads))
            animation.cachedSourceBounds = animation.cachedSourceBounds.isNull()
                ? QRectF(quad.bounds())
                : animation.cachedSourceBounds.united(QRectF(quad.bounds()));
        animation.cachedGrid = quads.makeGrid(40);
        animation.cachedVertices.clear();
        animation.cachedVertices.reserve(
            animation.cachedGrid.count() * 4);
        const QRectF &sourceBounds = animation.cachedSourceBounds;
        if (sourceBounds.width() > 0.0 && sourceBounds.height() > 0.0) {
            for (const WindowQuad &quad : std::as_const(animation.cachedGrid)) {
                for (int index = 0; index < 4; ++index) {
                    WindowAnimation::VertexConstants constants;
                    constants.originalX = quad[index].x();
                    constants.originalY = quad[index].y();
                    // WindowVertex::u/v are texture coordinates, not a reliable
                    // normalized location in the window. Derive mesh coordinates
                    // from positions so shadow/CSD quads and high-DPI textures
                    // cannot clamp whole rows or columns to one edge.
                    const qreal u = std::clamp(
                        (constants.originalX - sourceBounds.left())
                            / sourceBounds.width(), 0.0, 1.0);
                    const qreal v = std::clamp(
                        (constants.originalY - sourceBounds.top())
                            / sourceBounds.height(), 0.0, 1.0);
                    constants.delay = (1.0 - v) * 0.36;
                    constants.phaseDenom = std::max(0.001, 1.0 - constants.delay);
                    const QPointF rounded = roundedRectCoordinate(
                        u, v, icon.size(), 0.30, 0.20);
                    constants.roundedX = rounded.x();
                    constants.roundedY = rounded.y();
                    constants.sinPiV = std::sin(
                        std::numbers::pi_v<qreal> * v);
                    animation.cachedVertices.append(constants);
                }
            }
        }
    }
    const QRectF sourceBounds = animation.cachedSourceBounds;
    if (sourceBounds.width() <= 0.0 || sourceBounds.height() <= 0.0)
        return;

    // Lower rows arrive first while upper rows lag. The endpoint uses a 30%
    // top radius and a 20% bottom radius, both measured from the shorter side.
    quads = animation.cachedGrid;
    qsizetype vertexIndex = 0;
    for (WindowQuad &quad : quads) {
        for (int index = 0; index < 4; ++index, ++vertexIndex) {
            const WindowAnimation::VertexConstants &constants
                = animation.cachedVertices.at(vertexIndex);
            const qreal phase = std::clamp(
                (motionProgress - constants.delay) / constants.phaseDenom,
                0.0, 1.0);
            const qreal verticalProgress = smoothStep(phase);
            const qreal horizontalProgress = 1.0
                - std::pow(1.0 - verticalProgress, 2.05);
            const qreal targetX = icon.x() - geometry.x()
                + icon.width() * constants.roundedX;
            const qreal targetY = icon.y() - geometry.y()
                + icon.height() * constants.roundedY;
            qreal currentX = std::lerp(constants.originalX, targetX,
                                       horizontalProgress);

            // Give the middle of the drop a small outward belly. Scaling each
            // complete row around its moving centre preserves vertex ordering
            // and cannot flip the mesh triangles.
            const qreal rowCenterX = std::lerp(sourceBounds.center().x(),
                icon.center().x() - geometry.x(), horizontalProgress);
            const qreal outwardBulge = 0.12 * std::sin(
                std::numbers::pi_v<qreal> * verticalProgress)
                * constants.sinPiV;
            currentX = rowCenterX
                + (currentX - rowCenterX) * (1.0 + outwardBulge);
            quad[index].setX(currentX);
            quad[index].setY(std::lerp(constants.originalY, targetY,
                                       verticalProgress));
        }
    }
}

void DockWindowAnimationEffect::apply(EffectWindow *window, int mask,
                                       WindowPaintData &data,
                                       WindowQuadList &quads)
{
    Q_UNUSED(mask)
    auto it = m_animations.find(window);
    if (it == m_animations.end())
        return;

    // Compensate a CSD shadow offset only on axes whose complete quad bounds
    // have collapsed to the local origin. WindowQuad ordering is not a
    // geometry contract, so inspect the union rather than quads[0][0].
    if (!quads.isEmpty() && (it->csdOffset.x() < -1.0 || it->csdOffset.y() < -1.0)) {
        QRectF quadBounds;
        bool haveQuadBounds = false;
        for (const WindowQuad &quad : std::as_const(quads)) {
            const QRectF bounds(quad.bounds());
            quadBounds = haveQuadBounds ? quadBounds.united(bounds) : bounds;
            haveQuadBounds = true;
        }
        const QPointF compensation(
            haveQuadBounds && std::abs(quadBounds.left()) < 2.0 ? it->csdOffset.x() : 0.0,
            haveQuadBounds && std::abs(quadBounds.top()) < 2.0 ? it->csdOffset.y() : 0.0);
        if (!qFuzzyIsNull(compensation.x()) || !qFuzzyIsNull(compensation.y())) {
            for (WindowQuad &quad : quads) {
                for (int i = 0; i < 4; ++i) {
                    quad[i].setX(quad[i].x() + compensation.x());
                    quad[i].setY(quad[i].y() + compensation.y());
                }
            }
        }
    }

    // The window remains the only flying texture and simply disappears on
    // the final approach. Restore/open run the same curve in reverse.
    const qreal fadeProgress = smoothStep(
        (it->timeLine.value() - 0.80) / 0.20);
    data.multiplyOpacity(1.0 - fadeProgress);

    // The glass backdrop is anchored to the window's frame and cannot follow
    // the deformation, so it is faded with the animation instead of being left
    // behind: minimizing drops the material while the body is already streaming
    // into the Dock, restoring and opening bring it back during the final
    // approach, where the window itself is about to cover that area.
    const qreal arrived = 1.0 - it->timeLine.value();
    const qreal glassFade = it->transition == Transition::Minimize
        ? 1.0 - smoothStep(it->timeLine.value() / kGlassFadeSpan)
        : smoothStep((arrived - (1.0 - kGlassFadeSpan)) / kGlassFadeSpan);
    window->setData(KosDockAnimationGlassFadeRole, glassFade);

    if (m_morphStyle == MorphStyle::Genie
            && it->transition != Transition::Open)
        applyBottomGenie(window, *it, quads);
    else
        applyDockMorph(window, *it, quads);
}

#ifdef KOS_KWIN_PAINT_TIME_API
void DockWindowAnimationEffect::prePaintScreen(ScreenPrePaintData &data,
                                               std::chrono::milliseconds presentTime)
{
    // Match KWin's Magic Lamp exactly. Minimize/unminimize signals can arrive
    // on a paint-cycle boundary; setting this only after m_animations becomes
    // non-empty leaves that boundary frame with a partial damage region and
    // can expose wallpaper blocks or tearing at animation start/end.
    data.mask |= PAINT_SCREEN_WITH_TRANSFORMED_WINDOWS;
    effects->prePaintScreen(data, presentTime);
}
#else
void DockWindowAnimationEffect::prePaintScreen(ScreenPrePaintData &data)
{
    // Match KWin's Magic Lamp exactly. Minimize/unminimize signals can arrive
    // on a paint-cycle boundary; setting this only after m_animations becomes
    // non-empty leaves that boundary frame with a partial damage region and
    // can expose wallpaper blocks or tearing at animation start/end.
    data.mask |= PAINT_SCREEN_WITH_TRANSFORMED_WINDOWS;
    effects->prePaintScreen(data);
}
#endif

#ifdef KOS_KWIN_PAINT_TIME_API
void DockWindowAnimationEffect::prePaintWindow(RenderView *view,
                                                EffectWindow *window,
                                                WindowPrePaintData &data,
                                                std::chrono::milliseconds presentTime)
{
    auto it = m_animations.find(window);
    if (it != m_animations.end()) {
        it->timeLine.advance(presentTime);
        data.setTransformed();
    }
    effects->prePaintWindow(view, window, data, presentTime);
}
#else
void DockWindowAnimationEffect::prePaintWindow(RenderView *view,
                                                EffectWindow *window,
                                                WindowPrePaintData &data)
{
    auto it = m_animations.find(window);
    if (it != m_animations.end()) {
        it->timeLine.advance(view);
        data.setTransformed();
    }
    effects->prePaintWindow(view, window, data);
}
#endif

void DockWindowAnimationEffect::postPaintScreen()
{
    const auto windows = m_animations.keys();
    for (EffectWindow *window : windows) {
        const auto it = m_animations.constFind(window);
        if (it == m_animations.cend())
            continue;
        // The animation only ever draws inside the union of the window's
        // expanded geometry (frame + shadow margins) and the dock-icon
        // target rect, so repaint that envelope instead of the full screen
        // for every frame of the animation.
        const QRectF targetGeometry = it->target.geometry;
        addAnimationRepaint(window, targetGeometry);
        if (it->timeLine.done()) {
            finishAnimation(window);
            // Repaint the envelope once more after the final frame so the
            // redirected texture cannot remain as a stale compositor image.
            // The target rect was captured above because finishAnimation
            // erases the entry from m_animations.
            addAnimationRepaint(window, targetGeometry);
        }
    }
    effects->postPaintScreen();
}

bool DockWindowAnimationEffect::isActive() const
{
    return !m_animations.isEmpty();
}

void DockWindowAnimationEffect::handleWindowAdded(EffectWindow *window)
{
    watchWindow(window);
    tryStartTicketedOpenAnimation(window, 8);
}

void DockWindowAnimationEffect::watchWindow(EffectWindow *window)
{
    if (!window)
        return;
    connect(window, &EffectWindow::minimizedChanged,
            this, &DockWindowAnimationEffect::handleMinimizedChanged,
            Qt::UniqueConnection);
    // Qt6 中 Lambda 仿函数不支持 Qt::UniqueConnection（会导致断言崩溃），指定上下文 this 已具备安全性
    connect(window, &EffectWindow::windowFrameGeometryChanged,
            this, [this, window]() {
                updateWindowGeometryTracking(window);
            });
    updateWindowGeometryTracking(window);
}

void DockWindowAnimationEffect::updateWindowGeometryTracking(EffectWindow *window)
{
    if (!window || window->isMinimized())
        return;
    const QRectF frame = window->frameGeometry();
    const QRectF buffer = window->bufferGeometry();
    if (frame.isValid() && buffer.isValid() && frame.width() > 1 && frame.height() > 1) {
        const QPointF offset = buffer.topLeft() - frame.topLeft();
        if (offset.x() < -1.0 || offset.y() < -1.0) {
            m_csdOffsets.insert(window, offset);
        } else {
            // Decoration changes and maximization can remove the client shadow.
            // Do not reuse an offset captured for an earlier window geometry.
            m_csdOffsets.remove(window);
        }
    }
}

void DockWindowAnimationEffect::tryStartTicketedOpenAnimation(
    EffectWindow *window, int remainingAttempts)
{
    if (!eligibleWindow(window) || m_animations.contains(window))
        return;

    // Consume only a launch explicitly armed by the Dock. Starting as soon as
    // windowAdded supplies valid geometry redirects the very first paint;
    // waiting for isVisible() was the source of the full-window flash before
    // the old animation jumped back to the Dock.
    const QRectF geometry = window->frameGeometry();
    if (geometry.width() > 1 && geometry.height() > 1) {
        if (const auto target = takePendingLaunchForWindow(window)) {
            startAnimation(window, *target, Transition::Open);
            return;
        }
    }

    if (remainingAttempts <= 0)
        return;

    const QPointer<EffectWindow> guardedWindow(window);
    QTimer::singleShot(40, this, [this, guardedWindow, remainingAttempts]() {
        if (guardedWindow)
            tryStartTicketedOpenAnimation(guardedWindow,
                                          remainingAttempts - 1);
    });
}

void DockWindowAnimationEffect::handleMinimizedChanged(EffectWindow *window)
{
    if (!eligibleWindow(window))
        return;
    if (const auto target = targetForWindow(window)) {
        startAnimation(window, *target, window->isMinimized()
            ? Transition::Minimize : Transition::Restore);
    }
}

void DockWindowAnimationEffect::handleWindowDeleted(EffectWindow *window)
{
    m_csdOffsets.remove(window);
    m_animations.remove(window);
    m_claimedRoles.remove(window);
}

} // namespace KWin
