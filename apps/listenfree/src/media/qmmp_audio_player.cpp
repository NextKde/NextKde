#include <qmmp/effect.h>
#include <qmmp/effectfactory.h>
#include "media/qmmp_audio_player.h"
#include <qmmp/eqsettings.h>

#include <qmmp/audioparameters.h>
#include <qmmp/metadatamanager.h>
#include <qmmp/output.h>
#include <qmmp/qmmp.h>
#include <qmmp/soundcore.h>
#include <qmmp/trackinfo.h>

#include <QFileInfo>
#include <QSettings>
#include <QTimer>
#include <QSignalBlocker>
#include <QUrl>

#include <algorithm>
#include <cmath>
#include <utility>

#ifdef Q_OS_WIN
#include <windows.h>
#include <initguid.h>
#include <functiondiscoverykeys_devpkey.h>
#include <mmdeviceapi.h>
#include <propvarutil.h>
#endif

namespace listenfree::media {
namespace {

constexpr auto mask(application::PlaybackCapability capability) {
    return application::capabilityMask(capability);
}

std::string utf8(const QString& value) {
    const QByteArray bytes = value.toUtf8();
    return {bytes.constData(), static_cast<std::size_t>(bytes.size())};
}

QString fromUtf8(std::string_view value) {
    return QString::fromUtf8(value.data(), static_cast<qsizetype>(value.size()));
}

bool hasPlugin(QStringView category, QStringView stem) {
    const auto paths = Qmmp::findPlugins(category.toString());
    return std::any_of(paths.cbegin(), paths.cend(), [stem](const QString& path) {
        return QFileInfo(path).completeBaseName().contains(stem, Qt::CaseInsensitive);
    });
}

std::vector<application::AudioDeviceInfo> enumerateWindowsDevices(std::string_view selected) {
    std::vector<application::AudioDeviceInfo> result;
    result.push_back({"default", "System default", true, selected == "default"});
#ifdef Q_OS_WIN
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool shouldUninitialize = SUCCEEDED(initialized);
    if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) return result;

    IMMDeviceEnumerator* enumerator = nullptr;
    IMMDeviceCollection* collection = nullptr;
    if (FAILED(CoCreateInstance(CLSID_MMDeviceEnumerator, nullptr, CLSCTX_ALL,
                                IID_PPV_ARGS(&enumerator)))) {
        if (shouldUninitialize) CoUninitialize();
        return result;
    }
    if (FAILED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &collection))) {
        enumerator->Release();
        if (shouldUninitialize) CoUninitialize();
        return result;
    }

    UINT count = 0;
    if (SUCCEEDED(collection->GetCount(&count))) {
        for (UINT index = 0; index < count; ++index) {
            IMMDevice* device = nullptr;
            LPWSTR rawId = nullptr;
            IPropertyStore* properties = nullptr;
            PROPVARIANT friendlyName;
            PropVariantInit(&friendlyName);
            if (FAILED(collection->Item(index, &device))) continue;
            const bool idOk = SUCCEEDED(device->GetId(&rawId));
            const bool storeOk = SUCCEEDED(device->OpenPropertyStore(STGM_READ, &properties));
            const bool nameOk = storeOk &&
                                SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName,
                                                               &friendlyName)) &&
                                friendlyName.vt == VT_LPWSTR;
            if (idOk && rawId) {
                const QString id = QString::fromWCharArray(rawId);
                const QString name = nameOk && friendlyName.pwszVal
                                         ? QString::fromWCharArray(friendlyName.pwszVal)
                                         : id;
                const auto idUtf8 = utf8(id);
                result.push_back({idUtf8, utf8(name), false, idUtf8 == selected});
            }
            PropVariantClear(&friendlyName);
            if (properties) properties->Release();
            if (rawId) CoTaskMemFree(rawId);
            device->Release();
        }
    }
    collection->Release();
    enumerator->Release();
    if (shouldUninitialize) CoUninitialize();
#endif
    return result;
}

} // namespace

QmmpAudioPlayer::QmmpAudioPlayer(QObject* parent) : QObject(parent) {
    recreateCore();
}

QmmpAudioPlayer::~QmmpAudioPlayer() {
    if (core_) {
        core_->blockSignals(true);
        core_->stop();
    }
    setLiveBuffering(false);
}
void QmmpAudioPlayer::setLiveBuffering(bool enabled) {
    if(enabled==liveBuffering_)return;
    QSettings settings;
    if(enabled) {
        originalHttpBuffer_=settings.value("HTTP/buffer_size");originalHttpDuration_=settings.value("HTTP/buffer_duration");
        settings.setValue("HTTP/buffer_size",32);settings.setValue("HTTP/buffer_duration",1500);
    } else {
        if(originalHttpBuffer_.isValid())settings.setValue("HTTP/buffer_size",originalHttpBuffer_);else settings.remove("HTTP/buffer_size");
        if(originalHttpDuration_.isValid())settings.setValue("HTTP/buffer_duration",originalHttpDuration_);else settings.remove("HTTP/buffer_duration");
    }
    liveBuffering_=enabled;
}

void QmmpAudioPlayer::selectOutputFactory() {
    const QString requested = qEnvironmentVariable("LISTENFREE_QMMP_OUTPUT", "wasapi");
    for (auto* factory : Output::factories()) {
        if (factory && factory->properties().shortName == requested) {
            Output::setCurrentFactory(factory);
            return;
        }
    }
}

void QmmpAudioPlayer::recreateCore() {
    if (core_) {
        core_->blockSignals(true);
        core_->stop();
        core_.reset();
    }
    selectOutputFactory();
    core_ = std::make_unique<SoundCore>();
    connectCore();
}

void QmmpAudioPlayer::connectCore() {
    connect(core_.get(), &SoundCore::nextTrackRequest, this, &QmmpAudioPlayer::nextTrackRequested);
    connect(core_.get(), &SoundCore::stateChanged, this, [this](Qmmp::State state) {
        const auto generation = operationGeneration_;
        switch (state) {
        case Qmmp::Playing:
            boundary_ = false;
            finishNotified_ = false;
            stoppedByUser_ = false;
            setState(domain::PlaybackState::Playing);
            if (generation != operationGeneration_) return;
            break;
        case Qmmp::Paused:
            setState(domain::PlaybackState::Paused);
            if (generation != operationGeneration_) return;
            break;
        case Qmmp::Stopped:
            if (boundary_) return;
            setState(source_.isEmpty() ? domain::PlaybackState::Idle
                                       : domain::PlaybackState::Stopped);
            if (generation != operationGeneration_) return;
            break;
        case Qmmp::Buffering:
            if (boundary_) return;
            setState(domain::PlaybackState::Buffering);
            if (generation != operationGeneration_) return;
            break;
        case Qmmp::NormalError:
            setError(domain::PlaybackError{
                sourceIsNetwork_ ? domain::PlaybackErrorCode::Network
                                 : domain::PlaybackErrorCode::OpenFailed,
                sourceIsNetwork_ ? "Qmmp could not open the network stream"
                                 : "Qmmp could not decode the local media",
                sourceIsNetwork_});
            if (generation != operationGeneration_) return;
            setState(domain::PlaybackState::Error);
            break;
        case Qmmp::FatalError:
            setError(domain::PlaybackError{domain::PlaybackErrorCode::Internal,
                                           "Qmmp audio output failed", false});
            if (generation != operationGeneration_) return;
            setState(domain::PlaybackState::Error);
            break;
        }
    });
    connect(core_.get(), &SoundCore::elapsedChanged, this, [this](qint64 value) {
        if (pendingPrimary_ || outputClock_) return;
        position_ = std::chrono::milliseconds(std::max<qint64>(0, value));
        if (const auto callback = events_.onPositionChanged) {
            callback(position_);
        }
    });
    connect(core_.get(), &SoundCore::audioParametersChanged, this,
            [this](const AudioParameters&) { updateFormatFromCore(); });
    connect(core_.get(), &SoundCore::bitrateChanged, this,
            [this](int) { updateFormatFromCore(); });
    connect(core_.get(), &SoundCore::trackInfoChanged, this, [this] {
        if (pendingPrimary_) return; // metadata still belongs to A until the output commit
        const auto generation = operationGeneration_;
        if(sourceIsNetwork_)emit streamTitleChanged(core_->trackInfo().value(Qmmp::TITLE));
        if (core_->duration() > 0) metadataDuration_ = std::chrono::milliseconds(core_->duration());
        setSeekable(metadataDuration_.count() > 0);
        if (generation != operationGeneration_) return;
        updateFormatFromCore();
        if (generation != operationGeneration_) return;
        notifyDuration();
    });
    connect(core_.get(), &SoundCore::finished, this, [this] {
        if (stoppedByUser_ || finishNotified_) return;
        if (prepared_ && core_->nextTrackAccepted()) {
            mixedTrack_ = std::exchange(transitionRequested_, false);
            pendingPrimary_ = std::move(prepared_); prepared_.reset(); boundary_=true;
            const auto &item = *pendingPrimary_;
            pendingSource_=item.resolvedUrl ? fromUtf8(*item.resolvedUrl) : item.track.localPath ? QFileInfo(fromUtf8(*item.track.localPath)).absoluteFilePath() : QString{};
            incomingPosition_=0;
            finishNotified_=false;
            if (!mixedTrack_) commitPrimary();
            return;
        }
        const auto generation = operationGeneration_;
        finishNotified_ = true;
        setState(domain::PlaybackState::Stopped);
        if (generation != operationGeneration_) return;
        if (const auto callback = events_.onFinished) callback();
    });
    connect(core_.get(), &SoundCore::outputTrackProgress, this,
            [this](quint64 epoch, const QString &path, qint64 value) {
        if (state_!=domain::PlaybackState::Playing) return;
        if (pendingPrimary_) {
            if (!feedbackEpoch_ || epoch!=feedbackEpoch_ || path!=pendingSource_) return;
        } else if (!outputClock_ || epoch!=primaryEpoch_ || path!=source_) return;
        incomingPosition_=std::max<qint64>(0,value);
        if (pendingPrimary_) {
            const auto overlap=core_->crossfadeDuration();
            // Keep A's lyrics/progress in its source range during the first part
            // of actual A+B output. A short fallback still commits inside its mix.
            position_=std::chrono::milliseconds(std::clamp<qint64>(
                std::max(position_.count(),outgoingEnd_-overlap+value),0,outgoingDuration_.count()));
            const auto commitAt=overlap>=1600 ? 800 : std::max<qint64>(0,overlap/2);
            if (value>=commitAt) commitPrimary();
        } else if (outputClock_) position_=std::chrono::milliseconds(incomingPosition_);
        if (const auto callback=events_.onPositionChanged) callback(position_);
    }, Qt::QueuedConnection);
    connect(core_.get(), &SoundCore::volumeChanged, this, [this](int value) {
        if (const auto callback = events_.onVolumeChanged)
            callback(static_cast<float>(value) / 100.0F);
    });
    connect(core_.get(), &SoundCore::mutedChanged, this, [this](bool value) {
        if (const auto callback = events_.onMutedChanged) callback(value);
    });
}

void QmmpAudioPlayer::open(const domain::PlaybackItem& item) {
    ++preparedRevision_;
    prepared_.reset(); boundary_=false;
    resetPrimaryFeedback();
    transitionRequested_=false; mixedTrack_=false;
    QString candidate;
    bool candidateIsLocalPath = false;
    if (item.resolvedUrl) candidate = fromUtf8(*item.resolvedUrl);
    else if (item.track.localPath) {
        candidate = fromUtf8(*item.track.localPath);
        candidateIsLocalPath = true;
    }
    else if (item.track.remoteUrl) candidate = fromUtf8(*item.track.remoteUrl);
    const auto generation = ++operationGeneration_;
    if (core_) {
        const QSignalBlocker blocker(core_.get());
        core_->stop();
    }
    source_.clear();
    sourceIsNetwork_ = false;
    stoppedByUser_ = true;
    finishNotified_ = false;
    position_ = std::chrono::milliseconds(0);
    metadataDuration_ = item.track.duration;
    setSeekable(false);
    if (generation != operationGeneration_) return;
    setFormat(std::nullopt);
    if (generation != operationGeneration_) return;
    setError(std::nullopt);
    if (generation != operationGeneration_) return;
    notifyDuration();
    if (generation != operationGeneration_) return;
    if (candidate.isEmpty()) {
        setError(domain::PlaybackError{domain::PlaybackErrorCode::OpenFailed,
                                       "Playback item has no media location", false});
        if (generation != operationGeneration_) return;
        setState(domain::PlaybackState::Error);
        return;
    }

    if (candidateIsLocalPath) {
        source_ = candidate;
    } else {
        const QUrl parsed(candidate);
        const QString scheme = parsed.scheme().toLower();
        if (scheme == QStringLiteral("http") || scheme == QStringLiteral("https")) {
            source_ = parsed.toString(QUrl::FullyEncoded);
            sourceIsNetwork_ = true;
        } else if (scheme == QStringLiteral("file")) {
            source_ = parsed.toLocalFile();
        } else if (scheme.isEmpty()) {
            source_ = candidate;
        } else {
            setError(domain::PlaybackError{domain::PlaybackErrorCode::Unsupported,
                                           "Qmmp adapter accepts only local files and HTTP(S)", false});
            if (generation != operationGeneration_) return;
            setState(domain::PlaybackState::Error);
            return;
        }
    }

    setState(domain::PlaybackState::Loading);
    if (generation != operationGeneration_) return;
    if (!sourceIsNetwork_) {
        const QFileInfo file(source_);
        if (!file.isFile()) {
            setError(domain::PlaybackError{domain::PlaybackErrorCode::OpenFailed,
                                           "Local media file does not exist", false});
            if (generation != operationGeneration_) return;
            setState(domain::PlaybackState::Error);
            return;
        }
        source_ = file.absoluteFilePath();
        const auto tracks = MetaDataManager::instance()->createPlayList(source_);
        if (tracks.isEmpty()) {
            setError(domain::PlaybackError{domain::PlaybackErrorCode::Unsupported,
                                           "No enabled Qmmp decoder accepts the local media", false});
            if (generation != operationGeneration_) return;
            setState(domain::PlaybackState::Error);
            return;
        }
        const TrackInfo& track = tracks.constFirst();
        metadataDuration_ = std::chrono::milliseconds(std::max<qint64>(0, track.duration()));
        domain::AudioFormatInfo info;
        info.codec = utf8(track.value(Qmmp::FORMAT_NAME));
        info.sampleRate = track.value(Qmmp::SAMPLERATE).toInt();
        info.channels = track.value(Qmmp::CHANNELS).toInt();
        info.bitrate = track.value(Qmmp::BITRATE).toInt();
        if (!info.codec.empty() || info.sampleRate > 0 || info.channels > 0 || info.bitrate > 0)
            setFormat(std::move(info));
        if (generation != operationGeneration_) return;
        setSeekable(metadataDuration_.count() > 0);
        if (generation != operationGeneration_) return;
    }
    finishNotified_ = false;
    stoppedByUser_ = false;
    setError(std::nullopt);
    if (generation != operationGeneration_) return;
    notifyDuration();
    if (generation != operationGeneration_) return;
    setState(domain::PlaybackState::Stopped);
}

void QmmpAudioPlayer::clear() {
    resetPrimaryFeedback();
    const auto generation = ++operationGeneration_;
    if (core_) recreateCore();
    source_.clear();
    sourceIsNetwork_ = false;
    stoppedByUser_ = true;
    finishNotified_ = false;
    position_ = std::chrono::milliseconds(0);
    metadataDuration_ = std::chrono::milliseconds(0);
    setSeekable(false);
    if (generation != operationGeneration_) return;
    setFormat(std::nullopt);
    if (generation != operationGeneration_) return;
    setError(std::nullopt);
    if (generation != operationGeneration_) return;
    notifyDuration();
    if (generation != operationGeneration_) return;
    setState(domain::PlaybackState::Idle);
}

void QmmpAudioPlayer::play() {
    const auto generation = ++operationGeneration_;
    if (source_.isEmpty() || !core_) {
        setError(domain::PlaybackError{domain::PlaybackErrorCode::InvalidTransition,
                                       "No media is open", false});
        if (generation != operationGeneration_) return;
        setState(domain::PlaybackState::Error);
        return;
    }
    if (state_ == domain::PlaybackState::Paused) {
        core_->pause();
        return;
    }
    if (state_ == domain::PlaybackState::Playing || state_ == domain::PlaybackState::Buffering)
        return;
    stoppedByUser_ = false;
    finishNotified_ = false;
    setError(std::nullopt);
    if (generation != operationGeneration_) return;
    setState(domain::PlaybackState::Loading);
    if (generation != operationGeneration_) return;
    if (!core_->play(source_)) {
        if (generation != operationGeneration_) return;
        setError(domain::PlaybackError{sourceIsNetwork_ ? domain::PlaybackErrorCode::Network
                                                       : domain::PlaybackErrorCode::OpenFailed,
                                       "Qmmp rejected the media source", sourceIsNetwork_});
        if (generation != operationGeneration_) return;
        setState(domain::PlaybackState::Error);
    }
}

void QmmpAudioPlayer::pause() {
    ++operationGeneration_;
    if (core_ && state_ == domain::PlaybackState::Playing) core_->pause();
}

void QmmpAudioPlayer::stop() {
    ++preparedRevision_;
    prepared_.reset(); boundary_=false;
    resetPrimaryFeedback();
    transitionRequested_=false; mixedTrack_=false;
    const auto generation = ++operationGeneration_;
    stoppedByUser_ = true;
    if (core_) core_->stop();
    if (generation != operationGeneration_) return;
    if (!source_.isEmpty()) setState(domain::PlaybackState::Stopped);
}

void QmmpAudioPlayer::seek(std::chrono::milliseconds value) {
    resetPrimaryFeedback();
    transitionRequested_=false; mixedTrack_=false;
    ++operationGeneration_;
    if (!core_ || !seekable_) return;
    const auto upper = std::max<std::int64_t>(0, duration().count());
    const auto clamped = std::clamp<std::int64_t>(value.count(), 0, upper);
    position_ = std::chrono::milliseconds(clamped);
    core_->seek(clamped);
    if (const auto callback = events_.onPositionChanged) callback(position_);
}

void QmmpAudioPlayer::setVolume(float normalized) {
    ++operationGeneration_;
    if (!core_) return;
    const auto clamped = std::clamp(normalized, 0.0F, 1.0F);
    core_->setVolume(static_cast<int>(std::lround(clamped * 100.0F)));
}

float QmmpAudioPlayer::volume() const noexcept {
    return core_ ? static_cast<float>(core_->volume()) / 100.0F : 0.0F;
}

void QmmpAudioPlayer::setMuted(bool value) {
    ++operationGeneration_;
    if (core_) core_->setMuted(value);
}

bool QmmpAudioPlayer::muted() const noexcept {
    return core_ && core_->isMuted();
}

std::chrono::milliseconds QmmpAudioPlayer::position() const noexcept {
    return position_;
}

std::chrono::milliseconds QmmpAudioPlayer::duration() const noexcept {
    if (source_.isEmpty()) return std::chrono::milliseconds(0);
    if (pendingPrimary_) return outgoingDuration_;
    const auto live = core_ ? std::chrono::milliseconds(std::max<qint64>(0, core_->duration()))
                            : std::chrono::milliseconds(0);
    return std::max(live, metadataDuration_);
}

bool QmmpAudioPlayer::available() const noexcept {
    try {
        return hasPlugin(u"Input", u"ffmpeg") &&
               (hasPlugin(u"Output", u"wasapi") || hasPlugin(u"Output", u"null")) &&
               hasPlugin(u"Transports", u"http");
    } catch (...) {
        return false;
    }
}

std::uint32_t QmmpAudioPlayer::capabilities() const noexcept {
    try {
        const bool ffmpeg = hasPlugin(u"Input", u"ffmpeg");
        const bool http = hasPlugin(u"Transports", u"http");
        const bool wasapi = hasPlugin(u"Output", u"wasapi");
        const bool output = wasapi || hasPlugin(u"Output", u"null");
        if (!ffmpeg || !output) return 0;

        std::uint32_t result = mask(application::PlaybackCapability::LocalFile) |
                               mask(application::PlaybackCapability::Seek) |
                               mask(application::PlaybackCapability::Volume) |
                               mask(application::PlaybackCapability::Mute) |
                               mask(application::PlaybackCapability::Equalizer) |
                               mask(application::PlaybackCapability::Gapless) |
                               mask(application::PlaybackCapability::ReplayGain);
        if (http) result |= mask(application::PlaybackCapability::HttpStream);
        if (hasPlugin(u"Effect", u"crossfade"))
            result |= mask(application::PlaybackCapability::Crossfade);
#ifdef Q_OS_WIN
        if (wasapi) {
            result |= mask(application::PlaybackCapability::DeviceSelection);
            result |= mask(application::PlaybackCapability::HighResolution);
        }
#endif
        return result;
    } catch (...) {
        return 0;
    }
}

std::vector<application::AudioDeviceInfo> QmmpAudioPlayer::devices() const {
    return enumerateWindowsDevices(selectedDeviceId());
}

std::string QmmpAudioPlayer::selectedDeviceId() const {
    QSettings settings;
    return utf8(settings.value(QStringLiteral("WASAPI/device"), QStringLiteral("default"))
                    .toString());
}

bool QmmpAudioPlayer::select(std::string_view id) {
    const auto generation = ++operationGeneration_;
    const auto inventory = devices();
    const auto found = std::find_if(inventory.cbegin(), inventory.cend(), [id](const auto& device) {
        return device.id == id;
    });
    if (found == inventory.cend()) return false;
    if (selectedDeviceId() == id) return true;
    QSettings settings;
    settings.setValue(QStringLiteral("WASAPI/device"), fromUtf8(id));
    recreateCore();
    if (generation != operationGeneration_) return false;
    setState(source_.isEmpty() ? domain::PlaybackState::Idle : domain::PlaybackState::Stopped);
    if (generation != operationGeneration_) return false;
    if (const auto callback = deviceEvents_.onSelectedDeviceChanged) callback(std::string(id));
    if (const auto callback = deviceEvents_.onDevicesChanged) callback();
    if (const auto callback = backendEvents_.onCapabilitiesChanged) callback(capabilities());
    return true;
}

void QmmpAudioPlayer::refresh() {
    const auto generation = operationGeneration_;
    if (const auto callback = deviceEvents_.onDevicesChanged) callback();
    if (generation != operationGeneration_) return;
    if (const auto callback = backendEvents_.onCapabilitiesChanged) callback(capabilities());
}

void QmmpAudioPlayer::updateFormatFromCore() {
    if (!core_) return;
    const AudioParameters parameters = core_->audioParameters();
    domain::AudioFormatInfo info = audioFormat_.value_or(domain::AudioFormatInfo{});
    info.codec = utf8(core_->trackInfo().value(Qmmp::FORMAT_NAME));
    info.sampleRate = static_cast<std::int32_t>(parameters.sampleRate());
    info.channels = parameters.channels();
    info.bitrate = core_->bitrate();
    if (!info.codec.empty() || info.sampleRate > 0 || info.channels > 0 || info.bitrate > 0)
        setFormat(std::move(info));
}

void QmmpAudioPlayer::setState(domain::PlaybackState value) {
    if (state_ == value) return;
    state_ = value;
    if (const auto callback = events_.onStateChanged) callback(value);
}

void QmmpAudioPlayer::setError(std::optional<domain::PlaybackError> value) {
    if (lastError_ == value) return;
    lastError_ = std::move(value);
    if (const auto callback = events_.onErrorChanged) callback(lastError_);
}

void QmmpAudioPlayer::setFormat(std::optional<domain::AudioFormatInfo> value) {
    if (audioFormat_ == value) return;
    audioFormat_ = std::move(value);
    if (const auto callback = events_.onAudioFormatChanged) callback(audioFormat_);
}

void QmmpAudioPlayer::setSeekable(bool value) {
    if (seekable_ == value) return;
    seekable_ = value;
    if (const auto callback = events_.onSeekableChanged) callback(value);
}

void QmmpAudioPlayer::notifyDuration() {
    if (const auto callback = events_.onDurationChanged) callback(duration());
}

} // namespace listenfree::media

namespace listenfree::media {
void QmmpAudioPlayer::setEqualizer(bool enabled, const std::vector<double>& gains, double preampDb, bool autoHeadroom) {
    QSettings().setValue("Equalizer/unityGain", true);
    EqSettings settings(EqSettings::EQ_BANDS_10);
    settings.setEnabled(enabled);
    double peak = 0;
    for (int i = 0; i < 10 && i < static_cast<int>(gains.size()); ++i) {
        const double gain = std::clamp(gains[i], -12.0, 12.0);
        settings.setGain(i, gain);
        peak = std::max(peak, gain);
    }
    settings.setPreamp(std::clamp(preampDb, -12.0, 12.0) - (autoHeadroom ? peak : 0.0));
    if (core_) core_->setEqSettings(settings);
}
bool QmmpAudioPlayer::setSoundEffects(const QVariantMap& parameters) {
    auto* factory = Effect::findFactory("listenfree_sound");
    auto* object = dynamic_cast<QObject*>(factory);
    if (!object || !QMetaObject::invokeMethod(object, "setParameters", Qt::DirectConnection,
                                             Q_ARG(QVariantMap, parameters))) return false;
    // Keep the tiny bypass instance until playback ends. Qmmp 2.4 removes a
    // live effect from its list without destroying it; repeated toggles leak.
    // No timers, FFTs or PCM work are performed by our disabled instance.
    // Register before playback even in bypass, so changing a setting mid-song
    // cannot append this effect after Crossfade and change the DSP order.
    if (!Effect::isEnabled(factory)) Effect::setEnabled(factory, true);
    return true;
}
bool QmmpAudioPlayer::prepareNext(const domain::PlaybackItem& item) {
    if (!core_ || prepared_ || pendingPrimary_) return false;
    // Use the same canonical local path as open(): Qmmp's extension matching
    // treats Windows backslashes as pattern escapes during decoder selection.
    const QString url=item.resolvedUrl ? fromUtf8(*item.resolvedUrl) : item.track.localPath ? QFileInfo(fromUtf8(*item.track.localPath)).absoluteFilePath() : QString{};
    if (url.isEmpty()) return false;
    ++preparedRevision_;
    prepared_=item;
    if (!core_->play(url,true)) { prepared_.reset(); return false; }
    return true;
}
void QmmpAudioPlayer::cancelPrepared() {
    // Before the engine thread starts, its first decoder still occupies the
    // pending queue. Only cancel when this adapter actually queued a successor.
    if (!prepared_ && !pendingPrimary_) return;
    if(prepared_ && core_)core_->cancelQueuedSource();
    // The decoder may already be B. Resolve ownership before cancelling or
    // seeking so no old delayed callback can subsequently replace the user intent.
    if(pendingPrimary_) commitPrimary();
    transitionRequested_=false;
    ++preparedRevision_;
    prepared_.reset();
}
void QmmpAudioPlayer::configureTransition(bool crossfade,int milliseconds) {
    if(!crossfade){transitionRequested_=false;mixedTrack_=false;}
    QSettings settings;settings.setValue("Crossfade/overlap",qBound(20,milliseconds,12000));
    settings.setValue("Crossfade/manualOnly",true);
    for (auto* factory : Effect::factories()) if (factory->properties().shortName=="crossfade") Effect::setEnabled(factory,crossfade);
}
}

namespace listenfree::media {
bool QmmpAudioPlayer::startPreparedTransition(int milliseconds, qint64 sourceEndMs) {
    const auto* effect = Effect::findFactory("crossfade");
    if (!effect || !Effect::isEnabled(effect)) return false;
    if (!(prepared_ && core_ && state_ == domain::PlaybackState::Playing)) return false;
    feedbackEpoch_=core_->beginOutputFeedback();
    outgoingDuration_=duration();
    if (!(sourceEndMs>=0 ? core_->finishCurrentAt(sourceEndMs,milliseconds) : core_->finishCurrentAfter(milliseconds))) return false;
    outgoingEnd_=std::min(outgoingDuration_.count(),core_->transitionSourceEnd());
    transitionRequested_=true;
    return true;
}
}

namespace listenfree::media {
bool QmmpAudioPlayer::mixing() const {
    // An accepted source-time plan includes the outgoing lead-in. Keep the
    // indicator continuous while the first incoming DSP block publishes its length.
    return core_ && state_==domain::PlaybackState::Playing &&
        (transitionRequested_ || pendingPrimary_ || (mixedTrack_ &&
            (position_.count()==0 || position_.count()<core_->crossfadeDuration())));
}
}

namespace listenfree::media {
void QmmpAudioPlayer::resetPrimaryFeedback() {
    pendingPrimary_.reset(); pendingSource_.clear(); feedbackEpoch_=0; primaryEpoch_=0;
    outputClock_=false; incomingPosition_=0;
}
void QmmpAudioPlayer::commitPrimary() {
    if (!pendingPrimary_) return;
    const auto item=std::move(*pendingPrimary_); pendingPrimary_.reset();
    source_=std::exchange(pendingSource_,QString{});
    sourceIsNetwork_=source_.startsWith("http");
    metadataDuration_=core_->duration()>0 ? std::chrono::milliseconds(core_->duration()) : item.track.duration;
    position_=std::chrono::milliseconds(incomingPosition_);
    outputClock_=mixedTrack_; primaryEpoch_=feedbackEpoch_;
    // All consumers change identity through this single handoff; B is already
    // ~0.8 seconds into the same four/six-second overlap, never restarted at zero.
    emit preparedStarted();
    notifyDuration();
    updateFormatFromCore();
}
}
