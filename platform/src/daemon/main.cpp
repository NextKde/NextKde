#include "PlatformServer.h"
#include "../kwin/KWinBridge.h"

#include <QGuiApplication>
#include <QLoggingCategory>
#include <QTextStream>

using namespace KosPlatform;

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    // The desktop file basename is the KGlobalAccel component identity: all
    // shell shortcuts register under this ONE component in the Shortcuts KCM.
    app.setApplicationName(QStringLiteral("kos-platform"));
    app.setDesktopFileName(QStringLiteral("org.kos.Platform"));

    const QStringList arguments = app.arguments();
    if (arguments.size() > 1 && arguments.at(1) != QStringLiteral("daemon")) {
        QTextStream(stderr) << "Usage: kos-platform daemon\n";
        return 2;
    }

    PlatformServer server;
    if (!server.listen())
        return 1;

    startKWinBridge([&server](const QJsonObject &event) {
        server.broadcastKWinEvent(event);
    });

    QTextStream(stdout) << "READY " << server.socketPath() << Qt::endl;
    return app.exec();
}
