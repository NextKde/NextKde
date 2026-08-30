#include "Transcoder.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUuid>

#include <gst/gst.h>

#include <algorithm>

namespace {

bool elementAvailable(const QByteArray &name)
{
    GstElementFactory *factory = gst_element_factory_find(name.constData());
    if (!factory)
        return false;
    gst_object_unref(factory);
    return true;
}

QString messageText(GError *error, gchar *debug)
{
    QString result = error ? QString::fromUtf8(error->message)
                           : QStringLiteral("Unknown transcoder error");
    if (debug && *debug)
        result += QStringLiteral(" (%1)").arg(QString::fromUtf8(debug));
    return result;
}

} // namespace

Transcoder::Transcoder(QObject *parent)
    : QObject(parent)
{
    gst_init(nullptr, nullptr);
    const QList<Format> candidates{
        {QStringLiteral("flac"), QStringLiteral("FLAC"), QStringLiteral("flac"),
         QByteArrayLiteral("flacenc"), {}},
        {QStringLiteral("vorbis"), QStringLiteral("Ogg Vorbis"), QStringLiteral("ogg"),
         QByteArrayLiteral("vorbisenc"), QByteArrayLiteral("oggmux")},
        {QStringLiteral("opus"), QStringLiteral("Opus"), QStringLiteral("opus"),
         QByteArrayLiteral("opusenc"), QByteArrayLiteral("oggmux")},
        {QStringLiteral("wav"), QStringLiteral("WAV"), QStringLiteral("wav"),
         QByteArrayLiteral("wavenc"), {}},
        {QStringLiteral("mp3"), QStringLiteral("MP3"), QStringLiteral("mp3"),
         QByteArrayLiteral("lamemp3enc"), {}},
    };
    for (const Format &candidate : candidates) {
        if (elementAvailable(candidate.encoder)
            && (candidate.muxer.isEmpty() || elementAvailable(candidate.muxer))) {
            m_formats.append(candidate);
        }
    }
    m_busTimer.setInterval(50);
    connect(&m_busTimer, &QTimer::timeout, this, &Transcoder::pollBus);
    m_progressTimer.setInterval(250);
    connect(&m_progressTimer, &QTimer::timeout, this, &Transcoder::updateProgress);
}

Transcoder::~Transcoder()
{
    destroyPipeline(true);
}

QVariantList Transcoder::availableFormats() const
{
    QVariantList result;
    for (const Format &format : m_formats) {
        result.append(QVariantMap{
            {QStringLiteral("id"), format.id},
            {QStringLiteral("label"), format.label},
            {QStringLiteral("extension"), format.extension},
        });
    }
    return result;
}

bool Transcoder::active() const
{
    return m_pipeline != nullptr;
}

double Transcoder::progress() const
{
    return m_progress;
}

QString Transcoder::status() const
{
    return m_status;
}

QString Transcoder::errorMessage() const
{
    return m_errorMessage;
}

bool Transcoder::start(const QUrl &input, const QUrl &output, const QString &formatId,
                       bool overwrite)
{
    if (active()) {
        setError(QStringLiteral("Another conversion is already running"));
        return false;
    }
    const Format *format = findFormat(formatId);
    if (!format) {
        setError(QStringLiteral("The selected encoder is not installed"));
        return false;
    }
    if (!input.isLocalFile() || !QFileInfo::exists(input.toLocalFile())
        || !output.isLocalFile()) {
        setError(QStringLiteral("Conversion requires local input and output files"));
        return false;
    }
    const QFileInfo outputInfo(output.toLocalFile());
    if (outputInfo.exists() && !overwrite) {
        setError(QStringLiteral("The output file already exists"));
        return false;
    }
    if (!QDir().mkpath(outputInfo.absolutePath())) {
        setError(QStringLiteral("Unable to create the output directory"));
        return false;
    }

    m_temporaryPath = outputInfo.absoluteDir().filePath(
        QStringLiteral(".%1.kosmusic-part-%2").arg(outputInfo.fileName(),
            QUuid::createUuid().toString(QUuid::WithoutBraces)));
    m_pipeline = gst_pipeline_new("kos-music-transcoder");
    GstElement *source = gst_element_factory_make("uridecodebin3", "source");
    if (!source)
        source = gst_element_factory_make("uridecodebin", "source");
    m_audioQueue = gst_element_factory_make("queue", "audio-queue");
    GstElement *convert = gst_element_factory_make("audioconvert", "convert");
    GstElement *resample = gst_element_factory_make("audioresample", "resample");
    GstElement *encoder = gst_element_factory_make(format->encoder.constData(), "encoder");
    GstElement *muxer = format->muxer.isEmpty()
        ? nullptr : gst_element_factory_make(format->muxer.constData(), "muxer");
    GstElement *sink = gst_element_factory_make("filesink", "sink");
    if (!m_pipeline || !source || !m_audioQueue || !convert || !resample || !encoder
        || !sink || (!format->muxer.isEmpty() && !muxer)) {
        setError(QStringLiteral("Unable to construct the conversion pipeline"));
        if (source)
            gst_object_unref(source);
        if (m_audioQueue)
            gst_object_unref(m_audioQueue);
        if (convert)
            gst_object_unref(convert);
        if (resample)
            gst_object_unref(resample);
        if (encoder)
            gst_object_unref(encoder);
        if (muxer)
            gst_object_unref(muxer);
        if (sink)
            gst_object_unref(sink);
        destroyPipeline(true);
        return false;
    }

    const QByteArray inputUri = input.toEncoded();
    const QByteArray outputPath = QFile::encodeName(m_temporaryPath);
    g_object_set(source, "uri", inputUri.constData(), nullptr);
    g_object_set(sink, "location", outputPath.constData(), nullptr);
    gst_bin_add_many(GST_BIN(m_pipeline), source, m_audioQueue, convert, resample,
                     encoder, nullptr);
    if (muxer)
        gst_bin_add(GST_BIN(m_pipeline), muxer);
    gst_bin_add(GST_BIN(m_pipeline), sink);
    bool linked = gst_element_link_many(m_audioQueue, convert, resample, encoder, nullptr);
    linked = linked && (muxer ? gst_element_link_many(encoder, muxer, sink, nullptr)
                              : gst_element_link(encoder, sink));
    if (!linked) {
        setError(QStringLiteral("The selected encoder could not be linked"));
        destroyPipeline(true);
        return false;
    }
    g_signal_connect(source, "pad-added", G_CALLBACK(Transcoder::onPadAdded), this);
    m_bus = gst_element_get_bus(m_pipeline);
    m_outputUrl = output;
    m_progress = 0.0;
    emit progressChanged();
    setError({});
    setStatus(QStringLiteral("Converting"));
    m_busTimer.start();
    m_progressTimer.start();
    emit activeChanged();
    if (gst_element_set_state(m_pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        setError(QStringLiteral("GStreamer could not start the conversion"));
        destroyPipeline(true);
        setStatus(QStringLiteral("Failed"));
        return false;
    }
    return true;
}

void Transcoder::cancel()
{
    if (!active())
        return;
    destroyPipeline(true);
    setStatus(QStringLiteral("Cancelled"));
}

void Transcoder::pollBus()
{
    if (!m_bus)
        return;
    while (GstMessage *message = gst_bus_pop(m_bus)) {
        if (GST_MESSAGE_TYPE(message) == GST_MESSAGE_ERROR) {
            GError *error = nullptr;
            gchar *debug = nullptr;
            gst_message_parse_error(message, &error, &debug);
            const QString text = messageText(error, debug);
            if (error)
                g_error_free(error);
            g_free(debug);
            gst_message_unref(message);
            setError(text);
            destroyPipeline(true);
            setStatus(QStringLiteral("Failed"));
            return;
        }
        if (GST_MESSAGE_TYPE(message) == GST_MESSAGE_EOS) {
            gst_message_unref(message);
            const QUrl completedOutput = m_outputUrl;
            const QString temporaryPath = m_temporaryPath;
            destroyPipeline(false);
            if (QFileInfo::exists(completedOutput.toLocalFile()))
                QFile::remove(completedOutput.toLocalFile());
            if (!QFile::rename(temporaryPath, completedOutput.toLocalFile())) {
                QFile::remove(temporaryPath);
                setError(QStringLiteral("Unable to finalize the converted file"));
                setStatus(QStringLiteral("Failed"));
                return;
            }
            m_progress = 1.0;
            emit progressChanged();
            setStatus(QStringLiteral("Completed"));
            emit finished(completedOutput);
            return;
        }
        gst_message_unref(message);
    }
}

void Transcoder::updateProgress()
{
    if (!m_pipeline)
        return;
    gint64 position = GST_CLOCK_TIME_NONE;
    gint64 duration = GST_CLOCK_TIME_NONE;
    if (!gst_element_query_position(m_pipeline, GST_FORMAT_TIME, &position)
        || !gst_element_query_duration(m_pipeline, GST_FORMAT_TIME, &duration)
        || duration <= 0) {
        return;
    }
    const double value = std::clamp(static_cast<double>(position)
                                        / static_cast<double>(duration),
                                    0.0, 1.0);
    if (qFuzzyCompare(m_progress, value))
        return;
    m_progress = value;
    emit progressChanged();
}

void Transcoder::onPadAdded(GstElement *, GstPad *pad, void *userData)
{
    static_cast<Transcoder *>(userData)->handlePadAdded(pad);
}

void Transcoder::handlePadAdded(GstPad *pad)
{
    if (!m_audioQueue)
        return;
    GstCaps *caps = gst_pad_get_current_caps(pad);
    if (!caps)
        caps = gst_pad_query_caps(pad, nullptr);
    const GstStructure *structure = caps && gst_caps_get_size(caps) > 0
        ? gst_caps_get_structure(caps, 0) : nullptr;
    const gchar *name = structure ? gst_structure_get_name(structure) : nullptr;
    if (name && g_str_has_prefix(name, "audio/")) {
        GstPad *sinkPad = gst_element_get_static_pad(m_audioQueue, "sink");
        if (sinkPad && !gst_pad_is_linked(sinkPad))
            gst_pad_link(pad, sinkPad);
        if (sinkPad)
            gst_object_unref(sinkPad);
    }
    if (caps)
        gst_caps_unref(caps);
}

void Transcoder::setStatus(const QString &status)
{
    if (m_status == status)
        return;
    m_status = status;
    emit statusChanged();
}

void Transcoder::setError(const QString &message)
{
    if (m_errorMessage == message)
        return;
    m_errorMessage = message;
    emit errorMessageChanged();
}

void Transcoder::destroyPipeline(bool removeTemporaryFile)
{
    const bool wasActive = active();
    m_busTimer.stop();
    m_progressTimer.stop();
    if (m_pipeline)
        gst_element_set_state(m_pipeline, GST_STATE_NULL);
    if (m_bus)
        gst_object_unref(m_bus);
    if (m_pipeline)
        gst_object_unref(m_pipeline);
    m_bus = nullptr;
    m_pipeline = nullptr;
    m_audioQueue = nullptr;
    if (removeTemporaryFile && !m_temporaryPath.isEmpty())
        QFile::remove(m_temporaryPath);
    m_temporaryPath.clear();
    if (wasActive)
        emit activeChanged();
}

const Transcoder::Format *Transcoder::findFormat(const QString &id) const
{
    const auto found = std::find_if(m_formats.cbegin(), m_formats.cend(),
                                    [&id](const Format &format) { return format.id == id; });
    return found == m_formats.cend() ? nullptr : &*found;
}
