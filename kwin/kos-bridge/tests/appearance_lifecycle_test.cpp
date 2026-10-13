#include "windowappearance/windowappearance.h"

#include <scene/item.h>
#include <scene/outlinedborderitem.h>
#include <QGuiApplication>
#include <cstdlib>
#include <iostream>

namespace KOS
{
class WindowAppearanceLifecycleTest
{
    static void require(bool condition, const char *message)
    {
        if (!condition) {
            std::cerr << message << '\n';
            std::exit(1);
        }
    }

public:
    static void run()
    {
        WindowAppearanceManager manager;
        auto *parent = new KWin::Item;
        auto *bounds = new KWin::Item(parent);
        bounds->setParent(parent);
        bounds->setGeometry(KWin::RectF(-10, -10, 100, 100));
        auto *shadow = new WindowAppearance::SceneShadowItem(parent);
        auto *outline = new KWin::OutlinedBorderItem(KWin::RectF(), KWin::BorderOutline(), parent);
        outline->setParent(parent);
        auto *frame = new KWin::OutlinedBorderItem(KWin::RectF(), KWin::BorderOutline(), parent);
        frame->setParent(parent);
        QPointer<KWin::Item> boundsGuard(bounds);
        QPointer<QObject> shadowGuard(shadow), outlineGuard(outline), frameGuard(frame);
        // forget deliberately does not dereference the already-deleted window.
        // nullptr is sufficient as a tracking key in this teardown fixture.
        auto &state = manager.m_windows[nullptr];
        state.continuousBounds = bounds;
        state.sceneShadow = shadow;
        state.outline = outline;
        state.frame = frame;
        int callbacks = 0;
        state.connections.append(QObject::connect(parent, &KWin::Item::boundingRectChanged,
            &manager, [&] { ++callbacks; }));
        int sceneChanges = 0;
        QObject::connect(parent, &KWin::Item::boundingRectChanged,
            &manager, [&] { ++sceneChanges; });
        manager.m_animTimer.start();
        manager.m_tierTimer.start();
        manager.forget(nullptr);
        require(manager.m_windows.isEmpty(), "deleted-window tracking retained");
        require(boundsGuard && shadowGuard && outlineGuard && frameGuard,
            "forget destroyed parent-owned scene nodes");
        require(sceneChanges == 0, "forget synchronously changed expanded geometry");
        require(!manager.m_animTimer.isActive() && !manager.m_tierTimer.isActive(),
            "timers retained after final deleted window");
        bounds->setGeometry(KWin::RectF(-20, -20, 120, 120));
        require(sceneChanges > 0 && callbacks == 0, "forgotten state connections remain live");
        delete parent;
        require(!boundsGuard && !shadowGuard && !outlineGuard && !frameGuard,
            "window scene parent did not reclaim bridge nodes");

        // Live restoration must still remove scene additions. Its synchronous
        // geometry callback re-enters both restoreAll and forget.
        KWin::Item liveParent;
        auto *liveBounds = new KWin::Item(&liveParent);
        liveBounds->setParent(&liveParent);
        liveBounds->setGeometry(KWin::RectF(-10, -10, 100, 100));
        QPointer<KWin::Item> liveGuard(liveBounds);
        manager.m_windows[nullptr].continuousBounds = liveBounds;
        bool reentered = false;
        QObject::connect(&liveParent, &KWin::Item::boundingRectChanged, &manager, [&] {
            reentered = true;
            require(manager.m_restoring, "restoration gate not active");
            require(manager.m_windows.isEmpty(), "state still in hash during restoration");
            manager.forget(nullptr);
            manager.restoreAll();
            manager.prepare(nullptr);
        });
        manager.restoreAll();
        require(reentered && !liveGuard, "live restore did not remove scene node");
        require(manager.m_windows.isEmpty() && !manager.m_restoring,
            "live restoration left tracking or gate active");
        manager.restoreAll();
        std::cout << "appearance lifecycle: deleted-window ownership, disconnected callbacks, "
                     "timer shutdown, live restore and synchronous re-entry passed\n";
    }
};
}

int main(int argc, char **argv)
{
    QGuiApplication application(argc, argv);
    KOS::WindowAppearanceLifecycleTest::run();
}
