#pragma once
#include <QNetworkAccessManager>
#include <QTcpServer>
#include <QUrl>
#include <QVariantMap>

namespace listenfree::media {
// A bounded bridge between Qmmp's HTTP transport and Qt's HTTP/TLS client.
// Only the currently registered opaque URL is served, on loopback.
class MediaStreamProxy final : public QObject {
    Q_OBJECT
public:
    explicit MediaStreamProxy(QObject* parent = nullptr);
    ~MediaStreamProxy() override;
    QUrl publish(const QUrl& upstream, const QVariantMap& headers = {});
    void cancel();
private:
    QTcpServer server_;
    QNetworkAccessManager network_;
    QUrl upstream_;
    QVariantMap headers_;
    QByteArray path_;
    QList<QTcpSocket*> sockets_;
    void accept();
};
}
