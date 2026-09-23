#include "LxSourceService.h"
#include "LyricsService.h"
#include "OnlineMusicProvider.h"
#include "PlaybackEngine.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>
#include <QTextStream>
#include <QTimer>

class LiveCheck final : public QObject {
    Q_OBJECT

public:
    LiveCheck(QString sourcePath, QString query, QString providerIdOverride,
              QString overrideTitle, QString overrideArtist,
              QObject *parent = nullptr)
        : QObject(parent)
        , m_source(m_directory.path(), this)
        , m_provider(this)
        , m_lyrics(m_directory.filePath(QStringLiteral("lyrics")), this)
        , m_engine(this)
        , m_sourcePath(std::move(sourcePath))
        , m_query(std::move(query))
        , m_providerIdOverride(std::move(providerIdOverride))
        , m_overrideTitle(std::move(overrideTitle))
        , m_overrideArtist(std::move(overrideArtist))
    {
        connect(&m_provider, &OnlineMusicProvider::resultsReady,
                this, [this](const QList<TrackRecord> &tracks) {
            if (tracks.isEmpty()) {
                fail(QStringLiteral("search returned no tracks: %1")
                         .arg(m_provider.errorMessage()));
                return;
            }
            m_track = tracks.first();
            if (!m_providerIdOverride.isEmpty()) {
                m_track.providerId = m_providerIdOverride;
                m_track.path = QStringLiteral("lx://wy/%1").arg(m_providerIdOverride);
                QJsonObject data = QJsonDocument::fromJson(m_track.sourceData.toUtf8()).object();
                data.insert(QStringLiteral("id"), m_providerIdOverride);
                data.insert(QStringLiteral("songmid"), m_providerIdOverride);
                data.insert(QStringLiteral("songId"), m_providerIdOverride);
                QJsonObject meta = data.value(QStringLiteral("meta")).toObject();
                meta.insert(QStringLiteral("songId"), m_providerIdOverride);
                data.insert(QStringLiteral("meta"), meta);
                if (!m_overrideTitle.isEmpty()) {
                    m_track.title = m_overrideTitle;
                    data.insert(QStringLiteral("name"), m_track.title);
                }
                if (!m_overrideArtist.isEmpty()) {
                    m_track.artist = m_overrideArtist;
                    m_track.albumArtist = m_overrideArtist;
                    data.insert(QStringLiteral("singer"), m_track.artist);
                }
                m_track.sourceData = QString::fromUtf8(
                    QJsonDocument(data).toJson(QJsonDocument::Compact));
            }
            QTextStream(stdout) << "SEARCH_OK title=\"" << m_track.title
                                << "\" artist=\"" << m_track.artist
                                << "\" id=" << m_track.providerId << Qt::endl;
            m_lyrics.load(m_track);
            continueWhenReady();
        });
        connect(&m_lyrics, &LyricsService::lyricsChanged, this, [this] {
            if (!m_lyrics.lines().isEmpty()) {
                QTextStream(stdout) << "LYRICS_OK lines=" << m_lyrics.lines().size()
                                    << Qt::endl;
                m_lyricsFinished = true;
                maybeFinish();
            }
        });
        connect(&m_lyrics, &LyricsService::errorMessageChanged, this, [this] {
            if (m_lyrics.loading() || m_lyrics.errorMessage().isEmpty())
                return;
            QTextStream(stdout) << "LYRICS_UNAVAILABLE reason=\""
                                << m_lyrics.errorMessage() << "\"" << Qt::endl;
            m_lyricsFinished = true;
            maybeFinish();
        });
        connect(&m_source, &LxSourceService::stateChanged, this, [this] {
            if (m_finished)
                return;
            if (m_source.state() == QLatin1String("error")) {
                fail(QStringLiteral("source host failed: %1").arg(m_source.errorMessage()));
                return;
            }
            continueWhenReady();
        });
        connect(&m_source, &LxSourceService::resolved,
                this, [this](qint64, const QUrl &url) {
            QTextStream(stdout) << "RESOLVE_OK url=" << url.toString() << Qt::endl;
            if (!m_engine.load(url, true)) {
                fail(QStringLiteral("playback rejected URL: %1")
                         .arg(m_engine.errorMessage()));
            }
        });
        connect(&m_source, &LxSourceService::resolveFailed,
                this, [this](qint64, const QString &error) {
            fail(QStringLiteral("resolve failed: %1").arg(error));
        });
        connect(&m_engine, &PlaybackEngine::stateChanged, this, [this] {
            if (m_finished)
                return;
            if (m_engine.state() == QLatin1String("Playing")) {
                QTextStream(stdout) << "PLAYBACK_STARTED backend=\""
                                    << m_engine.backendName() << "\"" << Qt::endl;
            } else if (m_engine.state() == QLatin1String("Error")) {
                fail(QStringLiteral("playback failed: %1").arg(m_engine.errorMessage()));
            }
        });
        connect(&m_engine, &PlaybackEngine::positionChanged, this, [this] {
            if (m_finished || m_playbackReady
                || m_engine.state() != QLatin1String("Playing")
                || m_engine.positionMs() < 2000) {
                return;
            }
            QTextStream(stdout) << "PLAYBACK_OK backend=\""
                                << m_engine.backendName()
                                << "\" positionMs=" << m_engine.positionMs() << Qt::endl;
            m_playbackReady = true;
            maybeFinish();
        });
        m_timeout.setSingleShot(true);
        m_timeout.setInterval(60000);
        connect(&m_timeout, &QTimer::timeout, this, [this] {
            fail(QStringLiteral("live check timed out (source state: %1)")
                     .arg(m_source.state()));
        });
    }

    void start()
    {
        if (!m_directory.isValid()) {
            fail(QStringLiteral("unable to create temporary data directory"));
            return;
        }
        m_timeout.start();
        m_source.importSource(m_sourcePath);
        m_provider.search(m_query, 30);
    }

private:
    void maybeFinish()
    {
        if (m_playbackReady && m_lyricsFinished)
            finish(0);
    }

    void continueWhenReady()
    {
        if (m_resolveStarted || m_track.providerId.isEmpty()
            || m_source.state() != QLatin1String("ready")) {
            return;
        }
        m_resolveStarted = true;
        QTextStream(stdout) << "SOURCE_OK active=" << m_source.activeSourceId() << Qt::endl;
        m_source.resolve(1, m_track.source, m_track.sourceData);
    }

    void fail(const QString &message)
    {
        QTextStream(stderr) << "LIVE_CHECK_FAILED " << message << Qt::endl;
        finish(1);
    }

    void finish(int exitCode)
    {
        if (m_finished)
            return;
        m_finished = true;
        m_timeout.stop();
        m_engine.stop();
        QCoreApplication::exit(exitCode);
    }

    QTemporaryDir m_directory;
    LxSourceService m_source;
    OnlineMusicProvider m_provider;
    LyricsService m_lyrics;
    PlaybackEngine m_engine;
    QTimer m_timeout;
    TrackRecord m_track;
    QString m_sourcePath;
    QString m_query;
    QString m_providerIdOverride;
    QString m_overrideTitle;
    QString m_overrideArtist;
    bool m_resolveStarted = false;
    bool m_playbackReady = false;
    bool m_lyricsFinished = false;
    bool m_finished = false;
};

int main(int argc, char **argv)
{
    QCoreApplication application(argc, argv);
    const QStringList arguments = application.arguments();
    if (arguments.size() < 3) {
        QTextStream(stderr) << "usage: kos-music-live-source-check SOURCE.js QUERY [PROVIDER_ID [TITLE ARTIST]]"
                            << Qt::endl;
        return 2;
    }
    qputenv("KOS_MUSIC_FAKE_AUDIO", "1");
    const QString sourceArgument = arguments.at(1);
    const QUrl sourceUrl(sourceArgument);
    const QString source = sourceUrl.isValid() && !sourceUrl.scheme().isEmpty()
        ? sourceArgument : QFileInfo(sourceArgument).absoluteFilePath();
    LiveCheck check(source, arguments.at(2), arguments.value(3),
                    arguments.value(4), arguments.value(5));
    QTimer::singleShot(0, &check, &LiveCheck::start);
    return application.exec();
}

#include "MusicLiveSourceCheck.moc"
