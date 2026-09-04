#pragma once

#include <QObject>
#include <QTimer>
#include <QUrl>
#include <QVariantList>

typedef struct _GstElement GstElement;
typedef struct _GstBus GstBus;
typedef struct _GstPad GstPad;

class Transcoder : public QObject {
    Q_OBJECT

public:
    explicit Transcoder(QObject *parent = nullptr);
    ~Transcoder() override;

    QVariantList availableFormats() const;
    bool active() const;
    double progress() const;
    QString status() const;
    QString errorMessage() const;

    bool start(const QUrl &input, const QUrl &output, const QString &formatId,
               bool overwrite = false);
    void cancel();

signals:
    void availableFormatsChanged();
    void activeChanged();
    void progressChanged();
    void statusChanged();
    void errorMessageChanged();
    void finished(const QUrl &output);

private slots:
    void pollBus();
    void updateProgress();

private:
    struct Format {
        QString id;
        QString label;
        QString extension;
        QByteArray encoder;
        QByteArray muxer;
    };

    static void onPadAdded(GstElement *source, GstPad *pad, void *userData);
    void handlePadAdded(GstPad *pad);
    void setStatus(const QString &status);
    void setError(const QString &message);
    void destroyPipeline(bool removeTemporaryFile);
    const Format *findFormat(const QString &id) const;

    QList<Format> m_formats;
    GstElement *m_pipeline = nullptr;
    GstElement *m_audioQueue = nullptr;
    GstBus *m_bus = nullptr;
    QTimer m_busTimer;
    QTimer m_progressTimer;
    QUrl m_outputUrl;
    QString m_temporaryPath;
    QString m_status = QStringLiteral("Idle");
    QString m_errorMessage;
    double m_progress = 0.0;
};
