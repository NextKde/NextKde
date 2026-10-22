#include "KosApp/ApplicationRunner.h"

#include <QGuiApplication>
#include <QQmlContext>
#include <QQmlEngine>

int main(int argc, char *argv[])
{
    return Kos::App::run(argc, argv, {
        QStringLiteral("kos-calendar"),
        QStringLiteral("KOS Calendar"),
        QStringLiteral("kos-calendar"),
        QStringLiteral("org.nextkde.Kos.Calendar"),
        QStringLiteral("Kos.Apps.Calendar"),
        QStringLiteral(KOS_APP_VERSION),
        // N02 review hook: KOS_CALENDAR_REVIEW_NOW="HH:MM" pins the clock the
        // now-line/today markers show, so the line sits on-screen during
        // screenshot rounds. Unset (the default) keeps real time.
        [](QQmlEngine &engine, QVariantMap &) {
            const QString reviewNow = qEnvironmentVariable("KOS_CALENDAR_REVIEW_NOW");
            if (!reviewNow.isEmpty())
                engine.rootContext()->setContextProperty(
                    QStringLiteral("KosReviewNow"), reviewNow);
        },
    });
}
