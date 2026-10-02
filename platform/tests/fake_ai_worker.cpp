#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThread>

#include <iostream>
#include <string>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    std::string line;
    while (std::getline(std::cin, line)) {
        const QJsonObject request = QJsonDocument::fromJson(
            QByteArray::fromStdString(line)).object();
        const QByteArray progress = QJsonDocument(QJsonObject{
            {"version", 1}, {"requestId", request.value("requestId")}, {"event", "progress"},
            {"stage", "test download"}, {"received", 50}, {"total", 100}
        }).toJson(QJsonDocument::Compact);
        std::cout << progress.constData() << '\n' << std::flush;
        if (request.value("imagePath").toString() == "slow") QThread::msleep(2000);
        const QByteArray response = QJsonDocument(QJsonObject{
            {QStringLiteral("version"), 1},
            {QStringLiteral("requestId"), request.value(QStringLiteral("requestId"))},
            {QStringLiteral("ok"), true},
            {QStringLiteral("result"), QJsonObject{
                {QStringLiteral("depthPath"), QStringLiteral("/test/depth.png")},
            }},
        }).toJson(QJsonDocument::Compact);
        std::cout.write(response.constData(), response.size());
        std::cout.put('\n');
        std::cout.flush();
    }
    return 0;
}
