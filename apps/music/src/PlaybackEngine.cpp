#include "PlaybackEngine.h"

#include <QFileInfo>
#include <QFile>
#include <QDir>
#include <QTemporaryFile>
#include <QMetaObject>

#include <gst/gst.h>

#include <algorithm>
#include <utility>

namespace {

QString gstErrorMessage(const GError *error, const gchar *debug)
{
    QString message = error ? QString::fromUtf8(error->message)
                            : QStringLiteral("Unknown GStreamer error");
    if (debug && *debug)
        message += QStringLiteral(" (%1)").arg(QString::fromUtf8(debug));
    return message;
}

// Runs on whatever streaming thread posted the message. It must not touch Qt
// object members; it only queues pollBus() onto the engine's thread so the
// bus is drained on the UI event loop instead of a polling timer.
GstBusSyncReply busSyncHandler(GstBus *bus, GstMessage *message,
                               gpointer userData)
{
    Q_UNUSED(bus)
    Q_UNUSED(message)
    auto *engine = static_cast<PlaybackEngine *>(userData);
    QMetaObject::invokeMethod(engine, "pollBus", Qt::QueuedConnection);
    return GST_BUS_PASS;
}

} // namespace

PlaybackEngine::PlaybackEngine(QObject *parent)
    : QObject(parent)
{
    GError *initializationError = nullptr;
    if (!gst_init_check(nullptr, nullptr, &initializationError)) {
        setErrorMessage(initializationError
                            ? QString::fromUtf8(initializationError->message)
                            : QStringLiteral("Unable to initialize GStreamer"));
        if (initializationError)
            g_error_free(initializationError);
        return;
    }
    m_playbin = gst_element_factory_make("playbin3", "kos-music-player");
    if (m_playbin)
        m_backendName = QStringLiteral("GStreamer playbin3");
    else {
        m_playbin = gst_element_factory_make("playbin", "kos-music-player");
        m_backendName = QStringLiteral("GStreamer playbin");
    }
    if (!m_playbin) {
        setErrorMessage(QStringLiteral("GStreamer playbin is not installed"));
        return;
    }
    m_bus = gst_element_get_bus(m_playbin);
    g_object_set(m_playbin, "volume", m_volume, nullptr);
    g_object_set(m_playbin, "buffer-duration", gint64(2 * GST_SECOND),
                 "buffer-size", 256 * 1024, nullptr);
    // These callbacks run on streaming threads. The template is only changed
    // before the first load; no Qt state or signals are touched here.
    g_signal_connect(m_playbin, "deep-element-added", G_CALLBACK(+[](
        GstBin *, GstBin *, GstElement *element, gpointer data) {
        const auto *engine = static_cast<PlaybackEngine *>(data);
        GstElementFactory *factory = gst_element_get_factory(element);
        if (factory && !engine->m_downloadTemplate.isEmpty()
            && g_str_equal(gst_plugin_feature_get_name(GST_PLUGIN_FEATURE(factory)), "downloadbuffer")) {
            g_object_set(element, "temp-template", engine->m_downloadTemplate.constData(),
                         "temp-remove", TRUE, nullptr);
        }
    }), this);
    g_signal_connect(m_playbin, "source-setup", G_CALLBACK(+[](
        GstElement *, GstElement *source, gpointer) {
        if (g_object_class_find_property(G_OBJECT_GET_CLASS(source), "timeout"))
            g_object_set(source, "timeout", guint(15), nullptr);
    }), nullptr);

    if (qEnvironmentVariableIsSet("KOS_MUSIC_FAKE_AUDIO")) {
        if (GstElement *sink = gst_element_factory_make("fakesink", "test-audio-sink")) {
            // playbin stores an object property reference. Sink the factory's
            // floating reference first so releasing our reference cannot leave
            // playbin with a dangling audio sink during teardown.
            gst_object_ref_sink(sink);
            g_object_set(sink, "sync", TRUE, nullptr);
            g_object_set(m_playbin, "audio-sink", sink, nullptr);
            gst_object_unref(sink);
        }
    } else {
        const QByteArray requestedSink = qgetenv("KOS_MUSIC_AUDIO_SINK");
        if (!requestedSink.isEmpty()) {
            if (GstElement *sink = gst_element_factory_make(requestedSink.constData(),
                                                            "requested-audio-sink")) {
                gst_object_ref_sink(sink);
                g_object_set(m_playbin, "audio-sink", sink, nullptr);
                gst_object_unref(sink);
            }
        }
    }

    // Wake the UI thread only when the bus posts a message; the sync handler
    // queues pollBus() and never touches Qt object members itself.
    gst_bus_set_sync_handler(m_bus, busSyncHandler, this, nullptr);
    m_positionTimer.setInterval(250);
    connect(&m_positionTimer, &QTimer::timeout, this,
            &PlaybackEngine::updatePosition);
    m_downloadTimer.setInterval(500);
    connect(&m_downloadTimer, &QTimer::timeout, this, &PlaybackEngine::updateDownloadProgress);
    m_loadingTimeout.setInterval(30000);
    m_loadingTimeout.setSingleShot(true);
    connect(&m_loadingTimeout, &QTimer::timeout, this, [this] {
        m_requestedPlaying = false;
        gst_element_set_state(m_playbin, GST_STATE_NULL);
        setErrorMessage(tr("Playback timed out. Check the network or audio output, then retry."));
        setState(QStringLiteral("Error"));
    });
}

int PlaybackEngine::bufferingPercent() const { return m_bufferingPercent; }
double PlaybackEngine::downloadProgress() const { return m_downloadProgress; }

void PlaybackEngine::setDownloadDirectory(const QString &directory)
{
    QTemporaryFile probe(QDir(directory).filePath(QStringLiteral(".write-test-XXXXXX")));
    if (m_source.isEmpty() && QDir().mkpath(directory) && probe.open())
        m_downloadTemplate = QDir(directory).filePath(QStringLiteral("stream-XXXXXX")).toUtf8();
}

PlaybackEngine::~PlaybackEngine()
{
    if (m_playbin)
        gst_element_set_state(m_playbin, GST_STATE_NULL);
    finishDownload();
    if (m_bus) {
        // Drop the handler before unreferencing so no queued pollBus() call
        // or in-flight bus post can touch a destroyed engine.
        gst_bus_set_sync_handler(m_bus, nullptr, nullptr, nullptr);
        gst_object_unref(m_bus);
    }
    if (m_playbin)
        gst_object_unref(m_playbin);
}

bool PlaybackEngine::available() const
{
    return m_playbin != nullptr;
}

QString PlaybackEngine::backendName() const
{
    return m_backendName;
}

QString PlaybackEngine::state() const
{
    return m_state;
}

QString PlaybackEngine::errorMessage() const
{
    return m_errorMessage;
}

QUrl PlaybackEngine::source() const
{
    return m_source;
}

qint64 PlaybackEngine::positionMs() const
{
    return m_positionMs;
}

qint64 PlaybackEngine::durationMs() const
{
    return m_durationMs;
}

bool PlaybackEngine::seekable() const
{
    return m_seekable;
}

double PlaybackEngine::volume() const
{
    return m_volume;
}

bool PlaybackEngine::load(const QUrl &source, bool autoPlay, qint64 startPositionMs)
{
    if (!m_playbin)
        return false;
    gst_element_set_state(m_playbin, GST_STATE_NULL);
    finishDownload();
    if (source.isEmpty() || !source.isValid()) {
        setErrorMessage(QStringLiteral("Invalid audio URL"));
        setState(QStringLiteral("Error"));
        return false;
    }
    if (source.isLocalFile() && !QFileInfo::exists(source.toLocalFile())) {
        setErrorMessage(QStringLiteral("Audio file no longer exists: %1")
                            .arg(source.toLocalFile()));
        setState(QStringLiteral("Error"));
        return false;
    }

    const bool remote = source.scheme() == QLatin1String("http")
        || source.scheme() == QLatin1String("https");
    guint flags = 0;
    g_object_get(m_playbin, "flags", &flags, nullptr);
    constexpr guint downloadFlag = 1 << 7;
    flags = remote && !m_downloadTemplate.isEmpty() ? flags | downloadFlag : flags & ~downloadFlag;
    g_object_set(m_playbin, "flags", flags, nullptr);
    m_downloading = remote && !m_downloadTemplate.isEmpty();
    m_downloadFailed = false;
    m_downloadProgress = -1;
    m_bufferingPercent = remote ? 0 : 100;
    emit bufferingChanged();
    if (m_downloading)
        m_downloadTimer.start();
    else
        m_downloadTimer.stop();
    const QByteArray encodedUri = source.toEncoded();
    g_object_set(m_playbin, "uri", encodedUri.constData(), nullptr);
    m_source = source;
    m_positionMs = std::max<qint64>(0, startPositionMs);
    m_pendingPositionMs = m_positionMs > 0 ? m_positionMs : -1;
    m_durationMs = 0;
    m_seekable = false;
    m_requestedPlaying = autoPlay;
    setErrorMessage({});
    setState(QStringLiteral("Loading"));
    emit sourceChanged();
    emit positionChanged();
    emit durationChanged();
    emit seekableChanged();
    const GstStateChangeReturn result = gst_element_set_state(
        m_playbin, autoPlay && m_pendingPositionMs < 0 ? GST_STATE_PLAYING : GST_STATE_PAUSED);
    if (result == GST_STATE_CHANGE_FAILURE) {
        setErrorMessage(QStringLiteral("GStreamer rejected the audio source"));
        setState(QStringLiteral("Error"));
        return false;
    }
    return true;
}

void PlaybackEngine::play()
{
    if (!m_playbin || m_source.isEmpty())
        return;
    m_requestedPlaying = true;
    setState(QStringLiteral("Loading"));
    if (m_pendingPositionMs >= 0)
        return; // Finish preroll and restore the position before starting audio.
    if (gst_element_set_state(m_playbin, m_bufferingPercent < 100
            ? GST_STATE_PAUSED : GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        setErrorMessage(QStringLiteral("Unable to start playback"));
        setState(QStringLiteral("Error"));
    }
}

void PlaybackEngine::pause()
{
    if (!m_playbin || m_source.isEmpty())
        return;
    m_requestedPlaying = false;
    updatePosition();
    if (gst_element_set_state(m_playbin, GST_STATE_PAUSED) == GST_STATE_CHANGE_FAILURE) {
        setErrorMessage(QStringLiteral("Unable to pause playback"));
        setState(QStringLiteral("Error"));
    } else
        setState(QStringLiteral("Paused"));
}

void PlaybackEngine::stop()
{
    if (!m_playbin)
        return;
    m_requestedPlaying = false;
    m_pendingPositionMs = -1;
    m_downloading = false;
    m_downloadTimer.stop();
    gst_element_set_state(m_playbin, GST_STATE_NULL);
    finishDownload();
    if (m_positionMs != 0) {
        m_positionMs = 0;
        emit positionChanged();
    }
    setState(QStringLiteral("Stopped"));
}

void PlaybackEngine::seek(qint64 positionMs)
{
    if (!m_playbin || !m_seekable)
        return;
    const qint64 bounded = std::clamp<qint64>(positionMs, 0, m_durationMs);
    if (gst_element_seek_simple(m_playbin, GST_FORMAT_TIME,
                                static_cast<GstSeekFlags>(GST_SEEK_FLAG_FLUSH
                                                          | GST_SEEK_FLAG_KEY_UNIT),
                                bounded * GST_MSECOND)) {
        m_positionMs = bounded;
        emit positionChanged();
        emit seeked(bounded);
    }
}

void PlaybackEngine::setVolume(double volume)
{
    const double bounded = std::clamp(volume, 0.0, 1.5);
    if (qFuzzyCompare(m_volume, bounded))
        return;
    m_volume = bounded;
    if (m_playbin)
        g_object_set(m_playbin, "volume", m_volume, nullptr);
    emit volumeChanged();
}

void PlaybackEngine::pollBus()
{
    if (!m_bus)
        return;
    while (GstMessage *message = gst_bus_pop(m_bus)) {
        switch (GST_MESSAGE_TYPE(message)) {
        case GST_MESSAGE_ELEMENT: {
            const GstStructure *structure = gst_message_get_structure(message);
            if (structure && gst_structure_has_name(structure, "GstCacheDownloadComplete")) {
                const char *location = gst_structure_get_string(structure, "location");
                if (location && m_downloading) {
                    m_downloading = false;
                    m_downloadProgress = 1;
                    m_downloadTimer.stop();
                    // Completion can precede the sparse file's final stdio flush.
                    // Retain it until the pipeline closes before publishing a cache entry.
                    g_object_set(GST_MESSAGE_SRC(message), "temp-remove", FALSE, nullptr);
                    m_completedDownload = QString::fromUtf8(location);
                    emit bufferingChanged();
                }
            }
            break;
        }
        case GST_MESSAGE_ASYNC_DONE:
            updateSeekable();
            updatePosition();
            if (m_pendingPositionMs >= 0) {
                const qint64 position = m_pendingPositionMs;
                m_pendingPositionMs = -1;
                seek(position);
                if (m_requestedPlaying)
                    gst_element_set_state(m_playbin, GST_STATE_PLAYING);
                else
                    setState(QStringLiteral("Paused"));
            }
            break;
        case GST_MESSAGE_ERROR: {
            GError *error = nullptr;
            gchar *debug = nullptr;
            gst_message_parse_error(message, &error, &debug);
            setErrorMessage(gstErrorMessage(error, debug));
            if (error)
                g_error_free(error);
            g_free(debug);
            m_requestedPlaying = false;
            setState(QStringLiteral("Error"));
            break;
        }
        case GST_MESSAGE_EOS:
            m_requestedPlaying = false;
            if (m_durationMs > 0 && m_positionMs != m_durationMs) {
                m_positionMs = m_durationMs;
                emit positionChanged();
            }
            setState(QStringLiteral("Stopped"));
            emit endOfStream();
            break;
        case GST_MESSAGE_DURATION_CHANGED:
            updatePosition();
            break;
        case GST_MESSAGE_BUFFERING: {
            gint percent = 100;
            gst_message_parse_buffering(message, &percent);
            m_bufferingPercent = percent;
            emit bufferingChanged();
            if (percent < 100 && m_requestedPlaying) {
                gst_element_set_state(m_playbin, GST_STATE_PAUSED);
                setState(QStringLiteral("Loading"));
            } else if (percent == 100 && m_requestedPlaying) {
                gst_element_set_state(m_playbin, GST_STATE_PLAYING);
            }
            break;
        }
        case GST_MESSAGE_STATE_CHANGED:
            if (GST_MESSAGE_SRC(message) == GST_OBJECT(m_playbin)) {
                GstState oldState;
                GstState newState;
                GstState pending;
                gst_message_parse_state_changed(message, &oldState, &newState, &pending);
                Q_UNUSED(oldState)
                Q_UNUSED(pending)
                if (newState == GST_STATE_PLAYING)
                    setState(QStringLiteral("Playing"));
                else if (newState == GST_STATE_PAUSED)
                    setState(m_requestedPlaying ? QStringLiteral("Loading")
                                                : QStringLiteral("Paused"));
                else if (newState <= GST_STATE_READY && !m_requestedPlaying)
                    setState(QStringLiteral("Stopped"));
                updateSeekable();
            }
            break;
        default:
            break;
        }
        gst_message_unref(message);
    }
}

void PlaybackEngine::updatePosition()
{
    if (!m_playbin || m_source.isEmpty())
        return;
    gint64 value = GST_CLOCK_TIME_NONE;
    if (m_pendingPositionMs < 0
        && gst_element_query_position(m_playbin, GST_FORMAT_TIME, &value)
        && value >= 0) {
        const qint64 milliseconds = value / GST_MSECOND;
        if (milliseconds != m_positionMs) {
            m_positionMs = milliseconds;
            emit positionChanged();
        }
    }
    value = GST_CLOCK_TIME_NONE;
    if (gst_element_query_duration(m_playbin, GST_FORMAT_TIME, &value)
        && value >= 0) {
        setDuration(value / GST_MSECOND);
    }
}

void PlaybackEngine::setState(const QString &state)
{
    if (m_state == state)
        return;
    m_state = state;
    if (state == QLatin1String("Error")) m_downloadFailed = true;
    // Position polling only matters while frames are advancing; keep the
    // timer stopped for every other state so idle playback costs no wakeups.
    if (m_state == QStringLiteral("Playing"))
        m_positionTimer.start();
    else
        m_positionTimer.stop();
    if (m_state == QStringLiteral("Loading"))
        m_loadingTimeout.start();
    else
        m_loadingTimeout.stop();
    if (m_state == QStringLiteral("Error") || m_state == QStringLiteral("Stopped"))
        m_downloadTimer.stop();
    emit stateChanged();
}

void PlaybackEngine::finishDownload()
{
    const QString path = std::exchange(m_completedDownload, {});
    if (path.isEmpty())
        return;
    if (!m_downloadFailed)
        emit downloadCompleted(path);
    // The cache receiver moves accepted entries; rejected/unclaimed files are removed.
    QFile::remove(path);
}

void PlaybackEngine::updateDownloadProgress()
{
    if (!m_downloading)
        return;
    GstQuery *query = gst_query_new_buffering(GST_FORMAT_PERCENT);
    if (gst_element_query(m_playbin, query)) {
        gint64 covered = 0;
        for (guint i = 0; i < gst_query_get_n_buffering_ranges(query); ++i) {
            gint64 start = 0, stop = 0;
            if (gst_query_parse_nth_buffering_range(query, i, &start, &stop))
                covered += std::max<gint64>(0, stop - start);
        }
        const double progress = std::clamp(double(covered) / GST_FORMAT_PERCENT_MAX, 0.0, 1.0);
        if (progress != m_downloadProgress) {
            m_downloadProgress = progress;
            emit bufferingChanged();
        }
    }
    gst_query_unref(query);
}

void PlaybackEngine::setErrorMessage(const QString &message)
{
    if (m_errorMessage == message)
        return;
    m_errorMessage = message;
    emit errorMessageChanged();
}

void PlaybackEngine::setDuration(qint64 durationMs)
{
    if (m_durationMs == durationMs)
        return;
    m_durationMs = durationMs;
    emit durationChanged();
}

void PlaybackEngine::updateSeekable()
{
    if (!m_playbin)
        return;
    GstQuery *query = gst_query_new_seeking(GST_FORMAT_TIME);
    gboolean seekable = FALSE;
    if (gst_element_query(m_playbin, query)) {
        GstFormat format;
        gint64 start;
        gint64 end;
        gst_query_parse_seeking(query, &format, &seekable, &start, &end);
    }
    gst_query_unref(query);
    const bool value = seekable;
    if (m_seekable == value)
        return;
    m_seekable = value;
    emit seekableChanged();
}
