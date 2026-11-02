#include "cooperativecontrols.h"
#include "buttonconfig.h"
#include "wayland-kos-window-controls-v1-server-protocol.h"
#include <wayland/display.h>
#include <wayland/surface.h>
#include <effect/effecthandler.h>
#include <effect/effectwindow.h>
#include <window.h>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <cmath>
#include <cstring>
#include <algorithm>

namespace KOS {
struct CooperativeControls::Entry {
    CooperativeControls *owner = nullptr;
    KWin::SurfaceInterface *surface = nullptr;
    wl_resource *resource = nullptr;
    QRectF pendingRect, rect;
    std::array<QRectF, 3> pendingButtons, buttons;
    bool valid = false;
    qreal pendingDiameter = 14, diameter = 14, pendingGap = 14, gap = 14;
    bool requested = false, active = false, offered = false, sent = false, acknowledged = false;
    uint32_t serial = 0, glyph = 0;
    QMetaObject::Connection committed, destroyed;
};
static const struct kos_window_controls_manager_v1_interface managerImpl{CooperativeControls::get, CooperativeControls::destroyManager};
static const struct kos_window_controls_v1_interface controlsImpl{CooperativeControls::region, CooperativeControls::ack, CooperativeControls::destroy, CooperativeControls::buttons};

CooperativeControls::CooperativeControls(KWin::Display *display,
    std::function<AppConfig(KWin::EffectWindow *)> config, QObject *parent)
    : QObject(parent), m_config(std::move(config)) {
    m_path = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + "/kos/window-appearance.json";
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { refresh(); });
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { refresh(); });
    connect(KWin::effects, &KWin::EffectsHandler::windowAdded, this, [this](KWin::EffectWindow *window) {
        connect(window, &KWin::EffectWindow::windowFullScreenChanged, this, [this] { refresh(); });
        refresh();
    });
    refresh();
    if (display) m_global = wl_global_create(*display, &kos_window_controls_manager_v1_interface, 2, this, bind);
}
CooperativeControls::~CooperativeControls() {
    // Resources belong to clients. Keep late destroy requests valid after unload.
    for (auto *entry : std::as_const(m_entries)) {
        kos_window_controls_v1_send_configure(entry->resource, ++m_serial, 0, entry->glyph);
        disconnect(entry->committed); disconnect(entry->destroyed);
        entry->owner = nullptr; entry->surface = nullptr;
    }
    for (auto *resource : std::as_const(m_managers)) wl_resource_set_user_data(resource, nullptr);
    if (m_global) wl_global_destroy(m_global);
}
void CooperativeControls::watch() {
    for (const auto &file : {m_path, QFileInfo(m_path).path() + "/window-buttons.json"})
        if (QFile::exists(file) && !m_watcher.files().contains(file)) m_watcher.addPath(file);
    for (const auto &directory : {QFileInfo(m_path).path(), QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)})
        if (!m_watcher.directories().contains(directory)) m_watcher.addPath(directory);
}
void CooperativeControls::refresh() {
    watch();
    QFile file(m_path);
    m_enabled = true;
    if (file.exists()) {
        m_enabled = file.open(QIODevice::ReadOnly);
        const auto doc = QJsonDocument::fromJson(file.readAll());
        m_enabled = m_enabled && doc.isObject() && doc.object().value("enabled").toBool(true);
    }
    // Directory notifications also include unrelated settings and temporary
    // files. They are a reason to re-read policy, not to evict every window's
    // renderer state. In particular, legacy CSD overlays need their accepted
    // tint until a replacement sample is ready.
    for (auto *entry : std::as_const(m_entries)) {
        const auto previousSerial = entry->serial;
        offer(entry);
        if (entry->serial != previousSerial) Q_EMIT changed(entry->surface);
    }
}
KWin::EffectWindow *CooperativeControls::windowFor(KWin::SurfaceInterface *surface) const {
    for (auto *window : KWin::effects->stackingOrder())
        if (window->window() && window->window()->surface() == surface) return window;
    return nullptr;
}
void CooperativeControls::offer(Entry *entry) {
    auto *window = windowFor(entry->surface);
    const auto config = window ? m_config(window) : AppConfig{};
    const QRectF rect = entry->pendingRect;
    const bool accepted = m_enabled && entry->requested && entry->valid && window && window->isManaged()
        && (window->isNormalWindow() || window->isDialog()) && !window->isSpecialWindow()
        // showButtons is the legacy overlay policy. Existing self-drawn apps
        // are excluded there; their explicit surface negotiation supersedes it.
        && !window->isFullScreen() && !window->hasDecoration()
        && (rect.isEmpty() || QRectF(QPointF(), window->window()->bufferGeometry().size()).contains(rect));
    const uint32_t glyph = config.glyphMode == GlyphMode::Hover ? 1 : 0;
    if (entry->sent && entry->offered == accepted && entry->glyph == glyph) return;
    entry->sent = true; entry->offered = accepted; entry->glyph = glyph;
    entry->serial = ++m_serial; entry->acknowledged = false;
    kos_window_controls_v1_send_configure(entry->resource, entry->serial, accepted, glyph);
}
void CooperativeControls::commit(Entry *entry) {
    const QRectF oldRect = entry->rect;
    const auto oldButtons = entry->buttons;
    const qreal oldDiameter = entry->diameter, oldGap = entry->gap;
    const bool oldActive = entry->active;
    if (entry->acknowledged) { entry->active = entry->offered; entry->acknowledged = false; }
    // Never allocate/draw from rejected dimensions while waiting for fallback
    // acknowledgement. Keep the last accepted layout until the handoff frame.
    if (entry->offered || !entry->active) {
        entry->rect = entry->pendingRect;
        entry->buttons = entry->pendingButtons;
        entry->diameter = entry->pendingDiameter; entry->gap = entry->pendingGap;
    }
    offer(entry);
    const bool changedGeometry = oldButtons != entry->buttons || oldRect != entry->rect || oldDiameter != entry->diameter
        || oldGap != entry->gap || oldActive != entry->active;
    if (changedGeometry) Q_EMIT changed(entry->surface);
}
bool CooperativeControls::configureWindow(KWin::EffectWindow *window, AppConfig &config) const {
    if (!window->window()) return false;
    const auto *entry = m_entries.value(window->window()->surface());
    if (!entry) return false;
    config.cooperativeControls = entry->active;
    config.showButtons = entry->active && !entry->rect.isEmpty();
    config.nativeGtkControls = false;
    config.chromiumClientControls = false; // Explicit surface ownership supersedes fallback policy.
    config.interceptMargin = 0;
    config.geometry.buttonSize = entry->diameter;
    config.geometry.buttonSpacing = entry->gap;
    const auto offset = window->window()->bufferGeometry().topLeft() - window->frameGeometry().topLeft();
    for (int i = 0; i < 3; ++i)
        config.cooperativeButtons[i] = entry->buttons[i].isEmpty() ? QRectF() : entry->buttons[i].translated(offset);
    config.cooperativeRect = entry->rect.translated(window->window()->bufferGeometry().topLeft() - window->frameGeometry().topLeft());
    return true;
}
void CooperativeControls::bind(wl_client *client, void *data, uint32_t version, uint32_t id) {
    auto *self = static_cast<CooperativeControls *>(data);
    auto *resource = wl_resource_create(client, &kos_window_controls_manager_v1_interface, std::min(version, 2u), id);
    if (!resource) { wl_client_post_no_memory(client); return; }
    self->m_managers.insert(resource);
    wl_resource_set_implementation(resource, &managerImpl, self, managerGone);
}
void CooperativeControls::destroyManager(wl_client *, wl_resource *resource) { wl_resource_destroy(resource); }
void CooperativeControls::managerGone(wl_resource *resource) {
    if (auto *self = static_cast<CooperativeControls *>(wl_resource_get_user_data(resource))) self->m_managers.remove(resource);
}
void CooperativeControls::get(wl_client *client, wl_resource *manager, uint32_t id, wl_resource *surfaceResource) {
    auto *self = static_cast<CooperativeControls *>(wl_resource_get_user_data(manager));
    auto *surface = KWin::SurfaceInterface::get(surfaceResource);
    auto *entry = new Entry;
    entry->resource = wl_resource_create(client, &kos_window_controls_v1_interface, wl_resource_get_version(manager), id);
    if (!entry->resource) { delete entry; wl_client_post_no_memory(client); return; }
    wl_resource_set_implementation(entry->resource, &controlsImpl, entry, gone);
    if (!self || !surface || self->m_entries.contains(surface)) {
        kos_window_controls_v1_send_configure(entry->resource, 0, 0, 0); return;
    }
    entry->owner = self; entry->surface = surface;
    self->m_entries.insert(surface, entry);
    entry->committed = connect(surface, &KWin::SurfaceInterface::committed, self, [self, entry] { self->commit(entry); });
    entry->destroyed = connect(surface, &QObject::destroyed, self, [self, entry] {
        self->remove(entry); entry->owner = nullptr; entry->surface = nullptr;
    });
    self->offer(entry);
    Q_EMIT self->changed(surface);
}
void CooperativeControls::region(wl_client *, wl_resource *resource, wl_fixed_t x, wl_fixed_t y, wl_fixed_t width, wl_fixed_t height, wl_fixed_t diameter, wl_fixed_t gap, uint32_t enabled) {
    auto *entry = static_cast<Entry *>(wl_resource_get_user_data(resource));
    if (!entry->owner) return;
    entry->pendingRect = QRectF(wl_fixed_to_double(x), wl_fixed_to_double(y), wl_fixed_to_double(width), wl_fixed_to_double(height));
    entry->pendingDiameter = wl_fixed_to_double(diameter); entry->pendingGap = wl_fixed_to_double(gap);
    const auto rect = entry->pendingRect;
    const auto d = entry->pendingDiameter, g = entry->pendingGap;
    entry->valid = rect.x() >= 0 && rect.y() >= 0 && rect.width() <= 1024 && rect.height() <= 256
        && d >= 6 && d <= 40 && g >= 0 && g <= 80 && rect.width() >= 3*d+2*g && rect.height() >= d;
    for (int i = 0; i < 3; ++i)
        entry->pendingButtons[i] = QRectF(rect.x() + (rect.width()-3*d-2*g)/2 + i*(d+g), rect.y()+(rect.height()-d)/2, d, d);
    entry->requested = enabled == 1;
    entry->owner->offer(entry);
}
void CooperativeControls::buttons(wl_client *, wl_resource *resource, wl_array *data, uint32_t enabled) {
    auto *entry = static_cast<Entry *>(wl_resource_get_user_data(resource));
    if (!entry->owner) return;
    entry->pendingButtons = {};
    entry->pendingRect = {};
    entry->valid = data->size <= 60 && data->size % 20 == 0;
    for (size_t offset = 0; entry->valid && offset < data->size; offset += 20) {
        int32_t words[5];
        std::memcpy(words, static_cast<const char *>(data->data) + offset, sizeof(words));
        const int action = words[0];
        const QRectF rect(wl_fixed_to_double(words[1]), wl_fixed_to_double(words[2]),
                          wl_fixed_to_double(words[3]), wl_fixed_to_double(words[4]));
        entry->valid = action >= 0 && action < 3 && entry->pendingButtons[action].isEmpty()
            && rect.x() >= 0 && rect.y() >= 0 && rect.width() >= 6 && rect.width() <= 40
            && rect.width() == rect.height();
        for (const auto &previous : entry->pendingButtons)
            entry->valid = entry->valid && !previous.intersects(rect);
        if (!entry->valid) break;
        entry->pendingButtons[action] = rect;
        entry->pendingRect = entry->pendingRect.isEmpty() ? rect : entry->pendingRect.united(rect);
    }
    // Bound texture/damage regions even when buttons are placed far apart.
    entry->valid = entry->valid && entry->pendingRect.width() <= 4096 && entry->pendingRect.height() <= 4096;
    entry->requested = enabled == 1;
    entry->owner->offer(entry);
}
void CooperativeControls::ack(wl_client *, wl_resource *resource, uint32_t serial) {
    auto *entry = static_cast<Entry *>(wl_resource_get_user_data(resource));
    if (entry->owner && entry->serial == serial) entry->acknowledged = true;
}
void CooperativeControls::destroy(wl_client *, wl_resource *resource) { wl_resource_destroy(resource); }
void CooperativeControls::remove(Entry *entry) {
    m_entries.remove(entry->surface);
    disconnect(entry->committed); disconnect(entry->destroyed);
    Q_EMIT changed(entry->surface);
}
void CooperativeControls::gone(wl_resource *resource) {
    auto *entry = static_cast<Entry *>(wl_resource_get_user_data(resource));
    if (entry->owner) entry->owner->remove(entry);
    delete entry;
}
}
