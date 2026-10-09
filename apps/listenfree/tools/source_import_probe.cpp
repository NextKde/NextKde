// Exercise the actual Qt import service with an isolated data directory.
#include "qmlbridge/source_controller.h"
#include <QCoreApplication>
#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTimer>

int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    if (app.arguments().size() != 4) return 2;
    QFile input(app.arguments().at(1));
    if (!input.open(QIODevice::ReadOnly)) return 3;
    const auto urls = QJsonDocument::fromJson(input.readAll()).array();
    const auto root = QFileInfo(app.arguments().at(2)).absoluteFilePath();
    app.setProperty("listenfreeDataDir", root);
    listenfree::qmlbridge::SourceController source;
    QJsonArray reports;
    for (const auto& value : urls) {
        const QUrl url(value.toString());
        QJsonObject report{{"endpoint", url.host()+url.path()}};
        if (url.query().contains(QStringLiteral("卡密"))) {
            report.insert("result", "requires-user-key");
        } else {
            QEventLoop loop;
            QTimer timeout;
            timeout.setSingleShot(true);
            QObject::connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);
            auto connection = QObject::connect(&source, &listenfree::qmlbridge::SourceController::busyChanged,
                &loop, [&] { if (!source.busy()) QTimer::singleShot(0, &loop, &QEventLoop::quit); });
            const bool accepted = source.importUrl(url);
            if (accepted) { timeout.start(20000); loop.exec(); }
            QObject::disconnect(connection);
            if (accepted && !source.busy() && source.lastError().isEmpty()) {
                for (const auto& row : source.sources()) {
                    const auto map = row.toMap();
                    if (map.value("id") != source.activeId()) continue;
                    const auto path = map.value("path").toString();
                    QFile script(path);
                    if (script.open(QIODevice::ReadOnly)) {
                        const auto data = script.readAll().trimmed().toLower();
                        report.insert("result", data.startsWith("<!doctype") || data.startsWith("<html")
                            ? "invalid-script-download" : "downloaded");
                        report.insert("file", QFileInfo(path).fileName());
                        report.insert("bytes", script.size());
                    }
                    break;
                }
            } else {
                report.insert("result", "download-failed");
                report.insert("error", source.lastError());
            }
        }
        reports.append(report);
    }
    QFile output(app.arguments().at(3));
    if (!output.open(QIODevice::WriteOnly)) return 4;
    output.write(QJsonDocument(reports).toJson());
    return 0;
}
