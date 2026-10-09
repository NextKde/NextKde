#include "media/media_stream_proxy.h"
#include <QNetworkReply>
#include <QPointer>
#include <QTcpSocket>
#include <QTimer>
#include <QUuid>

namespace listenfree::media {
MediaStreamProxy::MediaStreamProxy(QObject* parent) : QObject(parent) {
    connect(&server_, &QTcpServer::newConnection, this, &MediaStreamProxy::accept);
    server_.listen(QHostAddress::LocalHost, 0);
}
MediaStreamProxy::~MediaStreamProxy() {
    // QObject disconnects this receiver only AFTER C++ members are destroyed.
    // Closing replies/server during member destruction can emit disconnected
    // and otherwise touch the already-destroyed sockets_ list.
    server_.close();
    for(auto* socket:sockets_) {
        socket->disconnect(this);
        socket->abort();
        delete socket;
    }
    sockets_.clear();
}
QUrl MediaStreamProxy::publish(const QUrl& url, const QVariantMap& headers) {
    cancel();
    if (!server_.isListening() || url.host().isEmpty() ||
        (url.scheme() != "http" && url.scheme() != "https")) return {};
    upstream_ = url;
    headers_ = headers;
    path_ = '/' + QUuid::createUuid().toByteArray(QUuid::WithoutBraces);
    return QUrl(QStringLiteral("http://127.0.0.1:%1%2").arg(server_.serverPort()).arg(QString::fromLatin1(path_)));
}
void MediaStreamProxy::cancel() {
    path_.clear();
    upstream_.clear();
    const auto sockets = sockets_;
    for (auto* socket : sockets) socket->abort();
}
void MediaStreamProxy::accept() {
    while (server_.hasPendingConnections()) {
        auto* socket = server_.nextPendingConnection();
        sockets_.append(socket);
        socket->setReadBufferSize(16384);
        connect(socket, &QTcpSocket::disconnected, this, [this, socket] {
            sockets_.removeAll(socket);
            socket->deleteLater();
        });
        QTimer::singleShot(10000, socket, [socket] {
            if (!socket->property("started").toBool()) socket->abort();
        });
        connect(socket, &QTcpSocket::readyRead, this, [this, socket] {
            if (socket->property("started").toBool()) return;
            QByteArray request = socket->property("request").toByteArray() + socket->readAll();
            if (request.size() > 16384) { socket->abort(); return; }
            if (!request.contains("\r\n\r\n")) { socket->setProperty("request", request); return; }
            socket->setProperty("started", true);
            const auto lines = request.split('\n');
            const auto first = lines.value(0).trimmed().split(' ');
            if (first.size() != 3 || first[1] != path_ || path_.isEmpty() ||
                (first[0] != "GET" && first[0] != "HEAD")) {
                socket->write("HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\n\r\n");
                socket->disconnectFromHost(); return;
            }
            QNetworkRequest upstream(upstream_);
            // A media consumer can intentionally stop reading for minutes.
            // Qt's socket inactivity timeout cannot distinguish that from a
            // stalled server; the reply watchdog below understands backpressure.
            upstream.setTransferTimeout(0);
            upstream.setRawHeader("Accept-Encoding", "identity");
            for (auto it = headers_.cbegin(); it != headers_.cend(); ++it) {
                const auto key = it.key().toLatin1();
                const auto value = it.value().toString().toUtf8();
                if (!key.contains('\r') && !key.contains('\n') && !value.contains('\r') && !value.contains('\n') &&
                    key.compare("Host", Qt::CaseInsensitive) != 0 && key.compare("Content-Length", Qt::CaseInsensitive) != 0)
                    upstream.setRawHeader(key, value);
            }
            for (const auto& line : lines) {
                if (line.toLower().startsWith("range:")) upstream.setRawHeader("Range", line.mid(6).trimmed());
                if (line.toLower().startsWith("icy-metadata:")) upstream.setRawHeader("Icy-MetaData", line.mid(13).trimmed());
            }
            auto* reply = first[0] == "HEAD" ? network_.head(upstream) : network_.get(upstream);
            reply->setReadBufferSize(262144);
            connect(socket, &QTcpSocket::disconnected, reply, &QNetworkReply::abort);
            auto* watchdog = new QTimer(reply);
            watchdog->setInterval(1000);
            connect(reply, &QNetworkReply::downloadProgress, watchdog, [watchdog] {
                watchdog->setProperty("idleTicks", 0);
            });
            connect(reply, &QNetworkReply::finished, watchdog, &QTimer::stop);
            connect(socket, &QObject::destroyed, watchdog, &QTimer::stop);
            connect(watchdog, &QTimer::timeout, reply, [socket, reply, watchdog] {
                if(reply->isFinished()) { watchdog->stop(); return; }
                if(reply->bytesAvailable() || socket->bytesToWrite()) {
                    watchdog->setProperty("idleTicks", 0); return;
                }
                const int ticks = watchdog->property("idleTicks").toInt() + 1;
                watchdog->setProperty("idleTicks", ticks);
                if(ticks >= 20)reply->abort();
            });
            watchdog->start();
            const auto pump = [socket, reply] {
                if (socket->state() != QAbstractSocket::ConnectedState) return;
                if (!reply->property("headersSent").toBool()) {
                    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                    // Qt emits metadata for intermediate redirects too. The
                    // local decoder must receive only the final media response.
                    if (status >= 300 && status < 400 && !reply->isFinished()) return;
                    if (!status && !reply->isFinished()) return;
                    QByteArray headers = "HTTP/1.0 " + QByteArray::number(status ? status : 502) + " Media\r\nConnection: close\r\n";
                    for (const auto& key : {QByteArray("Content-Type"), QByteArray("Content-Length"), QByteArray("Content-Range"), QByteArray("Accept-Ranges"), QByteArray("icy-metaint"), QByteArray("icy-name"), QByteArray("icy-br"), QByteArray("icy-genre"), QByteArray("icy-url")}) {
                        const auto value = reply->rawHeader(key);
                        if (!value.isEmpty()) headers += key + ": " + value + "\r\n";
                    }
                    socket->write(headers + "\r\n");
                    reply->setProperty("headersSent", true);
                }
                while (reply->bytesAvailable() && socket->bytesToWrite() < 262144)
                    socket->write(reply->read(65536));
                if (reply->isFinished() && !reply->bytesAvailable()) socket->disconnectFromHost();
            };
            connect(reply, &QNetworkReply::metaDataChanged, socket, pump);
            connect(reply, &QIODevice::readyRead, socket, pump);
            connect(reply, &QNetworkReply::finished, socket, pump);
            connect(socket, &QTcpSocket::bytesWritten, reply, pump);
            connect(socket, &QObject::destroyed, reply, &QObject::deleteLater);
        });
    }
}
}
