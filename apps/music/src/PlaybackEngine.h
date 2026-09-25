#pragma once

#include <QObject>
#include <QTimer>
#include <QUrl>

typedef struct _GstElement GstElement;
typedef struct _GstBus GstBus;

class PlaybackEngine : public QObject {
    Q_OBJECT

public:
    explicit PlaybackEngine(QObject *parent = nullptr);
    ~PlaybackEngine() override;

    bool available() const;
    QString backendName() const;
    QString state() const;
    QString errorMessage() const;
    QUrl source() const;
    qint64 positionMs() const;
    qint64 durationMs() const;
    bool seekable() const;
    double volume() const;
    int bufferingPercent() const;
    double downloadProgress() const;
    void setDownloadDirectory(const QString &directory);

    bool load(const QUrl &source, bool autoPlay = true, qint64 startPositionMs = 0);
    void play();
    void pause();
    void stop();
    void seek(qint64 positionMs);
    void setVolume(double volume);

signals:
    void availableChanged();
    void stateChanged();
    void errorMessageChanged();
    void sourceChanged();
    void positionChanged();
    void durationChanged();
    void seekableChanged();
    void volumeChanged();
    void endOfStream();
    void seeked(qint64 positionMs);
    void bufferingChanged();
    void downloadCompleted(const QString &path);

private slots:
    void updatePosition();

private:
    Q_INVOKABLE void pollBus();

    void setState(const QString &state);
    void setErrorMessage(const QString &message);
    void setDuration(qint64 durationMs);
    void updateSeekable();
    void updateDownloadProgress();
    void finishDownload();

    GstElement *m_playbin = nullptr;
    GstBus *m_bus = nullptr;
    QTimer m_positionTimer;
    QTimer m_downloadTimer;
    QTimer m_loadingTimeout;
    QByteArray m_downloadTemplate;
    QUrl m_source;
    QString m_backendName;
    QString m_state = QStringLiteral("Stopped");
    QString m_errorMessage;
    qint64 m_positionMs = 0;
    qint64 m_durationMs = 0;
    qint64 m_pendingPositionMs = -1;
    double m_volume = 0.8;
    bool m_seekable = false;
    bool m_requestedPlaying = false;
    int m_bufferingPercent = 100;
    double m_downloadProgress = -1;
    bool m_downloading = false;
    bool m_downloadFailed = false;
    QString m_completedDownload;
};
