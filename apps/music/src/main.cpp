#include "KosApp/ApplicationRunner.h"
#include "MusicController.h"

int main(int argc, char *argv[])
{
    return Kos::App::run(argc, argv, {
        QStringLiteral("kos-music"),
        QStringLiteral("KOS Music"),
        QStringLiteral("kos-music"),
        QStringLiteral("org.nextkde.Kos.Music"),
        QStringLiteral("Kos.Apps.Music"),
        QStringLiteral(KOS_APP_VERSION),
        [](QQmlEngine &, QVariantMap &initialProperties) {
            // The controller owns playback, the database connection, the queue,
            // and the MPRIS registration. Creating it here and handing it to
            // QML as an initial property keeps it outside the QML tree: a
            // --watch-qml reload rebuilds the window without stopping whatever
            // is playing. QML reaches it through the root's `music` property.
            initialProperties.insert(QStringLiteral("music"),
                                     QVariant::fromValue(
                                         static_cast<QObject *>(new MusicController)));
        },
    });
}
