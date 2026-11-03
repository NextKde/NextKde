#pragma once
#include <QObject>
#include <QHash>
#include <QSet>
#include <QRectF>
#include <QFileSystemWatcher>
#include <functional>
#include <wayland-server-core.h>

namespace KWin { class Display; class SurfaceInterface; class EffectWindow; }
namespace KOS {
struct AppConfig;
class CooperativeControls : public QObject {
    Q_OBJECT
public:
    struct Entry;
    explicit CooperativeControls(KWin::Display *, std::function<AppConfig(KWin::EffectWindow *)>, QObject *parent);
    ~CooperativeControls() override;
    // True means this client owns placement, even when drawing its own fallback.
    bool configureWindow(KWin::EffectWindow *, AppConfig &) const;
    void refresh();
Q_SIGNALS:
    void changed(KWin::SurfaceInterface *surface);
public: // Wayland dispatch entry points
    static void bind(wl_client *, void *, uint32_t, uint32_t);
    static void get(wl_client *, wl_resource *, uint32_t, wl_resource *);
    static void destroyManager(wl_client *, wl_resource *);
    static void managerGone(wl_resource *);
    static void region(wl_client *, wl_resource *, wl_fixed_t, wl_fixed_t, wl_fixed_t, wl_fixed_t, wl_fixed_t, wl_fixed_t, uint32_t);
    static void buttons(wl_client *, wl_resource *, wl_array *, uint32_t);
    static void ack(wl_client *, wl_resource *, uint32_t);
    static void destroy(wl_client *, wl_resource *);
    static void gone(wl_resource *);
private:
    void offer(Entry *);
    void commit(Entry *);
    void remove(Entry *);
    void watch();
    KWin::EffectWindow *windowFor(KWin::SurfaceInterface *) const;
    wl_global *m_global = nullptr;
    QHash<KWin::SurfaceInterface *, Entry *> m_entries;
    QSet<wl_resource *> m_managers;
    std::function<AppConfig(KWin::EffectWindow *)> m_config;
    QFileSystemWatcher m_watcher;
    QString m_path;
    bool m_enabled = true;
    uint32_t m_serial = 0;
};
}
