#pragma once

#include <QNetworkProxy>
#include <QSslCertificate>
#include <QSslConfiguration>
#include <QSslKey>
#include <QSslSocket>
#include <QTcpServer>

// A local CONNECT proxy terminates TLS for the fixed production hostnames.
// Tests trust only their generated certificate; no SSL-error bypass is used.
class ReleaseHttpsFixture : public QTcpServer {
public:
    struct Response {
        int status = 200;
        QByteArray body = "fixture";
        QByteArray headers;
        bool stall = false;
        bool disconnect = false;
    };
    QList<Response> responses;
    QStringList targets, requestLines;
    int requests = 0;

    ReleaseHttpsFixture(const QSslCertificate& certificate, const QSslKey& key)
        : m_certificate(certificate), m_key(key), m_previous(QNetworkProxy::applicationProxy())
    {
        if (listen(QHostAddress::LocalHost))
            QNetworkProxy::setApplicationProxy(QNetworkProxy(QNetworkProxy::HttpProxy, "127.0.0.1", serverPort()));
    }
    ~ReleaseHttpsFixture() override { QNetworkProxy::setApplicationProxy(m_previous); }

protected:
    void incomingConnection(qintptr descriptor) override
    {
        auto* socket = new QSslSocket(this);
        if (!socket->setSocketDescriptor(descriptor)) { socket->deleteLater(); return; }
        socket->setLocalCertificate(m_certificate);
        socket->setPrivateKey(m_key);
        socket->setPeerVerifyMode(QSslSocket::VerifyNone); // No client certificate is required.
        connect(socket, &QSslSocket::disconnected, socket, &QObject::deleteLater);
        connect(socket, &QSslSocket::readyRead, this,
            [this, socket, bytes = QByteArray{}, tunnel = false, handled = false]() mutable {
                bytes += socket->readAll();
                if (handled || !bytes.contains("\r\n\r\n")) return;
                if (!tunnel) {
                    targets.append(QString::fromLatin1(bytes.split('\n').first().trimmed()));
                    if (!bytes.startsWith("CONNECT ")) { socket->disconnectFromHost(); return; }
                    bytes.clear();
                    tunnel = true;
                    socket->write("HTTP/1.1 200 Connection established\r\n\r\n");
                    socket->flush();
                    socket->startServerEncryption();
                    return;
                }
                handled = true;
                requestLines.append(QString::fromLatin1(bytes.split('\n').first().trimmed()));
                const auto response = responses.value(qMin(requests++, qMax(0, int(responses.size()) - 1)));
                if (response.stall) return;
                if (response.disconnect) { socket->abort(); return; }
                socket->write("HTTP/1.1 " + QByteArray::number(response.status) + " Fixture\r\nConnection: close\r\nContent-Length: "
                    + QByteArray::number(response.body.size()) + "\r\n" + response.headers + "\r\n" + response.body);
                socket->disconnectFromHost();
            });
    }

private:
    QSslCertificate m_certificate;
    QSslKey m_key;
    QNetworkProxy m_previous;
};
