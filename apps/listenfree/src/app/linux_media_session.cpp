#include "linux_media_session.h"
#include "qmlbridge/portable_session.h"
#include "qmlbridge/controllers.h"
#include "qmlbridge/cover_image_provider.h"
#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QWindow>
#include <QFutureWatcher>
#include <QtConcurrent>
#include <QSaveFile>
#include <cmath>

namespace listenfree {
namespace {
constexpr auto Path = "/org/mpris/MediaPlayer2";
constexpr auto PlayerInterface = "org.mpris.MediaPlayer2.Player";
class RootAdaptor final : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(bool CanQuit READ yes CONSTANT)
    Q_PROPERTY(bool CanRaise READ yes CONSTANT)
    Q_PROPERTY(bool HasTrackList READ no CONSTANT)
    Q_PROPERTY(QString Identity READ identity CONSTANT)
    Q_PROPERTY(QString DesktopEntry READ desktopEntry CONSTANT)
    Q_PROPERTY(QStringList SupportedUriSchemes READ schemes CONSTANT)
    Q_PROPERTY(QStringList SupportedMimeTypes READ mimeTypes CONSTANT)
public:
    explicit RootAdaptor(LinuxMediaSession* session) : QDBusAbstractAdaptor(session), session_(session) {}
    bool yes() const { return true; }
    bool no() const { return false; }
    QString identity() const { return "KOS ListenFree"; }
    QString desktopEntry() const { return "listenfree"; }
    QStringList schemes() const { return {"file", "http", "https"}; }
    QStringList mimeTypes() const { return {"audio/mpeg", "audio/flac", "audio/ogg", "audio/wav", "audio/mp4"}; }
public slots:
    void Raise() { session_->raise(); }
    void Quit() { QCoreApplication::quit(); }
private:
    LinuxMediaSession* session_;
};
class PlayerAdaptor final : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus READ status)
    Q_PROPERTY(QString LoopStatus READ loop WRITE setLoop)
    Q_PROPERTY(double Rate READ rate WRITE setRate)
    Q_PROPERTY(bool Shuffle READ shuffle WRITE setShuffle)
    Q_PROPERTY(QVariantMap Metadata READ metadata)
    Q_PROPERTY(double Volume READ volume WRITE setVolume)
    Q_PROPERTY(qlonglong Position READ position)
    Q_PROPERTY(double MinimumRate READ rate CONSTANT)
    Q_PROPERTY(double MaximumRate READ rate CONSTANT)
    Q_PROPERTY(bool CanGoNext READ hasQueue)
    Q_PROPERTY(bool CanGoPrevious READ hasQueue)
    Q_PROPERTY(bool CanPlay READ hasTrack)
    Q_PROPERTY(bool CanPause READ hasTrack)
    Q_PROPERTY(bool CanSeek READ canSeek)
    Q_PROPERTY(bool CanControl READ yes CONSTANT)
public:
    explicit PlayerAdaptor(LinuxMediaSession* session) : QDBusAbstractAdaptor(session), session_(session) {
        connect(session, &LinuxMediaSession::seeked, this, &PlayerAdaptor::Seeked);
    }
    QString status() const { return session_->playbackStatus(); }
    QString loop() const { return session_->loopStatus(); }
    void setLoop(const QString& loop) {
        if (loop == "Track") session_->player().setPlaybackMode("singleLoop");
        else if (loop == "Playlist") session_->player().setPlaybackMode("listLoop");
        else if (loop == "None") session_->player().setPlaybackMode("stopAfterCurrent");
    }
    double rate() const { return 1.; }
    void setRate(double) {} // The unchanged engine uses a fixed playback rate.
    bool shuffle() const { return session_->player().playbackMode() == "shuffle"; }
    void setShuffle(bool value) {
        if (value) session_->player().setPlaybackMode("shuffle");
        else if (shuffle()) session_->player().setPlaybackMode("listLoop");
    }
    QVariantMap metadata() const { return session_->metadata(); }
    double volume() const { return session_->player().volume(); }
    void setVolume(double value) { if (std::isfinite(value)) session_->player().setVolume(qBound(0., value, 1.)); }
    qlonglong position() const { return qMax<qint64>(0, session_->player().position()) * 1000; }
    bool hasTrack() const { return !session_->player().currentTrack().isEmpty(); }
    bool hasQueue() const { return session_->player().queueSongs().size() > 1; }
    bool canSeek() const { return session_->player().seekable(); }
    bool yes() const { return true; }
public slots:
    void Next() { session_->player().next(); }
    void Previous() { session_->player().previous(); }
    void Pause() { session_->player().pause(); }
    void PlayPause() { if (status() == "Playing" || session_->player().state() == "Loading") Pause(); else Play(); }
    void Stop() { session_->player().stop(); }
    void Play() { session_->player().play(); }
    void Seek(qlonglong offset) {
        const auto target = static_cast<long double>(position()) + offset;
        if (canSeek() && hasQueue() && target > static_cast<long double>(session_->player().duration()) * 1000) { Next(); return; }
        session_->seek(static_cast<qint64>(qBound(0.L, target, static_cast<long double>(std::numeric_limits<qint64>::max()))));
    }
    void SetPosition(const QDBusObjectPath& id, qlonglong position) {
        if (id == session_->trackPath()) session_->seek(position);
    }
    void OpenUri(const QString& uri) {
        const QUrl url(uri);
        if (!url.isValid()) return;
        if (url.isLocalFile()) session_->player().openLocal(url.toLocalFile());
        else if (url.scheme() == "https" || url.scheme() == "http") session_->player().openUrl(url);
    }
signals:
    void Seeked(qlonglong position);
private:
    LinuxMediaSession* session_;
};
}
LinuxMediaSession::LinuxMediaSession(qmlbridge::PortableSession& player, qmlbridge::SettingsController& settings,
                                   QWindow* window, QObject* parent)
    : QObject(parent), player_(player), settings_(settings), window_(window) {
    new RootAdaptor(this);
    new PlayerAdaptor(this);
    flush_.setSingleShot(true);
    flush_.setInterval(30);
    connect(&flush_, &QTimer::timeout, this, &LinuxMediaSession::publish);
    connect(&player_, &qmlbridge::PortableSession::changed, this, &LinuxMediaSession::refresh);
    connect(&player_, &qmlbridge::PortableSession::queueChanged, this, &LinuxMediaSession::refresh);
    connect(&player_, &qmlbridge::PortableSession::lyricsChanged, this, [this] { lyrics_ = player_.lyrics(); refresh(); });
    connect(&player_, &qmlbridge::PortableSession::currentTrackChanged, this, [this] {
        elapsed_.invalidate(); lyrics_ = player_.lyrics(); updateArtwork(); refresh();
    });
    connect(&player_, &qmlbridge::PortableSession::progressChanged, this, [this] {
        const auto position = player_.position();
        const auto expected = lastPosition_ + (elapsed_.isValid() && playbackStatus() == "Playing" ? elapsed_.elapsed() : 0);
        if (elapsed_.isValid() && qAbs(position - expected) > 1200) emit seeked(position * 1000);
        elapsed_.restart(); lastPosition_ = position; refresh();
    });
    connect(&settings_, &qmlbridge::SettingsController::valueChanged, this, [this](const QString& key, const QVariant&) {
        if (key == "nextkde.mediaEnabled") updateRegistration();
        if (key.startsWith("nextkde.")) refresh();
    });
    lyrics_ = player_.lyrics(); updateArtwork(); updateRegistration();
}
LinuxMediaSession::~LinuxMediaSession() {
    if (registered_) {
        QDBusConnection::sessionBus().unregisterObject(Path);
        QDBusConnection::sessionBus().unregisterService(service_);
    }
}
void LinuxMediaSession::updateRegistration() {
    auto bus = QDBusConnection::sessionBus();
    const bool enabled = settings_.value("nextkde.mediaEnabled", true).toBool();
    if (registered_ && !enabled) {
        bus.unregisterObject(Path); bus.unregisterService(service_); registered_ = false; published_.clear();
    } else if (!registered_ && enabled) {
        service_ = "org.mpris.MediaPlayer2.listenfree";
        if (!bus.registerService(service_)) {
            service_ += ".instance" + QString::number(QCoreApplication::applicationPid());
            if (!bus.registerService(service_)) return;
        }
        registered_ = bus.registerObject(Path, this, QDBusConnection::ExportAdaptors);
        if (!registered_) bus.unregisterService(service_);
        else refresh();
    }
}
void LinuxMediaSession::raise() {
    if (!window_) return;
    if (window_->visibility() == QWindow::Minimized) window_->showNormal(); else window_->show();
    window_->raise(); window_->requestActivate();
}
QString LinuxMediaSession::playbackStatus() const {
    const auto state = player_.state();
    return state == "Playing" ? "Playing" : state == "Paused" || state == "Loading" || state == "Buffering" ? "Paused" : "Stopped";
}
QString LinuxMediaSession::loopStatus() const {
    const auto mode = player_.playbackMode();
    return mode == "singleLoop" ? "Track" : mode == "listLoop" || mode == "shuffle" ? "Playlist" : "None";
}
QDBusObjectPath LinuxMediaSession::trackPath() const {
    const auto track = player_.currentTrack();
    if (track.isEmpty()) return QDBusObjectPath("/org/mpris/MediaPlayer2/TrackList/NoTrack");
    const auto id = track.value("entryId", track.value("trackId")).toString();
    return QDBusObjectPath("/org/listenfree/track/t" + QString::fromLatin1(QCryptographicHash::hash(id.toUtf8(), QCryptographicHash::Sha256).toHex()));
}
QVariantMap LinuxMediaSession::metadata() const {
    const auto track = player_.currentTrack();
    if (track.isEmpty()) return {};
    const bool lyricsEnabled = settings_.value("nextkde.lyricsEnabled", true).toBool();
    const bool desktopLyrics = settings_.value("nextkde.desktopLyricsEnabled", true).toBool();
    const int index = player_.currentLyricIndex();
    const auto line = [this](int i) { return i >= 0 && i < lyrics_.size() ? lyrics_[i].toMap().value("text").toString() : QString{}; };
    const auto local = track.value("localPath").toString();
    QVariantMap result{{"mpris:trackid", QVariant::fromValue(trackPath())},
        {"mpris:length", QVariant::fromValue<qlonglong>(qMax<qint64>(0, player_.duration()) * 1000)},
        {"xesam:title", track.value("title").toString()}, {"xesam:artist", QStringList{track.value("artist").toString()}},
        {"xesam:album", track.value("album").toString()}, {"xesam:url", local.isEmpty() ? track.value("remoteUrl").toString() : QUrl::fromLocalFile(local).toString()},
        {"xesam:asText", line(index)}, {"kos:currentLyric", line(index)}, {"kos:nextLyric", line(index + 1)},
        {"kos:lyricIndex", index}, {"kos:lyricsEnabled", lyricsEnabled || desktopLyrics},
        {"kos:desktopLyricsEnabled", desktopLyrics}, {"kos:lockscreenLyricsEnabled", lyricsEnabled},
        {"kos:playbackState", player_.state()}, {"kos:playbackStatus", player_.state() == "Loading" ? tr("正在加载…") : QString{}}};
    if (!artworkUrl_.isEmpty()) result.insert("mpris:artUrl", artworkUrl_);
    return result;
}
void LinuxMediaSession::seek(qint64 microseconds) {
    if (!player_.seekable() || microseconds < 0 || microseconds / 1000 > player_.duration()) return;
    player_.seek(microseconds / 1000);
    emit seeked(microseconds);
    elapsed_.invalidate(); refresh();
}
void LinuxMediaSession::refresh() { if (!flush_.isActive()) flush_.start(); }
void LinuxMediaSession::publish() {
    if (!registered_) return;
    const bool hasTrack = !player_.currentTrack().isEmpty();
    const bool hasQueue = player_.queueSongs().size() > 1;
    const QVariantMap values{{"PlaybackStatus", playbackStatus()}, {"LoopStatus", loopStatus()},
        {"Shuffle", player_.playbackMode() == "shuffle"}, {"Metadata", metadata()}, {"Volume", double(player_.volume())},
        {"CanPlay", hasTrack}, {"CanPause", hasTrack}, {"CanSeek", player_.seekable()},
        {"CanGoNext", hasQueue}, {"CanGoPrevious", hasQueue}};
    QVariantMap changes;
    for (auto it = values.cbegin(); it != values.cend(); ++it)
        if (!published_.contains(it.key()) || published_.value(it.key()) != it.value()) changes.insert(it.key(), it.value());
    if (changes.isEmpty()) return;
    published_ = values;
    auto message = QDBusMessage::createSignal(Path, "org.freedesktop.DBus.Properties", "PropertiesChanged");
    message << QString(PlayerInterface) << changes << QStringList{};
    QDBusConnection::sessionBus().send(message);
}
void LinuxMediaSession::updateArtwork() {
    const auto source = player_.currentTrack().value("artwork").toString();
    if (source == artworkSource_) return;
    artworkSource_ = source; artworkUrl_.clear();
    const QUrl url(source);
    if (url.scheme() == "https" || url.scheme() == "http" || url.isLocalFile()) { artworkUrl_ = source; return; }
    if (!source.startsWith("image://covers/") || !artworkDirectory_.isValid()) return;
    const auto output = artworkDirectory_.filePath(QString::fromLatin1(QCryptographicHash::hash(source.toUtf8(), QCryptographicHash::Sha256).toHex()) + ".png");
    auto* job = new QFutureWatcher<QImage>(this);
    connect(job, &QFutureWatcher<QImage>::finished, this, [this, job, source, output] {
        const auto pixels = job->result(); job->deleteLater();
        if (source != artworkSource_ || pixels.isNull()) return;
        QSaveFile file(output);
        if (file.open(QIODevice::WriteOnly) && pixels.save(&file, "PNG") && file.commit()) {
            artworkUrl_ = QUrl::fromLocalFile(output).toString(); refresh();
        }
    });
    job->setFuture(QtConcurrent::run([source] { CoverImageProvider provider; return provider.requestImage(source.mid(15), nullptr, {256,256}); }));
}
}
#include "linux_media_session.moc"
