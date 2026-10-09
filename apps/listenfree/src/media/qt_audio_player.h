#pragma once

#include "application/ports.h"

#include <QObject>
#include <QStringList>
#include <QUrl>

#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace listenfree::media {

class QtAudioPlayer final : public QObject,
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
    explicit QtAudioPlayer(QObject* parent = nullptr);
    ~QtAudioPlayer() override;

    [[nodiscard]] domain::PlaybackState state() const noexcept override { return state_; }
    [[nodiscard]] QString stateName() const;
    [[nodiscard]] std::chrono::milliseconds position() const noexcept override;
    [[nodiscard]] std::chrono::milliseconds duration() const noexcept override;
    [[nodiscard]] qint64 positionMs() const noexcept { return position().count(); }
    [[nodiscard]] qint64 durationMs() const noexcept { return duration().count(); }
    [[nodiscard]] bool seekable() const noexcept override;
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
    Q_INVOKABLE void setVolume(float volume) override;
    [[nodiscard]] float volume() const noexcept override;
    Q_INVOKABLE void setMuted(bool muted) override;
    [[nodiscard]] bool muted() const noexcept override;
    void setEvents(application::PlaybackEvents events) override { events_ = std::move(events); }

    [[nodiscard]] std::string_view name() const noexcept override { return "qt-multimedia"; }
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
    [[nodiscard]] bool supported() const noexcept override { return false; }

    [[nodiscard]] std::vector<std::string> deviceIds() const;
    [[nodiscard]] bool routesToAudioOutput() const noexcept;
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
    std::unique_ptr<Impl> impl_;
    domain::PlaybackState state_{domain::PlaybackState::Idle};
    std::optional<domain::PlaybackError> lastError_;
    std::optional<domain::AudioFormatInfo> audioFormat_;
    application::PlaybackEvents events_;
    application::PlaybackBackendEvents backendEvents_;
    application::AudioDeviceEvents deviceEvents_;
    QUrl source_;
    bool hasAudioOutputs_{false};
    bool endNotified_{false};
    bool stoppedByUser_{false};
    bool opening_{false};
    std::uint64_t operationGeneration_{0};

    void setState(domain::PlaybackState state);
    void setError(domain::PlaybackError error);
    void setAudioFormat(domain::AudioFormatInfo info);
};

} // namespace listenfree::media
