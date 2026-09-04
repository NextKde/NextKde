#include "MprisService.h"

#include "MusicController.h"

#include <QCoreApplication>
#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QStringList>

namespace {

constexpr auto objectPath = "/org/mpris/MediaPlayer2";
constexpr auto serviceName = "org.mpris.MediaPlayer2.kosmusic";
constexpr auto playerInterface = "org.mpris.MediaPlayer2.Player";

class RootAdaptor final : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")

    Q_PROPERTY(bool CanQuit READ canQuit CONSTANT)
    Q_PROPERTY(bool Fullscreen READ fullscreen WRITE setFullscreen)
    Q_PROPERTY(bool CanSetFullscreen READ canSetFullscreen CONSTANT)
    Q_PROPERTY(bool CanRaise READ canRaise CONSTANT)
    Q_PROPERTY(bool HasTrackList READ hasTrackList CONSTANT)
    Q_PROPERTY(QString Identity READ identity CONSTANT)
    Q_PROPERTY(QString DesktopEntry READ desktopEntry CONSTANT)
    Q_PROPERTY(QStringList SupportedUriSchemes READ supportedUriSchemes CONSTANT)
    Q_PROPERTY(QStringList SupportedMimeTypes READ supportedMimeTypes CONSTANT)

public:
    RootAdaptor(MusicController *controller, QObject *parent)
        : QDBusAbstractAdaptor(parent)
        , m_controller(controller)
    {
        setAutoRelaySignals(false);
    }

    bool canQuit() const { return true; }
    bool fullscreen() const { return false; }
    void setFullscreen(bool) {}
    bool canSetFullscreen() const { return false; }
    bool canRaise() const { return true; }
    bool hasTrackList() const { return false; }
    QString identity() const { return QStringLiteral("KOS Music"); }
    QString desktopEntry() const { return QStringLiteral("kos-music"); }
    QStringList supportedUriSchemes() const { return {QStringLiteral("file")}; }
    QStringList supportedMimeTypes() const
    {
        return {
            QStringLiteral("audio/aac"),
            QStringLiteral("audio/flac"),
            QStringLiteral("audio/mp4"),
            QStringLiteral("audio/mpeg"),
            QStringLiteral("audio/ogg"),
            QStringLiteral("audio/opus"),
            QStringLiteral("audio/wav"),
            QStringLiteral("audio/x-flac"),
            QStringLiteral("audio/x-wav"),
        };
    }

public slots:
    void Raise() { m_controller->requestRaise(); }
    void Quit() { QCoreApplication::quit(); }

private:
    MusicController *m_controller;
};

class PlayerAdaptor final : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")

    Q_PROPERTY(QString PlaybackStatus READ playbackStatus)
    Q_PROPERTY(QString LoopStatus READ loopStatus WRITE setLoopStatus)
    Q_PROPERTY(double Rate READ rate WRITE setRate)
    Q_PROPERTY(bool Shuffle READ shuffle WRITE setShuffle)
    Q_PROPERTY(QVariantMap Metadata READ metadata)
    Q_PROPERTY(double Volume READ volume WRITE setVolume)
    Q_PROPERTY(qlonglong Position READ position)
    Q_PROPERTY(double MinimumRate READ minimumRate CONSTANT)
    Q_PROPERTY(double MaximumRate READ maximumRate CONSTANT)
    Q_PROPERTY(bool CanGoNext READ canGoNext)
    Q_PROPERTY(bool CanGoPrevious READ canGoPrevious)
    Q_PROPERTY(bool CanPlay READ canPlay)
    Q_PROPERTY(bool CanPause READ canPause)
    Q_PROPERTY(bool CanSeek READ canSeek)
    Q_PROPERTY(bool CanControl READ canControl CONSTANT)

public:
    PlayerAdaptor(MusicController *controller, QObject *parent)
        : QDBusAbstractAdaptor(parent)
        , m_controller(controller)
    {
        setAutoRelaySignals(false);
    }

    QString playbackStatus() const
    {
        if (m_controller->playbackState() == QLatin1String("Playing"))
            return QStringLiteral("Playing");
        if (m_controller->playbackState() == QLatin1String("Paused")
            || m_controller->playbackState() == QLatin1String("Loading")) {
            return QStringLiteral("Paused");
        }
        return QStringLiteral("Stopped");
    }
    QString loopStatus() const { return m_controller->mprisLoopStatus(); }
    void setLoopStatus(const QString &status)
    {
        if (status == QLatin1String("Track"))
            m_controller->setRepeatMode(QStringLiteral("track"));
        else if (status == QLatin1String("Playlist"))
            m_controller->setRepeatMode(QStringLiteral("playlist"));
        else
            m_controller->setRepeatMode(QStringLiteral("none"));
    }
    double rate() const { return 1.0; }
    void setRate(double) {}
    bool shuffle() const { return m_controller->shuffle(); }
    void setShuffle(bool enabled) { m_controller->setShuffle(enabled); }
    QVariantMap metadata() const { return m_controller->mprisMetadata(); }
    double volume() const { return m_controller->volume(); }
    void setVolume(double volume) { m_controller->setVolume(volume); }
    qlonglong position() const { return m_controller->positionMs() * 1000; }
    double minimumRate() const { return 1.0; }
    double maximumRate() const { return 1.0; }
    bool canGoNext() const { return m_controller->canGoNext(); }
    bool canGoPrevious() const { return m_controller->canGoPrevious(); }
    bool canPlay() const
    {
        return m_controller->engineAvailable() && m_controller->currentTrackId() >= 0;
    }
    bool canPause() const { return canPlay(); }
    bool canSeek() const { return m_controller->seekable(); }
    bool canControl() const { return true; }

public slots:
    void Next() { m_controller->next(); }
    void Previous() { m_controller->previous(); }
    void Pause() { m_controller->pause(); }
    void PlayPause() { m_controller->togglePlayPause(); }
    void Stop() { m_controller->stop(); }
    void Play() { m_controller->play(); }
    void Seek(qlonglong offset)
    {
        m_controller->seek(m_controller->positionMs() + offset / 1000);
    }
    void SetPosition(const QDBusObjectPath &trackId, qlonglong position)
    {
        const QDBusObjectPath current = m_controller->mprisMetadata()
                                            .value(QStringLiteral("mpris:trackid"))
                                            .value<QDBusObjectPath>();
        if (current.path() == trackId.path())
            m_controller->seek(position / 1000);
    }
    void OpenUri(const QString &uri) { m_controller->openUri(uri); }

signals:
    void Seeked(qlonglong Position);

private:
    MusicController *m_controller;
};

} // namespace

MprisService::MprisService(MusicController *controller, QObject *parent)
    : QObject(parent)
{
    new RootAdaptor(controller, this);
    auto *player = new PlayerAdaptor(controller, this);

    connect(controller, &MusicController::playbackStateChanged, this,
            [this, player] {
                publishPlayerProperties({
                    {QStringLiteral("PlaybackStatus"), player->playbackStatus()},
                });
            });
    connect(controller, &MusicController::currentTrackChanged, this,
            [this, controller, player] {
                publishPlayerProperties({
                    {QStringLiteral("Metadata"), controller->mprisMetadata()},
                    {QStringLiteral("CanPlay"), player->canPlay()},
                    {QStringLiteral("CanPause"), player->canPause()},
                    {QStringLiteral("CanGoNext"), controller->canGoNext()},
                    {QStringLiteral("CanGoPrevious"), controller->canGoPrevious()},
                });
                emit player->Seeked(controller->positionMs() * 1000);
            });
    connect(controller, &MusicController::queueChanged, this, [this, controller] {
        publishPlayerProperties({
            {QStringLiteral("CanGoNext"), controller->canGoNext()},
            {QStringLiteral("CanGoPrevious"), controller->canGoPrevious()},
        });
    });
    connect(controller, &MusicController::volumeChanged, this, [this, controller] {
        publishPlayerProperties({
            {QStringLiteral("Volume"), controller->volume()},
        });
    });
    connect(controller, &MusicController::shuffleChanged, this, [this, controller] {
        publishPlayerProperties({
            {QStringLiteral("Shuffle"), controller->shuffle()},
        });
    });
    connect(controller, &MusicController::repeatModeChanged, this, [this, controller] {
        publishPlayerProperties({
            {QStringLiteral("LoopStatus"), controller->mprisLoopStatus()},
        });
    });
    connect(controller, &MusicController::seekableChanged, this, [this, controller] {
        publishPlayerProperties({
            {QStringLiteral("CanSeek"), controller->seekable()},
        });
    });
    connect(controller, &MusicController::seeked, player,
            [player](qlonglong milliseconds) { emit player->Seeked(milliseconds * 1000); });

    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return;
    m_objectRegistered = bus.registerObject(
        QString::fromLatin1(objectPath), this, QDBusConnection::ExportAdaptors);
    if (!m_objectRegistered)
        return;
    m_registered = bus.registerService(QString::fromLatin1(serviceName));
    if (!m_registered) {
        bus.unregisterObject(QString::fromLatin1(objectPath));
        m_objectRegistered = false;
    }
}

MprisService::~MprisService()
{
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (m_registered)
        bus.unregisterService(QString::fromLatin1(serviceName));
    if (m_objectRegistered)
        bus.unregisterObject(QString::fromLatin1(objectPath));
}

bool MprisService::registered() const
{
    return m_registered;
}

void MprisService::publishPlayerProperties(const QVariantMap &properties) const
{
    if (!m_registered || properties.isEmpty())
        return;
    QDBusMessage message = QDBusMessage::createSignal(
        QString::fromLatin1(objectPath),
        QStringLiteral("org.freedesktop.DBus.Properties"),
        QStringLiteral("PropertiesChanged"));
    message << QString::fromLatin1(playerInterface) << properties << QStringList{};
    QDBusConnection::sessionBus().send(message);
}

#include "MprisService.moc"
