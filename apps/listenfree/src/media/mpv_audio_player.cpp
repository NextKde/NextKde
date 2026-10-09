#include "media/mpv_audio_player.h"

#include <mpv/client.h>

#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <deque>
#include <memory>
#include <unordered_map>
#include <utility>
#include <vector>

namespace listenfree::media {

namespace {

template <typename Callback, typename... Arguments>
void invokeCallback(const Callback& callback, Arguments&&... arguments) {
    auto snapshot = callback;
    if (snapshot) snapshot(std::forward<Arguments>(arguments)...);
}

QString takeProperty(mpv_handle* context, const char* name) {
    char* value = mpv_get_property_string(context, name);
    if (!value) return {};
    const QString result = QString::fromUtf8(value);
    mpv_free(value);
    return result;
}

QString sourceString(const domain::PlaybackItem& item) {
    if (item.resolvedUrl && !item.resolvedUrl->empty()) {
        return QString::fromStdString(*item.resolvedUrl);
    }
    if (item.track.localPath && !item.track.localPath->empty()) {
        return QUrl::fromLocalFile(
                   QFileInfo(QString::fromStdString(*item.track.localPath)).absoluteFilePath())
            .toString(QUrl::FullyEncoded);
    }
    if (item.track.remoteUrl && !item.track.remoteUrl->empty()) {
        return QString::fromStdString(*item.track.remoteUrl);
    }
    return {};
}

bool isRemote(const QString& source) {
    const auto scheme = QUrl(source).scheme().toLower();
    return scheme == QStringLiteral("http") || scheme == QStringLiteral("https") ||
           scheme == QStringLiteral("icy");
}

} // namespace

class MpvAudioPlayer::Impl final {
    enum class CommandType { Load, Stop, Pause, Seek, Volume, Mute, Effects, Device };
    struct PendingCommand {
        CommandType type;
        std::uint64_t generation;
        std::uint64_t id{0};
        std::vector<QByteArray> arguments;
    };
    struct PendingStart {
        std::uint64_t commandId;
        std::uint64_t generation;
    };

public:
    explicit Impl(MpvAudioPlayer& owner) : owner_(owner) {
        context_ = mpv_create();
        if (!context_) return;

        // Keep the core isolated from the user's mpv configuration.  The
        // default paused state preserves IAudioPlayer's open-then-play
        // contract while libmpv supplies mature decoding, WASAPI and filters.
        bool configured = true;
        configured &= setOption("terminal", "no");
        configured &= setOption("config", "no");
        configured &= setOption("video", "no");
        configured &= setOption("ao", "wasapi");
        configured &= setOption("audio-exclusive", "no");
        configured &= setOption("pause", "yes");
        configured &= setOption("idle", "yes");
        configured &= setOption("af", "lavfi=[equalizer=f=60:t=q:w=1:g=0]");
        const int initializeResult = configured ? mpv_initialize(context_) : MPV_ERROR_OPTION_ERROR;
        if (!configured || initializeResult < 0) {
            mpv_terminate_destroy(context_);
            context_ = nullptr;
            return;
        }

        owner_.available_ = true;
        observe(1, "time-pos", MPV_FORMAT_DOUBLE);
        observe(2, "duration", MPV_FORMAT_DOUBLE);
        observe(3, "pause", MPV_FORMAT_FLAG);
        observe(4, "seekable", MPV_FORMAT_FLAG);
        observe(5, "volume", MPV_FORMAT_DOUBLE);
        observe(6, "mute", MPV_FORMAT_FLAG);
        observe(7, "audio-device", MPV_FORMAT_STRING);
        observe(8, "audio-device-list", MPV_FORMAT_STRING);

        wakeup_ = std::make_shared<WakeupState>();
        wakeup_->owner = &owner_;
        mpv_set_wakeup_callback(context_, &Impl::wakeup, wakeup_.get());
    }

    ~Impl() {
        if (!context_) return;
        wakeup_->active.store(false, std::memory_order_release);
        mpv_set_wakeup_callback(context_, nullptr, nullptr);
        // This is the only owner of the libmpv handle.  terminate_destroy
        // guarantees that the decoder/audio worker threads are gone before
        // the QObject's deterministic destruction completes.
        mpv_terminate_destroy(context_);
        context_ = nullptr;
    }

    void open(const QString& source, std::uint64_t generation) {
        if (!context_ || source.isEmpty()) return;
        source_ = source;
        discardQueuedPlaybackCommands();
        if (!enqueue(CommandType::Load, generation,
                     {QByteArrayLiteral("loadfile"), source.toUtf8(), QByteArrayLiteral("replace")})) {
            owner_.setError({isRemote(source) ? domain::PlaybackErrorCode::Network
                                              : domain::PlaybackErrorCode::OpenFailed,
                             QStringLiteral("mpv.loadfile.failed").toStdString(), isRemote(source)});
            return;
        }
        // --pause=yes is an option, but explicitly restore it for every new
        // item because a previous play() changed the runtime property.
        enqueue(CommandType::Pause, generation,
                {QByteArrayLiteral("set"), QByteArrayLiteral("pause"), QByteArrayLiteral("yes")});
    }

    void clear() {
        if (!context_) return;
        discardQueuedPlaybackCommands();
        enqueue(CommandType::Stop, owner_.sourceGeneration_, {QByteArrayLiteral("stop")});
        enqueue(CommandType::Pause, owner_.sourceGeneration_,
                {QByteArrayLiteral("set"), QByteArrayLiteral("pause"), QByteArrayLiteral("yes")});
    }

    void play() {
        if (!context_) return;
        enqueue(CommandType::Pause, owner_.sourceGeneration_,
                {QByteArrayLiteral("set"), QByteArrayLiteral("pause"), QByteArrayLiteral("no")});
    }

    void pause() {
        if (!context_) return;
        enqueue(CommandType::Pause, owner_.sourceGeneration_,
                {QByteArrayLiteral("set"), QByteArrayLiteral("pause"), QByteArrayLiteral("yes")});
    }

    void stop() {
        if (!context_) return;
        discardQueuedPlaybackCommands();
        enqueue(CommandType::Stop, owner_.sourceGeneration_, {QByteArrayLiteral("stop")});
        enqueue(CommandType::Pause, owner_.sourceGeneration_,
                {QByteArrayLiteral("set"), QByteArrayLiteral("pause"), QByteArrayLiteral("yes")});
    }

    void seek(std::chrono::milliseconds position) {
        if (!context_) return;
        const auto clampedMs = std::max<std::int64_t>(0, position.count());
        const double secondsValue = static_cast<double>(clampedMs) / 1000.0;
        const QByteArray seconds = QByteArray::number(secondsValue, 'f', 3);
        enqueue(CommandType::Seek, owner_.sourceGeneration_,
                {QByteArrayLiteral("seek"), seconds, QByteArrayLiteral("absolute+exact")});
    }

    void setVolume(float normalized) {
        if (!context_) return;
        const QByteArray value = QByteArray::number(std::clamp(normalized, 0.0F, 1.0F) * 100.0F,
                                                    'f', 3);
        enqueue(CommandType::Volume, owner_.sourceGeneration_,
                {QByteArrayLiteral("set"), QByteArrayLiteral("volume"), value});
    }

    void setMuted(bool muted) {
        if (!context_) return;
        enqueue(CommandType::Mute, owner_.sourceGeneration_,
                {QByteArrayLiteral("set"), QByteArrayLiteral("mute"),
                 muted ? QByteArrayLiteral("yes") : QByteArrayLiteral("no")});
    }

    bool setEffects(const std::array<float, 10>& gains, float reverb) {
        if (!context_) return false;
        static constexpr std::array<int, 10> frequencies{60, 120, 250, 500, 1000,
                                                         2000, 4000, 8000, 12000, 16000};
        QStringList filters;
        filters.reserve(11);
        for (std::size_t index = 0; index < gains.size(); ++index) {
            filters.push_back(QStringLiteral("equalizer=f=%1:t=q:w=1:g=%2")
                                  .arg(frequencies[index])
                                  .arg(gains[index], 0, 'f', 3));
        }
        if (reverb > 0.001F) {
            filters.push_back(QStringLiteral("aecho=1:1:60:%1").arg(reverb, 0, 'f', 3));
        }
        const auto value = QStringLiteral("lavfi=[%1]").arg(filters.join(QLatin1Char(','))).toUtf8();
        return enqueue(CommandType::Effects, owner_.sourceGeneration_,
                       {QByteArrayLiteral("set"), QByteArrayLiteral("af"), value});
    }

    std::vector<application::AudioDeviceInfo> devices() const {
        std::vector<application::AudioDeviceInfo> result;
        if (!context_) return result;
        const auto json = takeProperty(context_, "audio-device-list");
        const auto document = QJsonDocument::fromJson(json.toUtf8());
        if (!document.isArray()) return result;
        const auto selected = selectedDeviceId();
        for (const auto value : document.array()) {
            if (!value.isObject()) continue;
            const auto object = value.toObject();
            const auto id = object.value(QStringLiteral("name")).toString();
            if (id.isEmpty() || (id != QStringLiteral("auto") &&
                                 !id.startsWith(QStringLiteral("wasapi/")))) {
                continue;
            }
            result.push_back({id.toStdString(),
                              object.value(QStringLiteral("description")).toString().toStdString(),
                              id == QStringLiteral("auto"), id.toStdString() == selected});
        }
        return result;
    }

    std::string selectedDeviceId() const {
        if (!context_) return "auto";
        const auto value = takeProperty(context_, "audio-device");
        return value.isEmpty() ? std::string("auto") : value.toStdString();
    }

    bool select(std::string_view id) {
        if (!context_ || id.empty()) return false;
        const QByteArray requested(id.data(), static_cast<qsizetype>(id.size()));
        const auto availableDevices = devices();
        if (std::none_of(availableDevices.cbegin(), availableDevices.cend(),
                         [&requested](const application::AudioDeviceInfo& device) {
                             return QByteArray::fromStdString(device.id) == requested;
                         })) {
            return false;
        }
        return enqueue(CommandType::Device, owner_.sourceGeneration_,
                       {QByteArrayLiteral("set"), QByteArrayLiteral("audio-device"), requested});
    }

    void refresh() { emitDeviceChanged(); }

private:
    struct WakeupState {
        std::atomic_bool active{true};
        std::atomic_bool queued{false};
        MpvAudioPlayer* owner{nullptr};
    };

    static void wakeup(void* opaque) {
        auto* state = static_cast<WakeupState*>(opaque);
        if (!state || !state->active.load(std::memory_order_acquire) ||
            state->queued.exchange(true, std::memory_order_acq_rel)) {
            return;
        }
        auto* owner = state->owner;
        QMetaObject::invokeMethod(owner, [owner] {
            if (!owner->impl_ || !owner->impl_->wakeup_) return;
            owner->impl_->wakeup_->queued.store(false, std::memory_order_release);
            owner->impl_->drainEvents();
        }, Qt::QueuedConnection);
    }

    static bool coalescible(CommandType type) noexcept {
        return type == CommandType::Seek || type == CommandType::Volume ||
               type == CommandType::Mute || type == CommandType::Effects ||
               type == CommandType::Device;
    }

    bool enqueue(CommandType type, std::uint64_t generation,
                 std::vector<QByteArray> arguments) {
        if (!context_) return false;
        if (coalescible(type) && !commandQueue_.empty() &&
            commandQueue_.back().type == type &&
            commandQueue_.back().generation == generation) {
            commandQueue_.back().arguments = std::move(arguments);
            return true;
        }
        if (commandQueue_.size() >= 128) return false;
        commandQueue_.push_back({type, generation, 0, std::move(arguments)});
        dispatchNextCommand();
        return true;
    }

    void discardQueuedPlaybackCommands() {
        commandQueue_.clear();
    }

    void dispatchNextCommand() {
        if (!context_ || inFlightCommand_ || commandQueue_.empty()) return;
        inFlightCommand_ = std::move(commandQueue_.front());
        commandQueue_.pop_front();
        inFlightCommand_->id = ++commandId_;
        std::vector<const char*> arguments;
        arguments.reserve(inFlightCommand_->arguments.size() + 1);
        for (const auto& argument : inFlightCommand_->arguments) {
            arguments.push_back(argument.constData());
        }
        arguments.push_back(nullptr);
        const int result = mpv_command_async(context_, inFlightCommand_->id, arguments.data());
        if (result >= 0) {
            if (inFlightCommand_->type == CommandType::Load) {
                pendingStarts_.push_back({inFlightCommand_->id, inFlightCommand_->generation});
            }
            return;
        }
        const auto failed = std::move(*inFlightCommand_);
        inFlightCommand_.reset();
        publishCommandFailure(failed, result);
        dispatchNextCommand();
    }

    void handleCommandReply(const mpv_event* event) {
        if (!event || !inFlightCommand_ || event->reply_userdata != inFlightCommand_->id) return;
        const auto completed = std::move(*inFlightCommand_);
        inFlightCommand_.reset();
        if (event->error < 0) {
            if (completed.type == CommandType::Load) {
                std::erase_if(pendingStarts_, [&completed](const PendingStart& pending) {
                    return pending.commandId == completed.id;
                });
            }
            publishCommandFailure(completed, event->error);
        }
        dispatchNextCommand();
    }

    void publishCommandFailure(const PendingCommand& command, int error) {
        if (command.generation != owner_.sourceGeneration_ || owner_.source_.isEmpty()) return;
        const bool remote = isRemote(source_);
        const auto code = command.type == CommandType::Load
                              ? (remote ? domain::PlaybackErrorCode::Network
                                        : domain::PlaybackErrorCode::OpenFailed)
                              : domain::PlaybackErrorCode::Internal;
        owner_.setError({code,
                         QStringLiteral("mpv.command.%1: %2")
                             .arg(static_cast<int>(command.type))
                             .arg(QString::fromUtf8(mpv_error_string(error)))
                             .toStdString(),
                         remote});
    }

    bool setOption(const char* name, const char* value) {
        const int result = mpv_set_option_string(context_, name, value);
        if (result < 0) {
            std::fprintf(stderr, "libmpv option %s=%s failed: %d (%s)\n", name, value, result,
                         mpv_error_string(result));
        }
        return result >= 0;
    }

    void observe(std::uint64_t id, const char* name, mpv_format format) {
        mpv_observe_property(context_, id, name, format);
    }

    void drainEvents() {
        if (!context_) return;
        for (int count = 0; count < 64; ++count) {
            const mpv_event* event = mpv_wait_event(context_, 0.0);
            if (!event || event->event_id == MPV_EVENT_NONE) break;
            switch (event->event_id) {
            case MPV_EVENT_COMMAND_REPLY:
                handleCommandReply(event);
                break;
            case MPV_EVENT_START_FILE: {
                const auto* started = static_cast<const mpv_event_start_file*>(event->data);
                const auto generation = pendingStarts_.empty()
                                            ? std::uint64_t{0}
                                            : pendingStarts_.front().generation;
                if (!pendingStarts_.empty()) pendingStarts_.pop_front();
                if (started) {
                    entryGenerations_[started->playlist_entry_id] = generation;
                    activePlaylistEntryId_ = started->playlist_entry_id;
                    activeGeneration_ = generation;
                }
                if (!isCurrentPlaybackEvent()) break;
                owner_.opening_ = true;
                owner_.setState(domain::PlaybackState::Loading);
                break;
            }
            case MPV_EVENT_FILE_LOADED:
                if (!isCurrentPlaybackEvent()) break;
                {
                const auto operation = owner_.operationGeneration_;
                const auto generation = activeGeneration_;
                owner_.opening_ = false;
                updateAudioFormat();
                if (owner_.operationGeneration_ != operation ||
                    owner_.sourceGeneration_ != generation) break;
                updateStaticProperties();
                if (owner_.operationGeneration_ != operation ||
                    owner_.sourceGeneration_ != generation) break;
                owner_.setState(owner_.playRequested_ ? domain::PlaybackState::Playing
                                                       : domain::PlaybackState::Stopped);
                break;
                }
            case MPV_EVENT_END_FILE:
                handleEndFile(static_cast<const mpv_event_end_file*>(event->data));
                break;
            case MPV_EVENT_PROPERTY_CHANGE:
                handleProperty(event->reply_userdata,
                               static_cast<const mpv_event_property*>(event->data));
                break;
            case MPV_EVENT_SHUTDOWN:
                owner_.available_ = false;
                owner_.setError({domain::PlaybackErrorCode::Internal, "mpv.shutdown", true});
                return;
            default:
                break;
            }
        }
    }

    void handleEndFile(const mpv_event_end_file* end) {
        if (!end) return;
        const auto found = entryGenerations_.find(end->playlist_entry_id);
        const auto generation = found == entryGenerations_.end() ? std::uint64_t{0} : found->second;
        if (found != entryGenerations_.end()) entryGenerations_.erase(found);
        if (activePlaylistEntryId_ == end->playlist_entry_id) {
            activePlaylistEntryId_ = 0;
            activeGeneration_ = 0;
        }
        if (generation == 0 || generation != owner_.sourceGeneration_ || owner_.source_.isEmpty()) return;
        const auto operation = owner_.operationGeneration_;
        owner_.opening_ = false;
        if (end->reason == MPV_END_FILE_REASON_ERROR) {
            const bool remote = isRemote(source_);
            const auto code = end->error == MPV_ERROR_UNKNOWN_FORMAT
                                  ? domain::PlaybackErrorCode::Unsupported
                                  : (remote ? domain::PlaybackErrorCode::Network
                                            : domain::PlaybackErrorCode::OpenFailed);
            owner_.setError({code,
                             QString::fromUtf8(mpv_error_string(end->error)).toStdString(), remote});
            return;
        }
        owner_.playRequested_ = false;
        owner_.setState(domain::PlaybackState::Stopped);
        if (owner_.operationGeneration_ != operation || generation != owner_.sourceGeneration_) return;
        if (end->reason == MPV_END_FILE_REASON_EOF && !owner_.stoppedByUser_) {
            owner_.notifyFinished();
        }
    }

    void handleProperty(std::uint64_t replyUserdata, const mpv_event_property* property) {
        if (!property || !property->name || !property->data) return;
        switch (replyUserdata) {
        case 1:
            if (isCurrentPlaybackEvent() && property->format == MPV_FORMAT_DOUBLE) {
                const auto value = *static_cast<double*>(property->data);
                owner_.setPosition(std::chrono::milliseconds(static_cast<std::int64_t>(
                    std::llround(std::max(0.0, value) * 1000.0))));
            }
            break;
        case 2:
            if (isCurrentPlaybackEvent() && property->format == MPV_FORMAT_DOUBLE) {
                const auto value = *static_cast<double*>(property->data);
                owner_.setDuration(std::chrono::milliseconds(static_cast<std::int64_t>(
                    std::llround(std::max(0.0, value) * 1000.0))));
            }
            break;
        case 3:
            if (property->format == MPV_FORMAT_FLAG) {
                const bool paused = *static_cast<int*>(property->data) != 0;
                if (isCurrentPlaybackEvent() && !owner_.opening_ && !owner_.stoppedByUser_) {
                    owner_.setState(!owner_.playRequested_ ? domain::PlaybackState::Stopped
                                                           : (paused ? domain::PlaybackState::Paused
                                                                     : domain::PlaybackState::Playing));
                }
            }
            break;
        case 4:
            if (isCurrentPlaybackEvent() && property->format == MPV_FORMAT_FLAG) {
                owner_.setSeekable(*static_cast<int*>(property->data) != 0);
            }
            break;
        case 5:
            if (property->format == MPV_FORMAT_DOUBLE) owner_.setVolumeValue(
                static_cast<float>(*static_cast<double*>(property->data) / 100.0));
            break;
        case 6:
            if (property->format == MPV_FORMAT_FLAG) owner_.setMutedValue(*static_cast<int*>(property->data) != 0);
            break;
        case 7:
            emitDeviceChanged();
            break;
        case 8:
            emitDeviceChanged();
            break;
        default:
            break;
        }
    }

    bool isCurrentPlaybackEvent() const noexcept {
        return !owner_.source_.isEmpty() && activeGeneration_ != 0 &&
               activeGeneration_ == owner_.sourceGeneration_;
    }

    void updateStaticProperties() {
        if (!context_) return;
        int flag = 0;
        if (mpv_get_property(context_, "seekable", MPV_FORMAT_FLAG, &flag) >= 0) owner_.setSeekable(flag != 0);
        if (auto value = takeProperty(context_, "duration"); !value.isEmpty()) {
            bool ok = false;
            const auto seconds = value.toDouble(&ok);
            if (ok) owner_.setDuration(std::chrono::milliseconds(static_cast<std::int64_t>(std::llround(seconds * 1000.0))));
        }
    }

    void updateAudioFormat() {
        if (!context_) return;
        domain::AudioFormatInfo info;
        info.codec = takeProperty(context_, "current-tracks/audio/codec").toStdString();
        bool ok = false;
        info.sampleRate = takeProperty(context_, "audio-params/samplerate").toInt(&ok);
        if (!ok) info.sampleRate = 0;
        info.channels = takeProperty(context_, "audio-params/channel-count").toInt(&ok);
        if (!ok) info.channels = 0;
        info.bitrate = takeProperty(context_, "audio-bitrate").toInt(&ok);
        if (!ok) info.bitrate = 0;
        if (!info.codec.empty() || info.sampleRate > 0 || info.channels > 0) owner_.setAudioFormat(info);
    }

    void emitDeviceChanged() {
        emit owner_.devicesChanged();
        invokeCallback(owner_.deviceEvents_.onDevicesChanged);
        emit owner_.selectedDeviceChanged();
        invokeCallback(owner_.deviceEvents_.onSelectedDeviceChanged, selectedDeviceId());
    }

    MpvAudioPlayer& owner_;
    mpv_handle* context_{nullptr};
    std::shared_ptr<WakeupState> wakeup_;
    QString source_;
    std::uint64_t commandId_{0};
    std::deque<PendingCommand> commandQueue_;
    std::optional<PendingCommand> inFlightCommand_;
    std::deque<PendingStart> pendingStarts_;
    std::unordered_map<std::int64_t, std::uint64_t> entryGenerations_;
    std::int64_t activePlaylistEntryId_{0};
    std::uint64_t activeGeneration_{0};
};

MpvAudioPlayer::MpvAudioPlayer(QObject* parent) : QObject(parent), impl_(std::make_unique<Impl>(*this)) {}

MpvAudioPlayer::~MpvAudioPlayer() {
    events_ = {};
    backendEvents_ = {};
    deviceEvents_ = {};
    impl_.reset();
}

QString MpvAudioPlayer::stateName() const {
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

void MpvAudioPlayer::open(const domain::PlaybackItem& item) {
    const auto source = sourceString(item);
    if (source.isEmpty()) {
        clear();
        return;
    }
    const auto operation = ++operationGeneration_;
    const auto generation = ++sourceGeneration_;
    opening_ = true;
    stoppedByUser_ = false;
    playRequested_ = false;
    endNotified_ = false;
    setPosition(std::chrono::milliseconds(0));
    if (operationGeneration_ != operation) return;
    setDuration(std::chrono::milliseconds(0));
    if (operationGeneration_ != operation) return;
    setSeekable(false);
    if (operationGeneration_ != operation) return;
    setAudioFormat(std::nullopt);
    if (operationGeneration_ != operation) return;
    clearError();
    if (operationGeneration_ != operation) return;
    const auto scheme = QUrl(source).scheme().toLower();
    if (!scheme.isEmpty() && scheme != QStringLiteral("file") &&
        scheme != QStringLiteral("http") && scheme != QStringLiteral("https") &&
        scheme != QStringLiteral("icy")) {
        impl_->clear();
        source_.clear();
        opening_ = false;
        setError({domain::PlaybackErrorCode::Unsupported, "media.unsupported-url-scheme", false});
        return;
    }
    source_ = QUrl::fromUserInput(source);
    if (!available_) {
        opening_ = false;
        setError({domain::PlaybackErrorCode::Internal, "mpv.initialization-failed", true});
        return;
    }
    setState(domain::PlaybackState::Loading);
    if (operationGeneration_ != operation || generation != sourceGeneration_) return;
    impl_->open(source, generation);
}

void MpvAudioPlayer::open(const QUrl& url) {
    domain::PlaybackItem item;
    if (url.isLocalFile()) item.track.localPath = url.toLocalFile().toStdString();
    else item.resolvedUrl = url.toString().toStdString();
    open(item);
}

void MpvAudioPlayer::clear() {
    const auto operation = ++operationGeneration_;
    ++sourceGeneration_;
    impl_->clear();
    source_.clear();
    opening_ = false;
    stoppedByUser_ = false;
    playRequested_ = false;
    endNotified_ = false;
    setPosition(std::chrono::milliseconds(0));
    if (operationGeneration_ != operation) return;
    setDuration(std::chrono::milliseconds(0));
    if (operationGeneration_ != operation) return;
    setSeekable(false);
    if (operationGeneration_ != operation) return;
    setAudioFormat(std::nullopt);
    if (operationGeneration_ != operation) return;
    clearError();
    if (operationGeneration_ != operation) return;
    setState(domain::PlaybackState::Idle);
}

void MpvAudioPlayer::play() {
    ++operationGeneration_;
    if (source_.isEmpty()) return;
    const bool reload = endNotified_ || stoppedByUser_;
    stoppedByUser_ = false;
    playRequested_ = true;
    if (reload) {
        endNotified_ = false;
        opening_ = true;
        const auto generation = ++sourceGeneration_;
        setPosition(std::chrono::milliseconds(0));
        setState(domain::PlaybackState::Loading);
        impl_->open(source_.toString(QUrl::FullyEncoded), generation);
    }
    impl_->play();
}

void MpvAudioPlayer::pause() {
    ++operationGeneration_;
    if (source_.isEmpty()) return;
    impl_->pause();
}

void MpvAudioPlayer::stop() {
    ++operationGeneration_;
    if (source_.isEmpty()) {
        setState(domain::PlaybackState::Idle);
        return;
    }
    stoppedByUser_ = true;
    playRequested_ = false;
    opening_ = false;
    impl_->stop();
    setState(domain::PlaybackState::Stopped);
}

void MpvAudioPlayer::seek(std::chrono::milliseconds value) {
    ++operationGeneration_;
    if (source_.isEmpty()) return;
    impl_->seek(std::clamp(value, std::chrono::milliseconds(0), duration_));
}

void MpvAudioPlayer::seek(qint64 value) { seek(std::chrono::milliseconds(value)); }

void MpvAudioPlayer::setVolume(float value) {
    setVolumeValue(std::clamp(value, 0.0F, 1.0F));
    impl_->setVolume(value);
}
void MpvAudioPlayer::setMuted(bool value) {
    setMutedValue(value);
    impl_->setMuted(value);
}

std::uint32_t MpvAudioPlayer::capabilities() const noexcept {
    if (!available_) return 0U;
    using application::PlaybackCapability;
    return application::capabilityMask(PlaybackCapability::LocalFile) |
           application::capabilityMask(PlaybackCapability::HttpStream) |
           application::capabilityMask(PlaybackCapability::Seek) |
           application::capabilityMask(PlaybackCapability::Volume) |
           application::capabilityMask(PlaybackCapability::Mute) |
           application::capabilityMask(PlaybackCapability::DeviceSelection) |
           application::capabilityMask(PlaybackCapability::Equalizer) |
           application::capabilityMask(PlaybackCapability::HighResolution);
}

std::vector<application::AudioDeviceInfo> MpvAudioPlayer::devices() const { return impl_->devices(); }
std::string MpvAudioPlayer::selectedDeviceId() const { return impl_->selectedDeviceId(); }
bool MpvAudioPlayer::select(std::string_view id) { return impl_->select(id); }
void MpvAudioPlayer::refresh() { impl_->refresh(); }
bool MpvAudioPlayer::setBandGain(std::size_t band, float gainDb) {
    if (band >= equalizerGains_.size() || !std::isfinite(gainDb)) return false;
    auto candidate = equalizerGains_;
    candidate[band] = std::clamp(gainDb, -24.0F, 24.0F);
    if (!impl_->setEffects(candidate, reverbAmount_)) return false;
    equalizerGains_ = candidate;
    return true;
}
bool MpvAudioPlayer::setReverb(float amount) {
    if (!std::isfinite(amount)) return false;
    const auto candidate = std::clamp(amount, 0.0F, 1.0F);
    if (!impl_->setEffects(equalizerGains_, candidate)) return false;
    reverbAmount_ = candidate;
    return true;
}
bool MpvAudioPlayer::setEqualizerBand(int band, float gainDb) {
    return band < 0 ? false : setBandGain(static_cast<std::size_t>(band), gainDb);
}
bool MpvAudioPlayer::setReverbAmount(float amount) { return setReverb(amount); }
QStringList MpvAudioPlayer::qtDeviceIds() const {
    QStringList result;
    for (const auto& device : devices()) result.push_back(QString::fromStdString(device.id));
    return result;
}
bool MpvAudioPlayer::selectDevice(const QString& id) { return select(id.toStdString()); }

void MpvAudioPlayer::setState(domain::PlaybackState state) {
    if (state_ == state) return;
    state_ = state;
    emit stateChanged();
    invokeCallback(events_.onStateChanged, state_);
}

void MpvAudioPlayer::setError(domain::PlaybackError error) {
    const auto published = std::move(error);
    lastError_ = published;
    setState(domain::PlaybackState::Error);
    if (!lastError_ || *lastError_ != published || state_ != domain::PlaybackState::Error) return;
    emit errorChanged(QString::fromStdString(published.message));
    if (!lastError_ || *lastError_ != published || state_ != domain::PlaybackState::Error) return;
    invokeCallback(events_.onErrorChanged, std::optional<domain::PlaybackError>{published});
}

void MpvAudioPlayer::clearError() {
    if (!lastError_) return;
    lastError_.reset();
    emit errorChanged({});
    invokeCallback(events_.onErrorChanged, std::optional<domain::PlaybackError>{});
}

void MpvAudioPlayer::setPosition(std::chrono::milliseconds value) {
    if (position_ == value) return;
    position_ = value;
    emit positionChanged();
    invokeCallback(events_.onPositionChanged, position_);
}

void MpvAudioPlayer::setDuration(std::chrono::milliseconds value) {
    if (duration_ == value) return;
    duration_ = value;
    emit durationChanged();
    invokeCallback(events_.onDurationChanged, duration_);
}

void MpvAudioPlayer::setSeekable(bool value) {
    if (seekable_ == value) return;
    seekable_ = value;
    emit seekableChanged();
    invokeCallback(events_.onSeekableChanged, seekable_);
}

void MpvAudioPlayer::setVolumeValue(float value) {
    value = std::clamp(value, 0.0F, 1.0F);
    if (std::abs(volume_ - value) < 0.0005F) return;
    volume_ = value;
    emit volumeChanged(volume_);
    invokeCallback(events_.onVolumeChanged, volume_);
}

void MpvAudioPlayer::setMutedValue(bool value) {
    if (muted_ == value) return;
    muted_ = value;
    emit mutedChanged(muted_);
    invokeCallback(events_.onMutedChanged, muted_);
}

void MpvAudioPlayer::setAudioFormat(std::optional<domain::AudioFormatInfo> value) {
    if (audioFormat_ == value) return;
    audioFormat_ = std::move(value);
    emit audioFormatChanged();
    invokeCallback(events_.onAudioFormatChanged, audioFormat_);
}

void MpvAudioPlayer::notifyFinished() {
    if (endNotified_) return;
    endNotified_ = true;
    invokeCallback(events_.onFinished);
}

} // namespace listenfree::media
