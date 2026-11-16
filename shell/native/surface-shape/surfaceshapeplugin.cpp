#include "cursoroverride.h"
#include "surfaceshape.h"
#include "startupinputmonitor.h"
#include "windowcontrolslot.h"

#include <QJSEngine>
#include <QQmlEngine>
#include <QQmlExtensionPlugin>
#include <qqml.h>

class SurfaceShapePlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override
    {
        qmlRegisterType<SurfaceShape>(uri, 1, 0, "SurfaceShape");
        qmlRegisterType<StartupInputMonitor>(uri, 1, 0, "StartupInputMonitor");
        qmlRegisterType<WindowControlSlot>(uri, 1, 0, "WindowControlSlot");
        qmlRegisterSingletonType<CursorOverride>(uri, 1, 0, "CursorOverride",
            [](QQmlEngine *, QJSEngine *) -> QObject * {
                return new CursorOverride;
            });
    }
};

#include "surfaceshapeplugin.moc"
