#pragma once
#include <QObject>
#include <QVariantList>
#include <QTimer>
#include <QPointer>
#include <QNetworkAccessManager>
#include <QMediaPlayer>
#include <QVideoSink>
#include <memory>
#include <functional>
#include <QJsonObject>
#include "media/media_stream_proxy.h"
#include "media/mv_frame_stream.h"

namespace listenfree::qmlbridge {
class SpectrumSampler;
class ImmersiveController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(bool suspended READ suspended WRITE setSuspended NOTIFY activeChanged)
    Q_PROPERTY(bool spectrumEnabled READ spectrumEnabled WRITE setSpectrumEnabled NOTIFY activeChanged)
    Q_PROPERTY(QVariantList spectrum READ spectrum NOTIFY spectrumChanged)
    Q_PROPERTY(QVariantList candidates READ candidates NOTIFY mvChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY mvChanged)
    Q_PROPERTY(QString error READ error NOTIFY mvChanged)
    Q_PROPERTY(bool videoReady READ videoReady NOTIFY mvChanged)
    Q_PROPERTY(QString videoTitle READ videoTitle NOTIFY mvChanged)
    Q_PROPERTY(QString videoResolution READ videoResolution NOTIFY mvChanged)
    Q_PROPERTY(int offsetMs READ offsetMs WRITE setOffsetMs NOTIFY mvChanged)
public:
    explicit ImmersiveController(QObject* parent = nullptr);
    ~ImmersiveController() override;
    bool active() const { return active_; }
    bool suspended() const { return suspended_; }
    void setSuspended(bool value);
    bool spectrumEnabled() const { return spectrumEnabled_; }
    QVariantList spectrum() const { return spectrum_; }
    QVariantList candidates() const { return candidates_; }
    bool busy() const { return busy_; }
    QString error() const { return error_; }
    bool videoReady() const { return videoReady_; }
    QString videoTitle() const { return videoTitle_; }
    QString videoResolution() const { return videoSize_.isEmpty()?QString{}:QString::number(videoSize_.width())+QStringLiteral(" × ")+QString::number(videoSize_.height()); }
    int offsetMs() const { return offsetMs_; }
    void setActive(bool value);
    void setSpectrumEnabled(bool value);
    void setPlayback(qint64 position, bool playing, const QString& identity);
    void setOffsetMs(int value);
    void setBilibiliCookie(const QByteArray& cookie);
    Q_INVOKABLE void attachVideoSink(QObject* sink);
    Q_INVOKABLE void searchMv(const QString& query, const QString& provider = "wy");
    Q_INVOKABLE void autoMatchMv(const QString& title, const QString& artist, qint64 duration);
    Q_INVOKABLE void selectMv(int index);
    Q_INVOKABLE void openLocalVideo(const QUrl& url);
    Q_INVOKABLE void clearVideo();
    // Pure reduction, also used by the synthetic PCM regression.
    static QVariantList reduceSpectrum(const float* left, const float* right);
    bool sampling() const { return timer_.isActive(); }
    QMediaPlayer* videoPlayer() const { return video_.get(); }
    media::MvFrameStream* nativeVideoPlayer() const { return nativeVideo_.get(); }
    QVideoSink* videoSink() const { return sink_; }
Q_SIGNALS:
    void activeChanged();
    void spectrumChanged();
    void mvChanged();
private:
    void updateSampling();
    void performSearch(const QString& query, const QString& provider);
    void searchBiliPage(const QString& query, int page);
    void finishSearch();
    void resolveMv(const QVariantMap& row);
    void getJson(QUrl url, std::function<void(QJsonObject)> callback);
    void prepareBili(std::function<void()> callback);
    QUrl biliUrl(const QString& path, const QMap<QString,QString>& params) const;
    QString biliMixin_, biliCookie_, searchProvider_, autoTitle_, autoArtist_, autoQuery_, videoReferer_;
    QByteArray biliAccountCookie_;
    qint64 autoDuration_=0;
    bool autoMatching_=false, autoTriedBili_=false;
    void sample();
    void cancelRequest();
    void loadVideo(const QUrl& url, const QString& title, bool remote);
    void startQtVideo(const QUrl& source);
    void syncVideo(bool force = false);
    void failVideo(const QString& message);
    bool active_ = false, suspended_ = false, spectrumEnabled_ = true, playing_ = false;
    bool busy_ = false, videoReady_ = false;
    qint64 position_ = 0;
    int offsetMs_ = 0;
    QString identity_, error_, videoTitle_;
    QVariantList spectrum_, candidates_;
    QTimer timer_, loadTimeout_;
    std::unique_ptr<SpectrumSampler> sampler_;
    std::unique_ptr<QMediaPlayer> video_;
    std::unique_ptr<media::MvFrameStream> nativeVideo_;
    QPointer<QVideoSink> sink_;
    QSize videoSize_;
    QMetaObject::Connection videoSizeConnection_;
    QNetworkAccessManager network_;
    QPointer<QNetworkReply> request_;
    quint64 generation_ = 0;
    std::unique_ptr<media::MediaStreamProxy> proxy_;
};
}
