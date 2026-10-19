#include "networkview.h"
#include <QQmlExtensionPlugin>
#include <qqml.h>
#include <QSurfaceFormat>

class FormaNetworkPlugin final : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
    void registerTypes(const char *uri) override {
        // Forma's instanced SDF shader needs gl_VertexID and flat varyings.
        // Request a desktop GL context before QML creates its popup windows;
        // this does not select a backend or affect Vulkan rendering.
        auto format = QSurfaceFormat::defaultFormat();
        format.setVersion(3, 3);
        format.setProfile(QSurfaceFormat::CoreProfile);
        format.setRenderableType(QSurfaceFormat::OpenGL);
        QSurfaceFormat::setDefaultFormat(format);
        qmlRegisterType<NetworkView>(uri, 1, 0, "NetworkTrafficView");
    }
};
#include "plugin.moc"
