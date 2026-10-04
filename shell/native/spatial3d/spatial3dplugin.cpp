#include "depthmeshgeometry.h"

#include <QQmlExtensionPlugin>
#include <qqml.h>

class Spatial3DPlugin final : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char *uri) override
    {
        qmlRegisterType<DepthMeshGeometry>(uri, 1, 0, "DepthMeshGeometry");
    }
};

#include "spatial3dplugin.moc"
