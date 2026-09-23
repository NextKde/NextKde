#include "../src/ai/AiWorkerClient.h"

#include <QCoreApplication>
#include <QJsonObject>
#include <QTimer>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    KosPlatform::AiWorkerClient client;
    int completed = 0;
    bool failed = false;

    const auto finish = [&](bool ok, const QJsonObject &result,
                            const QString &, const QString &, bool) {
        if (!ok || result.value(QStringLiteral("depthPath")).toString()
                       != QStringLiteral("/test/depth.png")) {
            failed = true;
            app.quit();
            return;
        }
        ++completed;
        if (completed == 1) {
            // Start after the first response has drained. The worker is warm
            // and waiting for input, which is the regression case.
            QTimer::singleShot(100, &app, [&] {
                client.generateDepth(QStringLiteral("second"),
                                     [&](bool secondOk, const QJsonObject &secondResult,
                                         const QString &, const QString &, bool) {
                    failed = !secondOk
                        || secondResult.value(QStringLiteral("depthPath")).toString()
                               != QStringLiteral("/test/depth.png");
                    ++completed;
                    app.quit();
                });
            });
        }
    };

    QTimer::singleShot(5000, &app, [&] {
        failed = true;
        app.quit();
    });
    client.generateDepth(QStringLiteral("first"), finish);
    app.exec();
    return failed || completed != 2 ? 1 : 0;
}
