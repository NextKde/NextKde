#pragma once

#include "application/ports.h"

#include <QObject>
#include <QStringList>
#include <QUrl>

#include <chrono>
#include <array>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace listenfree::media {

// Optional mature playback backend.  The libmpv dependency is intentionally
// hidden behind this deep module; application and QML code only sees the
// existing playback/device/effects ports.
class MpvAudioPlayer final : public QObject,
                             public application::IAudioPlayer,
                             public application::IPlaybackBackend,
                             public application::IAudioDeviceService,
                             public application::IEqualizerService {
    Q_OBJECT
    Q_PROPERTY(QString state READ stateName NOTIFY stateChanged)
    Q_PROPERTY(qint64 position READ positionMs NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ durationMs NOTIFY durationChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(float volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY mutedChanged)
    Q_PROPERTY(QStringList deviceIds READ qtDeviceIds NOTIFY devicesChanged)
    Q_PROPERTY(quint32 capabilities READ capabilities NOTIFY capabilitiesChanged)
public:
    explicit MpvAudioPlayer(QObject* parent = nullptr);
    ~MpvAudioPlayer() override;

    [[nodiscard]] domain::PlaybackState state() const noexcept override { return state_; }
    [[nodiscard]] QString stateName() const;
    [[nodiscard]] std::chrono::milliseconds position() const noexcept override { return position_; }
    [[nodiscard]] std::chrono::milliseconds duration() const noexcept override { return duration_; }
    [[nodiscard]] qint64 positionMs() const noexcept { return position_.count(); }
    [[nodiscard]] qint64 durationMs() const noexcept { return duration_.count(); }
    [[nodiscard]] bool seekable() const noexcept override { return seekable_; }
    [[nodiscard]] std::optional<domain::PlaybackError> lastError() const override { return lastError_; }
    [[nodiscard]] std::optional<domain::AudioFormatInfo> audioFormat() const override {
        return audioFormat_;
    }

    void open(const domain::PlaybackItem& item) override;
    Q_INVOKABLE void clear() override;
    Q_INVOKABLE void play() override;
    Q_INVOKABLE void pause() override;
    Q_INVOKABLE void stop() override;
    void seek(std::chrono::milliseconds position) override;
    Q_INVOKABLE void setVolume(float normalized) override;
    [[nodiscard]] float volume() const noexcept override { return volume_; }
    Q_INVOKABLE void setMuted(bool muted) override;
    [[nodiscard]] bool muted() const noexcept override { return muted_; }
    void setEvents(application::PlaybackEvents events) override { events_ = std::move(events); }

    [[nodiscard]] std::string_view name() const noexcept override { return "libmpv"; }
    [[nodiscard]] bool available() const noexcept override { return available_; }
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
    [[nodiscard]] bool supported() const noexcept override { return available_; }
    bool setBandGain(std::size_t band, float gainDb) override;
    bool setReverb(float amount) override;
    Q_INVOKABLE bool setEqualizerBand(int band, float gainDb);
    Q_INVOKABLE bool setReverbAmount(float amount);

    [[nodiscard]] QStringList qtDeviceIds() const;
    Q_INVOKABLE void open(const QUrl& url);
    Q_INVOKABLE void seek(qint64 position);
    Q_INVOKABLE bool selectDevice(const QString& id);

signals:
    void stateChanged();
    void positionChanged();
    void durationChanged();
    void seekableChanged();
    void volumeChanged(float volume);
    void mutedChanged(bool muted);
    void errorChanged(const QString& message);
    void audioFormatChanged();
    void devicesChanged();
    void selectedDeviceChanged();
    void capabilitiesChanged();

private:
    class Impl;
    bool available_{false};
    std::unique_ptr<Impl> impl_;
    domain::PlaybackState state_{domain::PlaybackState::Idle};
    std::chrono::milliseconds position_{0};
    std::chrono::milliseconds duration_{0};
    bool seekable_{false};
    float volume_{1.0F};
    bool muted_{false};
    bool opening_{false};
    bool stoppedByUser_{false};
    bool playRequested_{false};
    bool endNotified_{false};
    std::uint64_t operationGeneration_{0};
    std::uint64_t sourceGeneration_{0};
    QUrl source_;
    std::optional<domain::PlaybackError> lastError_;
    std::optional<domain::AudioFormatInfo> audioFormat_;
    application::PlaybackEvents events_;
    application::PlaybackBackendEvents backendEvents_;
    application::AudioDeviceEvents deviceEvents_;

    void setState(domain::PlaybackState state);
    void setError(domain::PlaybackError error);
    void clearError();
    void setPosition(std::chrono::milliseconds value);
    void setDuration(std::chrono::milliseconds value);
    void setSeekable(bool value);
    void setVolumeValue(float value);
    void setMutedValue(bool value);
    void setAudioFormat(std::optional<domain::AudioFormatInfo> value);
    void notifyFinished();
    std::array<float, 10> equalizerGains_{};
    float reverbAmount_{0.0F};
};

} // namespace listenfree::media
