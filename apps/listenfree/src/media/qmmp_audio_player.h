#pragma once

#include "application/ports.h"

#include <QObject>
#include <QVariant>

#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

class SoundCore;

namespace listenfree::media {

class QmmpAudioPlayer final : public QObject,
                              public application::IAudioPlayer,
                              public application::IPlaybackBackend,
                              public application::IAudioDeviceService,
                              public application::IEqualizerService {
    Q_OBJECT
public:
    explicit QmmpAudioPlayer(QObject* parent = nullptr);
    ~QmmpAudioPlayer() override;

    void open(const domain::PlaybackItem& item) override;
    bool prepareNext(const domain::PlaybackItem& item);
    void configureTransition(bool crossfade, int milliseconds);
    bool startPreparedTransition(int milliseconds, qint64 sourceEndMs = -1);
    void cancelPrepared();
    bool mixing() const;
    QString analysisSource() const { return source_; }
    bool hasPrepared() const { return prepared_.has_value() || pendingPrimary_.has_value(); }
    bool primaryPending() const { return pendingPrimary_.has_value(); }
    void setEqualizer(bool enabled, const std::vector<double>& gains, double preampDb = 0, bool autoHeadroom = true);
    bool setSoundEffects(const QVariantMap& parameters);
    void setLiveBuffering(bool enabled);
signals:
    void streamTitleChanged(const QString& title);
    void preparedStarted();
    void nextTrackRequested();
public:

    void clear() override;
    void play() override;
    void pause() override;
    void stop() override;
    void seek(std::chrono::milliseconds position) override;
    void setVolume(float normalized) override;
    [[nodiscard]] float volume() const noexcept override;
    void setMuted(bool muted) override;
    [[nodiscard]] bool muted() const noexcept override;
    [[nodiscard]] domain::PlaybackState state() const noexcept override { return state_; }
    [[nodiscard]] std::chrono::milliseconds position() const noexcept override;
    [[nodiscard]] std::chrono::milliseconds duration() const noexcept override;
    [[nodiscard]] bool seekable() const noexcept override { return seekable_; }
    [[nodiscard]] std::optional<domain::PlaybackError> lastError() const override {
        return lastError_;
    }
    [[nodiscard]] std::optional<domain::AudioFormatInfo> audioFormat() const override {
        return audioFormat_;
    }
    void setEvents(application::PlaybackEvents events) override { events_ = std::move(events); }

    [[nodiscard]] std::string_view name() const noexcept override { return "qmmp-2.4"; }
    [[nodiscard]] bool available() const noexcept override;
    [[nodiscard]] std::uint32_t capabilities() const noexcept override;
    void setBackendEvents(application::PlaybackBackendEvents events) override {
        backendEvents_ = std::move(events);
    }

    [[nodiscard]] std::vector<application::AudioDeviceInfo> devices() const override;
    [[nodiscard]] std::string selectedDeviceId() const override;
    bool select(std::string_view id) override;
    void refresh() override;
    void setDeviceEvents(application::AudioDeviceEvents events) override {
        deviceEvents_ = std::move(events);
    }

    [[nodiscard]] bool supported() const noexcept override { return available(); }

private:
    bool liveBuffering_{};
    QVariant originalHttpBuffer_,originalHttpDuration_;
    std::unique_ptr<SoundCore> core_;
    QString source_;
    std::optional<domain::PlaybackItem> prepared_;
    std::optional<domain::PlaybackItem> pendingPrimary_;
    QString pendingSource_;
    quint64 feedbackEpoch_{0}, primaryEpoch_{0};
    bool outputClock_{false};
    qint64 incomingPosition_{0}, outgoingEnd_{0};
    std::chrono::milliseconds outgoingDuration_{0};
    void commitPrimary();
    void resetPrimaryFeedback();
    std::uint64_t preparedRevision_{0};
    bool boundary_{false};
    bool transitionRequested_{false}, mixedTrack_{false};
    domain::PlaybackState state_{domain::PlaybackState::Idle};
    std::chrono::milliseconds position_{0};
    std::chrono::milliseconds metadataDuration_{0};
    bool seekable_{false};
    bool sourceIsNetwork_{false};
    bool stoppedByUser_{false};
    bool finishNotified_{false};
    std::uint64_t operationGeneration_{0};
    std::optional<domain::PlaybackError> lastError_;
    std::optional<domain::AudioFormatInfo> audioFormat_;
    application::PlaybackEvents events_;
    application::PlaybackBackendEvents backendEvents_;
    application::AudioDeviceEvents deviceEvents_;

    void recreateCore();
    void connectCore();
    void selectOutputFactory();
    void updateFormatFromCore();
    void setState(domain::PlaybackState state);
    void setError(std::optional<domain::PlaybackError> error);
    void setFormat(std::optional<domain::AudioFormatInfo> format);
    void setSeekable(bool seekable);
    void notifyDuration();
};

} // namespace listenfree::media
