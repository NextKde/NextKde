#pragma once
#include <QQuickTextureFactory>
#include <QQuickWindow>
#include <QColorSpace>
#include <QMutex>
#include <QMutexLocker>
#include <atomic>
#include <cstring>

// Qt's public factory seam keeps texture ownership in the scene graph. Keep a
// lossless compressed recovery copy, not a second full bitmap after upload.
// Compression runs on the image-loading thread; reconstruction never does I/O.
class ArtworkTextureFactory final : public QQuickTextureFactory {
public:
    explicit ArtworkTextureFactory(QImage image) {
        if (image.format() != QImage::Format_RGB32 && image.format() != QImage::Format_ARGB32_Premultiplied)
            image = image.convertToFormat(QImage::Format_ARGB32_Premultiplied);
        size_ = image.size(); format_ = image.format(); stride_ = image.bytesPerLine();
        colorSpace_ = image.colorSpace(); ratio_ = image.devicePixelRatio();
        dotsX_ = image.dotsPerMeterX(); dotsY_ = image.dotsPerMeterY();
        bytes_ = image.sizeInBytes();
        if (bytes_ >= 128 * 1024) {
            auto packed = qCompress(image.constBits(), bytes_, 1);
            if (packed.size() < bytes_ * 9 / 10) packed_ = std::move(packed);
        }
        bitmap_ = std::move(image);
        liveBitmapBytes.fetch_add(bytes_);
        liveRecoveryBytes.fetch_add(packed_.size());
    }
    ~ArtworkTextureFactory() override {
        liveBitmapBytes.fetch_sub(bitmap_.sizeInBytes());
        liveRecoveryBytes.fetch_sub(packed_.size());
    }
    QSize textureSize() const override { return size_; }
    int textureByteCount() const override { return int(bytes_); }
    QImage image() const override {
        QMutexLocker lock(&mutex_);
        return restore();
    }
    QSGTexture* createTexture(QQuickWindow* window) const override {
        QMutexLocker lock(&mutex_);
        const QImage pixels = restore();
        if (pixels.isNull()) return nullptr;
        auto* texture = window->createTextureFromImage(pixels, QQuickWindow::TextureCanUseAtlas);
        if (texture && !packed_.isEmpty() && !bitmap_.isNull()) {
            liveBitmapBytes.fetch_sub(bitmap_.sizeInBytes());
            bitmap_ = {};
        }
        return texture;
    }
    qsizetype retainedBitmapBytes() const { QMutexLocker lock(&mutex_); return bitmap_.sizeInBytes(); }
    qsizetype recoveryBytes() const { return packed_.size(); }
    inline static std::atomic<qint64> liveBitmapBytes{0}, liveRecoveryBytes{0};
private:
    QImage restore() const {
        if (!bitmap_.isNull()) return bitmap_;
        const QByteArray pixels = qUncompress(packed_);
        if (pixels.size() != bytes_) return {};
        // Return owned pixels. Qt may keep this image after the factory call.
        QImage image(size_, format_);
        if (image.isNull() || image.bytesPerLine() != stride_) return {};
        std::memcpy(image.bits(), pixels.constData(), size_t(bytes_));
        image.setColorSpace(colorSpace_); image.setDevicePixelRatio(ratio_);
        image.setDotsPerMeterX(dotsX_); image.setDotsPerMeterY(dotsY_);
        return image;
    }
    QSize size_;
    QImage::Format format_ = QImage::Format_Invalid;
    qsizetype stride_ = 0, bytes_ = 0;
    QColorSpace colorSpace_;
    qreal ratio_ = 1;
    int dotsX_ = 0, dotsY_ = 0;
    QByteArray packed_;
    mutable QMutex mutex_;
    mutable QImage bitmap_;
};
