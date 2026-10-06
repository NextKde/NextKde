#include "cursoroverride.h"
#include "surfaceshape.h"

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
        qmlRegisterSingletonType<CursorOverride>(uri, 1, 0, "CursorOverride",
            [](QQmlEngine *, QJSEngine *) -> QObject * {
                return new CursorOverride;
            });
    }
};

#include "surfaceshapeplugin.moc"
