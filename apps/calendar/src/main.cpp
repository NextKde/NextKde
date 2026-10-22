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
        // N01 review hook: KOS_CALENDAR_REVIEW_SELECT="YYYY-MM-DD" pins the
        // initial selected date to a non-today day, so the gray "other
        // selection" state is on-screen alongside the red today disc during
        // screenshot rounds without pointer injection. Unset (the default)
        // keeps selecting today.
        [](QQmlEngine &engine, QVariantMap &) {
            const QString reviewNow = qEnvironmentVariable("KOS_CALENDAR_REVIEW_NOW");
            if (!reviewNow.isEmpty())
                engine.rootContext()->setContextProperty(
                    QStringLiteral("KosReviewNow"), reviewNow);
            const QString reviewSelect = qEnvironmentVariable("KOS_CALENDAR_REVIEW_SELECT");
            if (!reviewSelect.isEmpty())
                engine.rootContext()->setContextProperty(
                    QStringLiteral("KosReviewSelect"), reviewSelect);
        },
    });
}
