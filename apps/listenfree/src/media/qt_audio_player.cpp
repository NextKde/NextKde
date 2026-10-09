#include "media/qt_audio_player.h"
#include "media/playback_state_machine.h"

#include <QAudioBuffer>
#include <QAudioBufferOutput>
#include <QAudioDevice>
#include <QAudioFormat>
#include <QAudioOutput>
#include <QMediaDevices>
#include <QMediaMetaData>
#include <QMediaPlayer>

#include <algorithm>
#include <utility>

namespace listenfree::media {

namespace {

template <typename Callback, typename... Arguments>
void invokeCallback(const Callback& callback, Arguments&&... arguments) {
    auto snapshot = callback;
    if (snapshot) snapshot(std::forward<Arguments>(arguments)...);
}

domain::PlaybackError mapError(QMediaPlayer::Error error, const QString& message, bool localSource) {
    domain::PlaybackError result;
    result.message = message.isEmpty() ? std::string("media.playback-failed") : message.toStdString();
    switch (error) {
    case QMediaPlayer::ResourceError:
        result.code = localSource ? domain::PlaybackErrorCode::OpenFailed
                                  : domain::PlaybackErrorCode::Network;
        result.retryable = !localSource;
        break;
    case QMediaPlayer::FormatError:
        result.code = domain::PlaybackErrorCode::Unsupported;
        break;
    case QMediaPlayer::NetworkError:
        result.code = domain::PlaybackErrorCode::Network;
        result.retryable = true;
        break;
    case QMediaPlayer::AccessDeniedError:
        result.code = domain::PlaybackErrorCode::OpenFailed;
        break;
    case QMediaPlayer::NoError:
        result.code = localSource ? domain::PlaybackErrorCode::OpenFailed
                                  : domain::PlaybackErrorCode::Internal;
        break;
    }
    return result;
}

std::string sampleFormatName(QAudioFormat::SampleFormat format) {
    switch (format) {
    case QAudioFormat::UInt8: return "pcm_u8";
    case QAudioFormat::Int16: return "pcm_s16";
    case QAudioFormat::Int32: return "pcm_s32";
    case QAudioFormat::Float: return "pcm_f32";
    case QAudioFormat::Unknown:
    case QAudioFormat::NSampleFormats: return "unknown";
    }
    return "unknown";
}

BackendMediaStatus mapMediaStatus(QMediaPlayer::MediaStatus status) {
    switch (status) {
    case QMediaPlayer::NoMedia: return BackendMediaStatus::NoMedia;
    case QMediaPlayer::LoadingMedia: return BackendMediaStatus::Loading;
    case QMediaPlayer::LoadedMedia: return BackendMediaStatus::Loaded;
    case QMediaPlayer::StalledMedia: return BackendMediaStatus::Stalled;
    case QMediaPlayer::BufferingMedia: return BackendMediaStatus::Buffering;
    case QMediaPlayer::BufferedMedia: return BackendMediaStatus::Buffered;
    case QMediaPlayer::EndOfMedia: return BackendMediaStatus::EndOfMedia;
    case QMediaPlayer::InvalidMedia: return BackendMediaStatus::Invalid;
    }
    return BackendMediaStatus::Invalid;
}

BackendPlaybackState mapPlaybackState(QMediaPlayer::PlaybackState state) {
    switch (state) {
    case QMediaPlayer::StoppedState: return BackendPlaybackState::Stopped;
    case QMediaPlayer::PlayingState: return BackendPlaybackState::Playing;
    case QMediaPlayer::PausedState: return BackendPlaybackState::Paused;
    }
    return BackendPlaybackState::Stopped;
}

} // namespace

class QtAudioPlayer::Impl final {
public:
    explicit Impl(QtAudioPlayer& owner) : owner_(owner) {
        player_.setAudioOutput(&output_);
        player_.setAudioBufferOutput(&bufferOutput_);

        connect(&player_, &QMediaPlayer::positionChanged, &owner_, [this](qint64 value) {
            emit owner_.positionChanged();
            invokeCallback(owner_.events_.onPositionChanged, std::chrono::milliseconds(value));
        });
        connect(&player_, &QMediaPlayer::durationChanged, &owner_, [this](qint64 value) {
            emit owner_.durationChanged();
            invokeCallback(owner_.events_.onDurationChanged, std::chrono::milliseconds(value));
        });
        connect(&player_, &QMediaPlayer::seekableChanged, &owner_, [this](bool seekable) {
            emit owner_.seekableChanged();
            invokeCallback(owner_.events_.onSeekableChanged, seekable);
        });
        connect(&output_, &QAudioOutput::volumeChanged, &owner_, [this](float volume) {
            emit owner_.volumeChanged(volume);
            invokeCallback(owner_.events_.onVolumeChanged, volume);
        });
        connect(&output_, &QAudioOutput::mutedChanged, &owner_, [this](bool muted) {
            emit owner_.mutedChanged(muted);
            invokeCallback(owner_.events_.onMutedChanged, muted);
        });
        connect(&output_, &QAudioOutput::deviceChanged, &owner_, [this] {
            emit owner_.selectedDeviceChanged();
            invokeCallback(owner_.deviceEvents_.onSelectedDeviceChanged,
                           owner_.selectedDeviceId());
        });
        connect(&player_, &QMediaPlayer::playbackStateChanged, &owner_, [this](auto state) {
            Q_UNUSED(state);
            applyState();
        });
        connect(&player_, &QMediaPlayer::mediaStatusChanged, &owner_, [this](auto status) {
            if (status != QMediaPlayer::EndOfMedia) owner_.endNotified_ = false;
            if (status == QMediaPlayer::LoadedMedia || status == QMediaPlayer::BufferedMedia ||
                status == QMediaPlayer::InvalidMedia || status == QMediaPlayer::EndOfMedia) {
                owner_.opening_ = false;
            }
            if (status == QMediaPlayer::InvalidMedia && !owner_.lastError_) {
                owner_.setError(mapError(player_.error(), player_.errorString(),
                                         owner_.source_.isLocalFile()));
                return;
            }
            applyState();
        });
        connect(&player_, &QMediaPlayer::errorOccurred, &owner_,
                [this](QMediaPlayer::Error error, const QString& message) {
                    owner_.opening_ = false;
                    owner_.setError(mapError(error, message, owner_.source_.isLocalFile()));
                });
        connect(&bufferOutput_, &QAudioBufferOutput::audioBufferReceived, &owner_,
                [this](const QAudioBuffer& buffer) { updateAudioFormat(buffer); });
        connect(&devices_, &QMediaDevices::audioOutputsChanged, &owner_, [this] {
            refreshDevices();
        });
    }

    ~Impl() {
        player_.blockSignals(true);
        output_.blockSignals(true);
        bufferOutput_.blockSignals(true);
        devices_.blockSignals(true);
        player_.stop();
        player_.setSource({});
        player_.setAudioBufferOutput(nullptr);
        player_.setAudioOutput(nullptr);
    }

    void refreshDevices() {
        const auto generation = owner_.operationGeneration_;
        const auto outputs = QMediaDevices::audioOutputs();
        const bool hasOutputs = !outputs.isEmpty();
        const QByteArray selected = output_.device().id();
        const bool selectedStillExists =
            std::any_of(outputs.cbegin(), outputs.cend(), [&selected](const QAudioDevice& device) {
                return device.id() == selected;
            });
        if (!selectedStillExists || selected.isEmpty()) {
            output_.setDevice(QMediaDevices::defaultAudioOutput());
            if (owner_.operationGeneration_ != generation) return;
        }
        emit owner_.devicesChanged();
        if (owner_.operationGeneration_ != generation) return;
        invokeCallback(owner_.deviceEvents_.onDevicesChanged);
        if (owner_.operationGeneration_ != generation) return;
        owner_.hasAudioOutputs_ = hasOutputs;
        emit owner_.capabilitiesChanged();
        invokeCallback(owner_.backendEvents_.onCapabilitiesChanged, owner_.capabilities());
    }

    void applyState() {
        const auto generation = owner_.operationGeneration_;
        const auto reduction = reducePlaybackState({mapMediaStatus(player_.mediaStatus()),
                                                     mapPlaybackState(player_.playbackState()),
                                                     !owner_.source_.isEmpty(),
                                                     owner_.lastError_.has_value(),
                                                     owner_.stoppedByUser_, owner_.opening_});
        owner_.setState(reduction.state);
        if (owner_.operationGeneration_ != generation) return;
        if (reduction.finished && !owner_.endNotified_) {
            owner_.endNotified_ = true;
            invokeCallback(owner_.events_.onFinished);
        }
    }

    void updateAudioFormat(const QAudioBuffer& buffer) {
        if (!buffer.isValid() || owner_.audioFormat_.has_value()) return;
        const auto format = buffer.format();
        const auto metadata = player_.metaData();
        domain::AudioFormatInfo info;
        info.codec = metadata.stringValue(QMediaMetaData::AudioCodec).toStdString();
        if (info.codec.empty()) info.codec = sampleFormatName(format.sampleFormat());
        info.sampleRate = format.sampleRate();
        info.channels = format.channelCount();
        info.bitrate = metadata.value(QMediaMetaData::AudioBitRate).toInt();
        if (info.bitrate <= 0) {
            info.bitrate = format.sampleRate() * format.channelCount() * format.bytesPerSample() * 8;
        }
        owner_.setAudioFormat(std::move(info));
    }

    QtAudioPlayer& owner_;
    QMediaDevices devices_;
    QAudioOutput output_;
    QAudioBufferOutput bufferOutput_;
    QMediaPlayer player_;
};

QtAudioPlayer::QtAudioPlayer(QObject* parent)
    : QObject(parent), impl_(std::make_unique<Impl>(*this)),
      hasAudioOutputs_(!QMediaDevices::audioOutputs().isEmpty()) {}

QtAudioPlayer::~QtAudioPlayer() {
    events_ = {};
    backendEvents_ = {};
    deviceEvents_ = {};
    impl_.reset();
}

QString QtAudioPlayer::stateName() const {
    switch (state_) {
    case domain::PlaybackState::Idle: return QStringLiteral("Idle");
    case domain::PlaybackState::Loading: return QStringLiteral("Loading");
    case domain::PlaybackState::Playing: return QStringLiteral("Playing");
    case domain::PlaybackState::Paused: return QStringLiteral("Paused");
    case domain::PlaybackState::Stopped: return QStringLiteral("Stopped");
    case domain::PlaybackState::Buffering: return QStringLiteral("Buffering");
    case domain::PlaybackState::Error: return QStringLiteral("Error");
    }
    return QStringLiteral("Error");
}

std::chrono::milliseconds QtAudioPlayer::position() const noexcept {
    return std::chrono::milliseconds(impl_->player_.position());
}

std::chrono::milliseconds QtAudioPlayer::duration() const noexcept {
    return std::chrono::milliseconds(impl_->player_.duration());
}

bool QtAudioPlayer::seekable() const noexcept { return impl_->player_.isSeekable(); }

void QtAudioPlayer::open(const domain::PlaybackItem& item) {
    if (item.resolvedUrl) open(QUrl(QString::fromStdString(*item.resolvedUrl)));
    else if (item.track.localPath) open(QUrl::fromLocalFile(QString::fromStdString(*item.track.localPath)));
    else if (item.track.remoteUrl) open(QUrl(QString::fromStdString(*item.track.remoteUrl)));
    else clear();
}

void QtAudioPlayer::open(const QUrl& url) {
    const auto operation = ++operationGeneration_;
    if (url.isEmpty()) {
        clear();
        return;
    }
    const QString scheme = url.scheme().toLower();
    if (!url.isLocalFile() && scheme != QStringLiteral("http") && scheme != QStringLiteral("https")) {
        const bool hadFormat = audioFormat_.has_value();
        impl_->player_.stop();
        if (operationGeneration_ != operation) return;
        impl_->player_.setSource({});
        if (operationGeneration_ != operation) return;
        source_ = url;
        audioFormat_.reset();
        endNotified_ = false;
        stoppedByUser_ = false;
        opening_ = false;
        setError({domain::PlaybackErrorCode::Unsupported, "media.unsupported-url-scheme", false});
        if (operationGeneration_ != operation) return;
        if (hadFormat) {
            emit audioFormatChanged();
            if (operationGeneration_ != operation) return;
            invokeCallback(events_.onAudioFormatChanged,
                           std::optional<domain::AudioFormatInfo>{});
        }
        return;
    }
    const bool hadError = lastError_.has_value();
    const bool hadFormat = audioFormat_.has_value();
    source_ = url;
    lastError_.reset();
    audioFormat_.reset();
    endNotified_ = false;
    stoppedByUser_ = false;
    opening_ = true;
    if (hadError) {
        emit errorChanged({});
        if (operationGeneration_ != operation) return;
        invokeCallback(events_.onErrorChanged, std::optional<domain::PlaybackError>{});
        if (operationGeneration_ != operation) return;
    }
    if (hadFormat) {
        emit audioFormatChanged();
        if (operationGeneration_ != operation) return;
        invokeCallback(events_.onAudioFormatChanged, std::optional<domain::AudioFormatInfo>{});
        if (operationGeneration_ != operation) return;
    }
    if (impl_->player_.audioBufferOutput() == nullptr) {
        impl_->player_.setAudioBufferOutput(&impl_->bufferOutput_);
    }
    if (impl_->player_.audioOutput() == nullptr) {
        impl_->player_.setAudioOutput(&impl_->output_);
    }
    setState(domain::PlaybackState::Loading);
    if (operationGeneration_ != operation) return;
    impl_->player_.setSource(url);
}

void QtAudioPlayer::clear() {
    const auto operation = ++operationGeneration_;
    const bool hadError = lastError_.has_value();
    const bool hadFormat = audioFormat_.has_value();
    endNotified_ = false;
    stoppedByUser_ = false;
    opening_ = false;
    source_ = QUrl{};
    impl_->player_.stop();
    if (operationGeneration_ != operation) return;
    impl_->player_.setSource({});
    if (operationGeneration_ != operation) return;
    impl_->player_.setAudioBufferOutput(nullptr);
    impl_->player_.setAudioOutput(nullptr);
    lastError_.reset();
    audioFormat_.reset();
    setState(domain::PlaybackState::Idle);
    if (hadError) {
        emit errorChanged({});
        if (operationGeneration_ != operation) return;
        invokeCallback(events_.onErrorChanged, std::optional<domain::PlaybackError>{});
        if (operationGeneration_ != operation) return;
    }
    if (hadFormat) {
        emit audioFormatChanged();
        if (operationGeneration_ != operation) return;
        invokeCallback(events_.onAudioFormatChanged, std::optional<domain::AudioFormatInfo>{});
    }
}

void QtAudioPlayer::play() {
    const auto operation = ++operationGeneration_;
    if (source_.isEmpty()) {
        setState(domain::PlaybackState::Idle);
        return;
    }
    if (impl_->player_.mediaStatus() == QMediaPlayer::EndOfMedia) {
        impl_->player_.setPosition(0);
        if (operationGeneration_ != operation) return;
    }
    stoppedByUser_ = false;
    impl_->player_.play();
}

void QtAudioPlayer::pause() {
    ++operationGeneration_;
    if (!source_.isEmpty()) impl_->player_.pause();
}

void QtAudioPlayer::stop() {
    const auto operation = ++operationGeneration_;
    if (source_.isEmpty()) {
        setState(domain::PlaybackState::Idle);
        return;
    }
    stoppedByUser_ = true;
    opening_ = false;
    impl_->player_.stop();
    if (operationGeneration_ != operation) return;
    setState(domain::PlaybackState::Stopped);
}

void QtAudioPlayer::seek(qint64 value) {
    ++operationGeneration_;
    const qint64 bounded = std::clamp(value, qint64(0),
                                      std::max(qint64(0), impl_->player_.duration()));
    impl_->player_.setPosition(bounded);
}

void QtAudioPlayer::seek(std::chrono::milliseconds value) { seek(value.count()); }
void QtAudioPlayer::setVolume(float value) {
    ++operationGeneration_;
    impl_->output_.setVolume(std::clamp(value, 0.0F, 1.0F));
}
float QtAudioPlayer::volume() const noexcept { return impl_->output_.volume(); }
void QtAudioPlayer::setMuted(bool value) {
    ++operationGeneration_;
    impl_->output_.setMuted(value);
}
bool QtAudioPlayer::muted() const noexcept { return impl_->output_.isMuted(); }

std::uint32_t QtAudioPlayer::capabilities() const noexcept {
    using application::PlaybackCapability;
    if (!available()) return 0U;
    return application::capabilityMask(PlaybackCapability::LocalFile) |
           application::capabilityMask(PlaybackCapability::HttpStream) |
           application::capabilityMask(PlaybackCapability::Seek) |
           application::capabilityMask(PlaybackCapability::Volume) |
           application::capabilityMask(PlaybackCapability::Mute) |
           (hasAudioOutputs_ ? application::capabilityMask(PlaybackCapability::DeviceSelection) : 0U);
}

bool QtAudioPlayer::available() const noexcept { return impl_->player_.isAvailable(); }

std::vector<application::AudioDeviceInfo> QtAudioPlayer::devices() const {
    std::vector<application::AudioDeviceInfo> result;
    const auto outputs = QMediaDevices::audioOutputs();
    QByteArray selected = impl_->output_.device().id();
    if (selected.isEmpty()) selected = QMediaDevices::defaultAudioOutput().id();
    result.reserve(static_cast<std::size_t>(outputs.size()));
    for (const auto& device : outputs) {
        result.push_back({device.id().toStdString(), device.description().toStdString(),
                          device.isDefault(), device.id() == selected});
    }
    return result;
}

std::string QtAudioPlayer::selectedDeviceId() const {
    const auto selected = impl_->output_.device();
    return (selected.isNull() ? QMediaDevices::defaultAudioOutput().id() : selected.id()).toStdString();
}

std::vector<std::string> QtAudioPlayer::deviceIds() const {
    std::vector<std::string> result;
    const auto outputs = QMediaDevices::audioOutputs();
    result.reserve(static_cast<std::size_t>(outputs.size()));
    for (const auto& device : outputs) result.push_back(device.id().toStdString());
    return result;
}

QStringList QtAudioPlayer::qtDeviceIds() const {
    QStringList result;
    const auto outputs = QMediaDevices::audioOutputs();
    result.reserve(outputs.size());
    for (const auto& device : outputs) result.push_back(QString::fromUtf8(device.id()));
    return result;
}

bool QtAudioPlayer::select(std::string_view id) {
    ++operationGeneration_;
    const QByteArray requested(id.data(), static_cast<qsizetype>(id.size()));
    const auto outputs = QMediaDevices::audioOutputs();
    const auto match = std::find_if(outputs.cbegin(), outputs.cend(), [&requested](const QAudioDevice& device) {
        return device.id() == requested;
    });
    if (match == outputs.cend()) return false;
    impl_->output_.setDevice(*match);
    return true;
}

bool QtAudioPlayer::selectDevice(const QString& id) { return select(id.toStdString()); }

void QtAudioPlayer::refresh() {
    ++operationGeneration_;
    impl_->refreshDevices();
}

bool QtAudioPlayer::routesToAudioOutput() const noexcept {
    return impl_->player_.audioOutput() == &impl_->output_;
}

void QtAudioPlayer::setState(domain::PlaybackState state) {
    if (state_ == state) return;
    state_ = state;
    const auto published = state_;
    emit stateChanged();
    if (state_ != published) return;
    invokeCallback(events_.onStateChanged, published);
}

void QtAudioPlayer::setError(domain::PlaybackError error) {
    if (state_ == domain::PlaybackState::Error && lastError_ && *lastError_ == error) return;
    const auto published = std::move(error);
    lastError_ = published;
    setState(domain::PlaybackState::Error);
    if (!lastError_ || *lastError_ != published || state_ != domain::PlaybackState::Error) return;
    emit errorChanged(QString::fromStdString(published.message));
    if (!lastError_ || *lastError_ != published || state_ != domain::PlaybackState::Error) return;
    invokeCallback(events_.onErrorChanged, std::optional<domain::PlaybackError>{published});
}

void QtAudioPlayer::setAudioFormat(domain::AudioFormatInfo info) {
    if (audioFormat_ && *audioFormat_ == info) return;
    const auto published = std::move(info);
    audioFormat_ = published;
    emit audioFormatChanged();
    if (!audioFormat_ || *audioFormat_ != published) return;
    invokeCallback(events_.onAudioFormatChanged,
                   std::optional<domain::AudioFormatInfo>{published});
}

} // namespace listenfree::media
