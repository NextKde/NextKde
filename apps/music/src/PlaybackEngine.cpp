#include "PlaybackEngine.h"

#include <QFileInfo>

#include <gst/gst.h>

#include <algorithm>

namespace {

QString gstErrorMessage(const GError *error, const gchar *debug)
{
    QString message = error ? QString::fromUtf8(error->message)
                            : QStringLiteral("Unknown GStreamer error");
    if (debug && *debug)
        message += QStringLiteral(" (%1)").arg(QString::fromUtf8(debug));
    return message;
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

    if (qEnvironmentVariableIsSet("KOS_MUSIC_FAKE_AUDIO")) {
        if (GstElement *sink = gst_element_factory_make("fakesink", "test-audio-sink")) {
            g_object_set(sink, "sync", TRUE, nullptr);
            g_object_set(m_playbin, "audio-sink", sink, nullptr);
            gst_object_unref(sink);
        }
    } else {
        const QByteArray requestedSink = qgetenv("KOS_MUSIC_AUDIO_SINK");
        if (!requestedSink.isEmpty()) {
            if (GstElement *sink = gst_element_factory_make(requestedSink.constData(),
                                                            "requested-audio-sink")) {
                g_object_set(m_playbin, "audio-sink", sink, nullptr);
                gst_object_unref(sink);
            }
        }
    }

    m_busTimer.setInterval(40);
    connect(&m_busTimer, &QTimer::timeout, this, &PlaybackEngine::pollBus);
    m_busTimer.start();
    m_positionTimer.setInterval(250);
    connect(&m_positionTimer, &QTimer::timeout, this, &PlaybackEngine::updatePosition);
    m_positionTimer.start();
}

PlaybackEngine::~PlaybackEngine()
{
    if (m_playbin)
        gst_element_set_state(m_playbin, GST_STATE_NULL);
    if (m_bus)
        gst_object_unref(m_bus);
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

bool PlaybackEngine::load(const QUrl &source, bool autoPlay)
{
    if (!m_playbin || !source.isValid())
        return false;
    if (source.isLocalFile() && !QFileInfo::exists(source.toLocalFile())) {
        setErrorMessage(QStringLiteral("Audio file no longer exists: %1")
                            .arg(source.toLocalFile()));
        setState(QStringLiteral("Error"));
        return false;
    }

    gst_element_set_state(m_playbin, GST_STATE_NULL);
    const QByteArray encodedUri = source.toEncoded();
    g_object_set(m_playbin, "uri", encodedUri.constData(), nullptr);
    m_source = source;
    m_positionMs = 0;
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
        m_playbin, autoPlay ? GST_STATE_PLAYING : GST_STATE_PAUSED);
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
    if (gst_element_set_state(m_playbin, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        setErrorMessage(QStringLiteral("Unable to start playback"));
        setState(QStringLiteral("Error"));
    }
}

void PlaybackEngine::pause()
{
    if (!m_playbin || m_source.isEmpty())
        return;
    m_requestedPlaying = false;
    if (gst_element_set_state(m_playbin, GST_STATE_PAUSED) == GST_STATE_CHANGE_FAILURE) {
        setErrorMessage(QStringLiteral("Unable to pause playback"));
        setState(QStringLiteral("Error"));
    }
}

void PlaybackEngine::stop()
{
    if (!m_playbin)
        return;
    m_requestedPlaying = false;
    gst_element_set_state(m_playbin, GST_STATE_READY);
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
    if (gst_element_query_position(m_playbin, GST_FORMAT_TIME, &value)) {
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
    emit stateChanged();
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
