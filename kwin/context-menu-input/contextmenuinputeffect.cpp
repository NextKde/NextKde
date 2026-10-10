#include "contextmenuinputeffect.h"

#include <input.h>
#include <effect/effecthandler.h>
#include <input_event.h>
#include <input_event_spy.h>
#include <keyboard_input.h>
#include <window.h>
#include <workspace.h>
#include <virtualdesktops.h>
#include <wayland_server.h>
#include <wayland/seat.h>
#include <wayland/surface.h>
#include <wayland/textinput_v2.h>
#include <wayland/textinput_v3.h>
#include <xkb.h>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDateTime>
#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>

#include <chrono>
#include <optional>
#include <cmath>

#include <xkbcommon/xkbcommon-keysyms.h>

namespace KWin
{

// The current-desktop overload changed after KWin 6.6. Keep the check
// dependent on Handler so the unavailable overload is discarded at compile time.
template<typename Handler>
static auto placementAreaAt(Handler *handler, const QPoint &point)
{
    if constexpr (requires { handler->clientArea(PlacementArea, point); }) {
        return handler->clientArea(PlacementArea, point);
    } else {
        auto *manager = VirtualDesktopManager::self();
        return handler->clientArea(PlacementArea, handler->screenAt(point),
                                   manager ? manager->currentDesktop() : nullptr);
    }
}

// InputEventSpy runs before KWin's input filters, observes every pointer
// button change, and has no return value with which it could consume input.
class ContextMenuPointerSpy final : public InputEventSpy
{
public:
    explicit ContextMenuPointerSpy(ContextMenuInputEffect *effect)
        : m_effect(effect)
    {
    }

    void pointerButton(PointerButtonEvent *event) override
    {
        if (event && event->state == PointerButtonState::Pressed)
            m_effect->handlePointerPress(event->position, event->button);
    }

private:
    ContextMenuInputEffect *m_effect;
};

ContextMenuInputEffect::ContextMenuInputEffect()
{
    QDBusConnection::sessionBus().registerObject(
        QStringLiteral("/KOSContextMenuInput"), this,
        // 只导出 Q_SCRIPTABLE 业务槽：ExportAllSlots 连 deleteLater 一起导
        // 给会话总线（任意进程可打死特效，见头注释）
        QDBusConnection::ExportScriptableSlots);
    m_pointerSpy = std::make_unique<ContextMenuPointerSpy>(this);
    installPointerSpy();
}

ContextMenuInputEffect::~ContextMenuInputEffect()
{
    QDBusConnection::sessionBus().unregisterObject(QStringLiteral("/KOSContextMenuInput"));
}

QVariantMap ContextMenuInputEffect::activeApplicationMenu() const
{
    Window *window = Workspace::self() ? Workspace::self()->activeWindow() : nullptr;
    if (!window || !window->hasApplicationMenu())
        return {{QStringLiteral("available"), false}};

    const QString service = window->applicationMenuServiceName();
    const QString path = window->applicationMenuObjectPath();
    return {{QStringLiteral("available"), !service.isEmpty() && !path.isEmpty()},
            {QStringLiteral("service"), service},
            {QStringLiteral("path"), path}};
}

QVariantMap ContextMenuInputEffect::clipboardAnchor(const QString &expectedWindowId) const
{
    if (!effects || !Workspace::self())
        return {{QStringLiteral("available"), false}};

    const QPointF pointer = effects->cursorPos();
    QRectF anchor(pointer, QSizeF(0, 0));
    QString source = QStringLiteral("pointer");
    Window *target = Workspace::self()->activeWindow();
    SeatInterface *seat = waylandServer() ? waylandServer()->seat() : nullptr;
    const QUuid expected(expectedWindowId);
    // An enabled text-input can outlive a focus transition. Require all three
    // identities to agree, and never use the search panel's own input field.
    if (!expected.isNull() && target && target->internalId() == expected
        && target->surface() && seat
        && seat->focusedKeyboardSurface() == target->surface()
        && seat->focusedTextInputSurface() == target->surface()) {
        const auto useCaret = [&](auto *textInput) {
            if (!textInput || !textInput->isEnabled() || textInput->surface() != target->surface())
                return false;
            const auto local = textInput->cursorRectangle();
            // Zero-width carets are valid; an absent/default 0x0 rectangle is
            // not. Reject off-surface positions left behind by scrolled fields.
            if (!std::isfinite(local.x()) || !std::isfinite(local.y())
                || !std::isfinite(local.width()) || !std::isfinite(local.height())
                || local.width() < 0 || local.height() <= 0)
                return false;
            const QPointF topLeft = target->mapFromLocal(local.topLeft());
            const QPointF bottomRight = target->mapFromLocal(local.bottomRight());
            const QRectF global(topLeft, bottomRight);
            if (!target->frameGeometry().contains(global.center()))
                return false;
            anchor = global;
            source = QStringLiteral("caret");
            return true;
        };
        if (!useCaret(seat->textInputV3()))
            useCaret(seat->textInputV2());
    }
    // PlacementArea excludes reserved panels and is evaluated for the output
    // containing the chosen anchor on the current desktop.
    const auto area = placementAreaAt(effects, anchor.center().toPoint());
    return {{QStringLiteral("available"), true},
            {QStringLiteral("source"), source},
            {QStringLiteral("x"), anchor.x()}, {QStringLiteral("y"), anchor.y()},
            {QStringLiteral("width"), anchor.width()}, {QStringLiteral("height"), anchor.height()},
            {QStringLiteral("areaX"), area.x()}, {QStringLiteral("areaY"), area.y()},
            {QStringLiteral("areaWidth"), area.width()}, {QStringLiteral("areaHeight"), area.height()}};
}

bool ContextMenuInputEffect::paste(const QString &expectedWindowId)
{
    InputRedirection *redirection = input();
    KeyboardInputRedirection *keyboard = redirection ? redirection->keyboard() : nullptr;
    Xkb *xkb = keyboard ? keyboard->xkb() : nullptr;
    Window *target = Workspace::self() ? Workspace::self()->activeWindow() : nullptr;
    SeatInterface *seat = waylandServer() ? waylandServer()->seat() : nullptr;
    // Keyboard focus, rather than activeWindow(), also excludes an intervening
    // layer surface, popup or lock screen. No event loop runs before injection.
    const QUuid expected(expectedWindowId);
    if (expected.isNull() || !target || target->internalId() != expected
            || !target->surface() || !seat
            || seat->focusedKeyboardSurface() != target->surface())
        return false;
    if (!xkb) {
        qWarning() << "KOS paste: keyboard state unavailable; skipping injection";
        return false;
    }

    // Resolve the keycodes on the layout that is active right now. Going
    // through xkb keeps the injected chord identical to a physical press on
    // non-Latin layouts, where the V keysym does not sit where a hardcoded
    // keycode would put it.
    const std::optional<Xkb::KeyCode> control =
        xkb->keycodeFromKeysym(XKB_KEY_Control_L);
    const std::optional<Xkb::KeyCode> letterV = xkb->keycodeFromKeysym(XKB_KEY_v);
    if (!control || !letterV) {
        qWarning() << "KOS paste: Ctrl+V is not reachable on the active layout";
        return false;
    }

    // KWin stamps real input with the monotonic clock. Reusing it keeps key
    // repeat and shortcut handling looking at a plausible sequence instead of
    // an event from before the session started.
    const auto now = std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch());

    keyboard->processKey(control->keyCode, KeyboardKeyState::Pressed, now);
    keyboard->processKey(letterV->keyCode, KeyboardKeyState::Pressed, now);
    keyboard->processKey(letterV->keyCode, KeyboardKeyState::Released, now);
    keyboard->processKey(control->keyCode, KeyboardKeyState::Released, now);
    return true;
}

void ContextMenuInputEffect::installPointerSpy()
{
    if (m_pointerSpyInstalled)
        return;

    if (auto *inputRedirection = input()) {
        inputRedirection->installInputEventSpy(m_pointerSpy.get());
        m_pointerSpyInstalled = true;
        return;
    }

    // Effects may be constructed before KWin finishes bringing up input on a
    // compositor restart. Retry on its event loop instead of silently ending
    // up with a permanently inactive effect.
    QTimer::singleShot(100, this, &ContextMenuInputEffect::installPointerSpy);
}

void ContextMenuInputEffect::handlePointerPress(const QPointF &position,
                                                Qt::MouseButton button)
{
    // KWin owns the authoritative surface hit-test. PopupWindow's QML x/y are
    // anchor-local and cannot be compared to compositor-global coordinates.
    // A press delivered to any popup is therefore already an internal menu
    // interaction, not an outside press that should dismiss our menu.
    if (auto *target = input() ? input()->findToplevel(position) : nullptr;
        target && target->isPopupWindow()) {
        return;
    }

    const QJsonObject eventData{
        {QStringLiteral("type"), QStringLiteral("global-pointer-press")},
        {QStringLiteral("x"), position.x()},
        {QStringLiteral("y"), position.y()},
        {QStringLiteral("button"), static_cast<int>(button)},
        {QStringLiteral("timestamp"), QDateTime::currentMSecsSinceEpoch()},
    };
    publish(eventData);
}

void ContextMenuInputEffect::publish(const QJsonObject &eventData)
{
    const QString payload = QString::fromUtf8(QJsonDocument(eventData).toJson(
        QJsonDocument::Compact));

    // The platform daemon owns this local session-bus endpoint. send() is a
    // no-reply, non-blocking D-Bus delivery and therefore cannot stall KWin's
    // input thread when Quickshell is restarting.
    QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("org.kos.Platform"),
        QStringLiteral("/Platform"),
        QStringLiteral("org.kos.Platform"),
        QStringLiteral("Publish"));
    message.setArguments({payload});
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (bus.isConnected())
        bus.send(message);
}

} // namespace KWin
