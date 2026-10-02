#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>

#include <iostream>
#include <string>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    std::string line;
    while (std::getline(std::cin, line)) {
        const QJsonObject request = QJsonDocument::fromJson(
            QByteArray::fromStdString(line)).object();
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
