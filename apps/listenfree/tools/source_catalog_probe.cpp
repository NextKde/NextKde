// Read-only sample capture using the exact production catalog and LX adapter.
#include "online/platform_catalog.h"
#include <QCoreApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QTimer>

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    if (app.arguments().size() < 2) return 2;
    QNetworkAccessManager network;
    QJsonObject samples, errors;
    int remaining = 5;
    const QString query = app.arguments().value(2, QStringLiteral("陈奕迅 孤勇者"));
    for (const auto& platform : QStringList{"wy", "kw", "tx", "kg", "mg"}) {
        auto* reply = listenfree::online::platformRequest(network, platform, "search", query, {}, 1, 30);
        QObject::connect(reply, &QNetworkReply::finished, &app, [&, reply, platform] {
            const auto rows = listenfree::online::platformSearchRows(platform, "songs",
                listenfree::online::platformJson(reply->readAll()));
            if (rows.isEmpty()) {
                errors.insert(platform, QJsonObject{{"status", reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt()},
                                                    {"error", reply->error() == QNetworkReply::NoError ? "empty-results" : "network-error"}});
            } else {
                const auto info = listenfree::online::sourceMusicInfo(rows.first().toMap());
                samples.insert(platform, QJsonObject::fromVariantMap(info));
            }
            reply->deleteLater();
            if (--remaining == 0) app.quit();
        });
    }
    QTimer::singleShot(22000, &app, &QCoreApplication::quit);
    app.exec();
    QFile output(app.arguments().at(1));
    if (!output.open(QIODevice::WriteOnly)) return 3;
    output.write(QJsonDocument(samples).toJson());
    output.close();
    QFile diagnostics(app.arguments().at(1)+".errors.json");
    if (diagnostics.open(QIODevice::WriteOnly)) diagnostics.write(QJsonDocument(errors).toJson());
    return samples.size() == 5 ? 0 : 1;
}
