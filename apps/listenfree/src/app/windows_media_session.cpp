// Public SMTC integration, following spmn/vlc-win10smtc's window binding,
// incremental updates and synchronous IStream thumbnail bridge. See
// docs/research/windows-media-session-2026-09-11.md for provenance.
#include <unknwn.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>
#include <systemmediatransportcontrolsinterop.h>
#include <shcore.h>
#include <shlwapi.h>
#include <shlobj.h>
#include <propkey.h>
#include <propvarutil.h>
#include "windows_media_session.h"
#include "qmlbridge/cover_image_provider.h"
#include <QFutureWatcher>
#include <QThreadPool>
#include <QWindow>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QtConcurrentRun>
#include <mutex>
#include <optional>

using namespace winrt::Windows::Media;
using namespace winrt::Windows::Storage::Streams;
using namespace winrt::Windows::Foundation;
namespace listenfree {
namespace {
winrt::hstring nativeText(const QString& text) { return winrt::hstring(text.toStdWString()); }
MediaPlaybackStatus status(const QString& state) {
    if (state == "Playing") return MediaPlaybackStatus::Playing;
    if (state == "Paused") return MediaPlaybackStatus::Paused;
    if (state == "Loading" || state == "Buffering") return MediaPlaybackStatus::Changing;
    return MediaPlaybackStatus::Stopped;
}
RandomAccessStreamReference thumbnailStream(const QByteArray& bytes) {
    winrt::com_ptr<IStream> memory;
    memory.attach(SHCreateMemStream(reinterpret_cast<const BYTE*>(bytes.constData()), UINT(bytes.size())));
    if (!memory) throw std::bad_alloc{};
    IRandomAccessStream stream{nullptr};
    winrt::check_hresult(CreateRandomAccessStreamOverStream(memory.get(), BSOS_DEFAULT,
        winrt::guid_of<IRandomAccessStream>(), winrt::put_abi(stream)));
    return RandomAccessStreamReference::CreateFromStream(stream);
}
QByteArray readThumbnail(const QString& source) {
    QImage pixels;
    if (source.startsWith("image://covers/")) {
        CoverImageProvider provider;
        pixels = provider.requestImage(source.mid(15), nullptr, {256, 256});
    } else {
        const QUrl url(source);
        QString path = url.isLocalFile() ? url.toLocalFile() : source;
        if (path.startsWith("qrc:/")) path.remove(0, 3);
        QImageReader reader(path);
        reader.setAutoTransform(true);
        const auto size = reader.size();
        if (size.width() > 256 || size.height() > 256)
            reader.setScaledSize(size.scaled(256, 256, Qt::KeepAspectRatio));
        pixels = reader.read();
    }
    if (pixels.isNull() || pixels.size() == QSize(1, 1)) return {};
    QByteArray bytes;
    QBuffer buffer(&bytes);
    buffer.open(QIODevice::WriteOnly);
    pixels.save(&buffer, "PNG");
    return bytes;
}
}
struct WindowsMediaSession::Impl {
    struct Callbacks { std::mutex mutex; WindowsMediaSession* target{}; };
    WindowsMediaSession* owner;
    std::shared_ptr<Callbacks> callbacks = std::make_shared<Callbacks>();
    SystemMediaTransportControls controls{nullptr};
    SystemMediaTransportControlsDisplayUpdater display{nullptr};
    winrt::event_token buttons{}, seeking{};
    bool apartment{}, ready{}, thumbnailBusy{};
    QString error, artwork, pendingArtwork;
    std::optional<State> pushed;
    QThreadPool pool;
    QFutureWatcher<QByteArray> imageJob;

    explicit Impl(WindowsMediaSession* target) : owner(target) {
        callbacks->target = target;
        pool.setMaxThreadCount(1);
        pool.setExpiryTimeout(2000);
        QObject::connect(&imageJob, &QFutureWatcherBase::finished, owner, [this] {
            auto future = imageJob.future();
            auto bytes = future.takeResult();
            thumbnailBusy = false;
            if (artwork != pendingArtwork) { startThumbnail(); return; }
            if (!bytes.isEmpty() && controls && pushed && pushed->hasTrack) {
                try { display.Thumbnail(thumbnailStream(bytes)); display.Update(); }
                catch (const winrt::hresult_error& e) { warn(e); }
            }
        });
    }
    ~Impl() {
        // WinRT delegates can arrive on RPC threads. Invalidate under the same
        // lock used when posting; Qt removes queued calls when owner is destroyed.
        { std::lock_guard lock(callbacks->mutex); callbacks->target = nullptr; }
        QObject::disconnect(&imageJob, nullptr, owner, nullptr);
        pool.waitForDone();
        if (controls) {
            try { if (buttons.value) controls.ButtonPressed(buttons); } catch (...) {}
            try { if (seeking.value) controls.PlaybackPositionChangeRequested(seeking); } catch (...) {}
            try { controls.IsEnabled(false); controls.PlaybackStatus(MediaPlaybackStatus::Closed); } catch (...) {}
        }
        display = nullptr;
        controls = nullptr;
        winrt::clear_factory_cache();
        if (apartment) winrt::uninit_apartment();
    }
    void warn(const winrt::hresult_error& e) {
        const auto message = QString::fromStdWString(std::wstring(e.message())) +
            QStringLiteral(" (0x%1)").arg(quint32(e.code().value), 8, 16, QLatin1Char('0'));
        if (message != error) qWarning().noquote() << "Windows media session:" << message;
        error = message;
    }
    void initialize(QWindow* window) {
        try {
            winrt::init_apartment(winrt::apartment_type::single_threaded);
            apartment = true;
            const auto interop = winrt::get_activation_factory<SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
            winrt::check_hresult(interop->GetForWindow(reinterpret_cast<HWND>(window->winId()),
                winrt::guid_of<SystemMediaTransportControls>(), winrt::put_abi(controls)));
            display = controls.DisplayUpdater();
            buttons = controls.ButtonPressed([state=callbacks](auto&&, const SystemMediaTransportControlsButtonPressedEventArgs& args) {
                std::optional<Button> button;
                switch (args.Button()) {
                case SystemMediaTransportControlsButton::Play: button = Play; break;
                case SystemMediaTransportControlsButton::Pause: button = Pause; break;
                case SystemMediaTransportControlsButton::Stop: button = Stop; break;
                case SystemMediaTransportControlsButton::Next: button = Next; break;
                case SystemMediaTransportControlsButton::Previous: button = Previous; break;
                default: return;
                }
                std::lock_guard lock(state->mutex);
                if (auto* target = state->target)
                    QMetaObject::invokeMethod(target, [target, button] { emit target->buttonRequested(*button); }, Qt::QueuedConnection);
            });
            seeking = controls.PlaybackPositionChangeRequested([state=callbacks](auto&&, const PlaybackPositionChangeRequestedEventArgs& args) {
                const qint64 milliseconds = std::chrono::duration_cast<std::chrono::milliseconds>(args.RequestedPlaybackPosition()).count();
                std::lock_guard lock(state->mutex);
                if (auto* target = state->target)
                    QMetaObject::invokeMethod(target, [target, milliseconds] { emit target->seekRequested(milliseconds); }, Qt::QueuedConnection);
            });
            controls.IsPlayEnabled(true);
            controls.IsPauseEnabled(true);
            controls.IsStopEnabled(true);
            controls.IsEnabled(false);
            ready = true;
        } catch (const winrt::hresult_error& e) { warn(e); }
    }
    void startThumbnail() {
        pendingArtwork = artwork;
        if (artwork.isEmpty()) return;
        const QUrl url(artwork);
        if (url.scheme() == "http" || url.scheme() == "https") {
            try { display.Thumbnail(RandomAccessStreamReference::CreateFromUri(Uri(nativeText(artwork)))); display.Update(); }
            catch (const winrt::hresult_error& e) { warn(e); }
            return;
        }
        // Only one local decode runs; fast track changes replace the pending key.
        thumbnailBusy = true;
        imageJob.setFuture(QtConcurrent::run(&pool, [source=artwork] { return readThumbnail(source); }));
    }
    void update(const State& state) {
        if (!ready) return;
        try {
            const bool opening = !pushed || !pushed->hasTrack;
            if (!state.hasTrack) {
                if (!opening) { controls.IsEnabled(false); display.ClearAll(); controls.PlaybackStatus(MediaPlaybackStatus::Closed); }
                artwork.clear(); pushed = state; return;
            }
            if (opening || state.previous != pushed->previous) controls.IsPreviousEnabled(state.previous);
            if (opening || state.next != pushed->next) controls.IsNextEnabled(state.next);
            const bool newArt = opening || state.artwork != pushed->artwork;
            if (opening || newArt || state.title != pushed->title || state.artist != pushed->artist || state.album != pushed->album) {
                display.Type(MediaPlaybackType::Music);
                const auto music = display.MusicProperties();
                music.Title(nativeText(state.title));
                music.Artist(nativeText(state.artist));
                music.AlbumTitle(nativeText(state.album));
                if (newArt) display.Thumbnail(nullptr);
                display.Update();
            }
            if (opening || state.position != pushed->position || state.duration != pushed->duration ||
                state.seekable != pushed->seekable || state.playback != pushed->playback) {
                SystemMediaTransportControlsTimelineProperties timeline;
                const auto duration = state.seekable ? qMax<qint64>(0, state.duration) : 0;
                timeline.StartTime(TimeSpan::zero()); timeline.MinSeekTime(TimeSpan::zero());
                timeline.EndTime(std::chrono::milliseconds(duration)); timeline.MaxSeekTime(std::chrono::milliseconds(duration));
                timeline.Position(std::chrono::milliseconds(qBound<qint64>(0, state.position, duration)));
                controls.UpdateTimelineProperties(timeline);
                controls.PlaybackRate(state.playback == "Playing" ? 1.0 : 0.0);
            }
            if (opening || state.playback != pushed->playback) controls.PlaybackStatus(status(state.playback));
            if (opening) controls.IsEnabled(true);
            pushed = state;
            if (newArt) {
                artwork = state.artwork;
                if (!thumbnailBusy) startThumbnail();
            }
        } catch (const winrt::hresult_error& e) { warn(e); }
    }
};
QString WindowsMediaSession::registerApplicationIdentity(const QString& appId, const QString& displayName) {
    // Microsoft Shell AppUserModelID / IShellLink registration. This uses the
    // current user's Start menu, requires no elevation and follows moved EXEs.
    try {
        const auto id = appId.toStdWString();
        winrt::check_hresult(SetCurrentProcessExplicitAppUserModelID(id.c_str()));
        PWSTR programs = nullptr;
        winrt::check_hresult(SHGetKnownFolderPath(FOLDERID_Programs, KF_FLAG_CREATE, nullptr, &programs));
        const QString folder = QString::fromWCharArray(programs) + "/ListenFree";
        CoTaskMemFree(programs);
        if (!QDir().mkpath(folder)) return {};
        const QString linkPath = folder + "/" + displayName + ".lnk";
        const auto executable = QDir::toNativeSeparators(QCoreApplication::applicationFilePath()).toStdWString();
        const auto workingDirectory = QDir::toNativeSeparators(QCoreApplication::applicationDirPath()).toStdWString();
        auto link = winrt::create_instance<IShellLinkW>(CLSID_ShellLink);
        const auto persist = link.as<IPersistFile>();
        const auto path = QDir::toNativeSeparators(linkPath).toStdWString();
        const auto properties = link.as<IPropertyStore>();
        // Do not rewrite an already correct shortcut on every launch.
        if (SUCCEEDED(persist->Load(path.c_str(), STGM_READWRITE))) {
            wchar_t target[32768]{};
            PROPVARIANT existing{};
            properties->GetValue(PKEY_AppUserModel_ID, &existing);
            const bool sameId = existing.vt == VT_LPWSTR && existing.pwszVal && id == existing.pwszVal;
            PropVariantClear(&existing);
            if (sameId && SUCCEEDED(link->GetPath(target, 32768, nullptr, SLGP_RAWPATH)) &&
                QString::fromWCharArray(target).compare(QString::fromStdWString(executable), Qt::CaseInsensitive) == 0)
                return linkPath;
        }
        winrt::check_hresult(link->SetPath(executable.c_str()));
        winrt::check_hresult(link->SetArguments(L""));
        winrt::check_hresult(link->SetWorkingDirectory(workingDirectory.c_str()));
        winrt::check_hresult(link->SetDescription(displayName.toStdWString().c_str()));
        winrt::check_hresult(link->SetIconLocation(executable.c_str(), 0));
        PROPVARIANT value{};
        winrt::check_hresult(InitPropVariantFromString(id.c_str(), &value));
        const auto result = properties->SetValue(PKEY_AppUserModel_ID, value);
        PropVariantClear(&value);
        winrt::check_hresult(result);
        winrt::check_hresult(properties->Commit());
        winrt::check_hresult(persist->Save(path.c_str(), TRUE));
        SHChangeNotify(SHCNE_CREATE, SHCNF_PATHW, path.c_str(), nullptr);
        return linkPath;
    } catch (const winrt::hresult_error& e) {
        qWarning().noquote() << "Windows application identity:" << QString::fromStdWString(std::wstring(e.message()));
        return {};
    }
}
WindowsMediaSession::WindowsMediaSession(QWindow* window, QObject* parent)
    : QObject(parent), impl_(std::make_unique<Impl>(this)) { impl_->initialize(window); }
WindowsMediaSession::~WindowsMediaSession() = default;
bool WindowsMediaSession::available() const { return impl_->ready; }
QString WindowsMediaSession::errorString() const { return impl_->error; }
void WindowsMediaSession::update(const State& state) { impl_->update(state); }
}
