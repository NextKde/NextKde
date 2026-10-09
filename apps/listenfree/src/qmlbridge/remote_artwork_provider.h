#pragma once
#include "artwork_texture_factory.h"
#include <QQuickAsyncImageProvider>
#include <QFutureWatcher>
#include <QtConcurrentRun>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QEventLoop>
#include <QImageReader>
#include <QBuffer>
#include <QTimer>
#include <QThreadPool>
#include <QSemaphore>
#include <QScopeGuard>
#include <memory>

// Qt still owns request deduplication and pixmap lifetime. Only the retained
// representation changes; network I/O and decoding run away from rendering.
class RemoteArtworkResponse final : public QQuickImageResponse {
    static QSemaphore& largeDecodeGate() { static QSemaphore gate(1); return gate; }
public:
    struct Result { std::unique_ptr<ArtworkTextureFactory> texture; QString error; };
    RemoteArtworkResponse(QThreadPool* pool, QUrl url, QSize size)
        : cancelled_(std::make_shared<std::atomic_bool>(false)) {
        auto* watcher = new QFutureWatcher<Result>(this);
        connect(watcher, &QFutureWatcher<Result>::finished, this, [this, watcher] {
            auto future = watcher->future();
            result_ = future.takeResult();
            watcher->deleteLater();
            emit finished();
        });
        watcher->setFuture(QtConcurrent::run(pool, [url, size, cancelled=cancelled_] {
            Result result;
            if (cancelled->load()) { result.error = QStringLiteral("Cancelled"); return result; }
            if (url.scheme() != "https" && url.scheme() != "http") {
                result.error = QStringLiteral("Unsupported artwork URL"); return result;
            }
            QImage pixels;
            bool largeDecode = false;
            const auto release = qScopeGuard([&] { if (largeDecode) largeDecodeGate().release(); });
            {
            QNetworkAccessManager network;
            QNetworkRequest request(url);
            request.setTransferTimeout(12000);
            auto* reply = network.get(request);
            // Keep compressed transfers bounded as well as decoded surfaces.
            constexpr qsizetype maxTransfer = 32 * 1024 * 1024;
            reply->setReadBufferSize(maxTransfer + 1);
            QByteArray encoded;
            QEventLoop loop;
            QTimer cancellation;
            QTimer deadline;
            deadline.setSingleShot(true);
            QObject::connect(&deadline, &QTimer::timeout, &loop, [&] { reply->abort(); });
            cancellation.setInterval(50);
            QObject::connect(&cancellation, &QTimer::timeout, &loop, [&] {
                if (cancelled->load()) reply->abort();
            });
            QObject::connect(reply, &QIODevice::readyRead, &loop, [&] {
                encoded += reply->readAll();
                if (encoded.size() > maxTransfer) reply->abort();
            });
            QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
            cancellation.start(); deadline.start(15000); loop.exec();
            if (cancelled->load() || reply->error() != QNetworkReply::NoError) {
                result.error = cancelled->load() ? QStringLiteral("Cancelled") : reply->errorString();
                return result;
            }
            encoded += reply->readAll();
            if (encoded.size() > maxTransfer) { result.error = QStringLiteral("Artwork too large"); return result; }
            QBuffer buffer(&encoded); buffer.open(QIODevice::ReadOnly);
            QImageReader reader(&buffer); reader.setAutoTransform(true);
            const QSize original = reader.size();
            if (original.isValid()) {
                QSize target = original;
                if (size.width() > 0 && size.height() > 0)
                    target.scale(size, Qt::KeepAspectRatioByExpanding);
                else if (size.width() > 0) target.scale(size.width(), original.height() * 2400, Qt::KeepAspectRatio);
                else if (size.height() > 0) target.scale(original.width() * 2400, size.height(), Qt::KeepAspectRatio);
                // Respect one-axis and crop requests: a portrait may legitimately
                // need a taller backing to preserve detail in the visible area.
                if (target.width() < original.width() || target.height() < original.height()) reader.setScaledSize(target);
            }
            // Some codecs downsample only after allocating the original bitmap.
            // Bound concurrent large decodes, including the lossless recovery
            // compression below. Small covers still use all three workers.
            if (!original.isValid() || qint64(original.width()) * original.height() * 4 >= 8 * 1024 * 1024) {
                while (!largeDecodeGate().tryAcquire(1, 50)) {
                    if (cancelled->load()) { result.error = QStringLiteral("Cancelled"); return result; }
                }
                largeDecode = true;
            }
            if (cancelled->load()) { result.error = QStringLiteral("Cancelled"); return result; }
            pixels = reader.read();
            if (pixels.isNull()) result.error = reader.errorString();
            } // Drop encoded bytes, reply, TLS/network and reader before qCompress.
            if (cancelled->load()) result.error = QStringLiteral("Cancelled");
            else if (!pixels.isNull()) result.texture = std::make_unique<ArtworkTextureFactory>(std::move(pixels));
            return result;
        }));
    }
    void cancel() override { cancelled_->store(true); }
    QQuickTextureFactory* textureFactory() const override { return result_.texture.release(); }
    QString errorString() const override { return result_.error; }
private:
    std::shared_ptr<std::atomic_bool> cancelled_;
    mutable Result result_;
};

class RemoteArtworkProvider final : public QQuickAsyncImageProvider {
public:
    RemoteArtworkProvider() { pool_.setMaxThreadCount(3); pool_.setExpiryTimeout(10000); }
    QQuickImageResponse* requestImageResponse(const QString& id, const QSize& size) override {
        return new RemoteArtworkResponse(&pool_, QUrl(QUrl::fromPercentEncoding(id.toUtf8())), size);
    }
private:
    QThreadPool pool_;
};
