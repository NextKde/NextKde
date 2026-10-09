// Live, read-only acceptance of the artist photo pipeline. Reports metadata
// and decoded dimensions only; no web tokens or media URLs enter the report.
#include "online/apple_dynamic_artwork_provider.h"

#include <QCoreApplication>
#include <QFile>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTimer>

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    bool abandonedCallback = false;
    auto* abandoned = new listenfree::online::AppleDynamicArtworkProvider;
    abandoned->fetchArtist("Taylor Swift", [&](const QVariantMap&) { abandonedCallback = true; });
    delete abandoned; // Cancels token/network jobs before their replies arrive.
    listenfree::online::AppleDynamicArtworkProvider provider;
    QNetworkAccessManager network;
    const QStringList names{QStringLiteral("周杰伦"), QStringLiteral("Taylor Swift"),
                            QStringLiteral("周杰倫"), QStringLiteral("ListenFreeNonexistentArtistF73D12")};
    QJsonArray results;
    int remaining = names.size();
    bool passed = true;
    const auto complete = [&](const QJsonObject& row, bool okay) {
        results.append(row); passed = passed && okay;
        if (--remaining) return;
        passed = passed && !abandonedCallback;
        const QJsonObject report{{"passed", passed}, {"destroyedProviderDidNotCallback", !abandonedCallback},
                                 {"results", results}};
        const auto bytes = QJsonDocument(report).toJson();
        QFile output;
        output.open(stdout, QIODevice::WriteOnly); output.write(bytes); output.flush();
        app.exit(passed ? 0 : 1);
    };
    for (const auto& name : names) provider.fetchArtist(name, [&, name](const QVariantMap& result) {
        QJsonObject row{{"query", name}, {"source", result.value("source").toString()},
                        {"hasHero", !result.value("hero").toString().isEmpty()},
                        {"hasSignature", !result.value("signature").toString().isEmpty()}};
        const bool missing = name.startsWith("ListenFreeNonexistent");
        if (missing || result.value("hero").toString().isEmpty()) {
            row["passed"] = missing && result.isEmpty(); complete(row, row["passed"].toBool()); return;
        }
        QNetworkRequest request{QUrl(result.value("hero").toString())};
        request.setTransferTimeout(12000);
        request.setRawHeader("user-agent", "ListenFree/0.2 (https://github.com/Tabris-Ayanami/ListenFree-desktop; artist artwork)");
        auto* reply = network.get(request);
        QObject::connect(reply, &QNetworkReply::finished, &app, [&, reply, row]() mutable {
            const auto image = QImage::fromData(reply->readAll());
            const bool okay = reply->error() == QNetworkReply::NoError && !image.isNull();
            row["width"] = image.width(); row["height"] = image.height(); row["passed"] = okay;
            reply->deleteLater(); complete(row, okay);
        });
    });
    QTimer::singleShot(40000, &app, [&] { app.exit(2); });
    return app.exec();
}
