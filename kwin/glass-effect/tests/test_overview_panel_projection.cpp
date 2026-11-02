#include "../src/overviewpanelprojection.h"
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <memory>
#include <stdexcept>

static void check(bool condition, const char *message)
{
    if (!condition) throw std::runtime_error(message);
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QQmlEngine engine;
    // Real Overview's delegates bind positions to the output/window and opacity
    // to overviewVal, not to their visual parent. Keep that binding independent
    // from the fixture's structural parent before changing visual ancestry.
    QQmlComponent binding(&engine);
    binding.setData(R"(
        import QtQuick
        Item {
            id: root
            property real progress: 0
            Item { objectName: "panel"; opacity: 1 - root.progress }
        }
    )", QUrl());
    std::unique_ptr<QObject> object(binding.create());
    check(bool(object), "bound panel fixture must load");
    auto *parent = qobject_cast<QQuickItem *>(object.get());
    auto *panel = parent->findChild<QQuickItem *>(QStringLiteral("panel"));
    check(panel && panel->opacity() == 1, "panel starts at its native opacity");
    KWin::OverviewPanelProjection projection;
    projection.project(panel);
    projection.project(panel);
    check(panel->parentItem() != parent && panel->parentItem()->opacity() == 0,
          "redundant native thumbnail must remain absent");
    parent->setProperty("progress", 0.5);
    check(panel->opacity() == 0.5 && panel->parentItem()->opacity() == 0,
          "native animation binding must remain live without exposing a duplicate");
    projection.restore();
    check(panel->parentItem() == parent && panel->opacity() == 0.5,
          "exit must restore visual ancestry without changing native opacity");
    parent->setProperty("progress", 0.75);
    check(panel->opacity() == 0.25, "exit must preserve the native QML binding");
    projection.project(panel);
    object.reset();
    projection.restore(); // Scene teardown before Overview exit must be safe.
    QQuickItem liveParent, livePanel(&liveParent);
    {
        KWin::OverviewPanelProjection unloading;
        unloading.project(&livePanel);
    }
    check(livePanel.parentItem() == &liveParent, "effect teardown must restore a live delegate");
}
