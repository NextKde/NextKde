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

    bool load(const QUrl &source, bool autoPlay = true);
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

private slots:
    void pollBus();
    void updatePosition();

private:
    void setState(const QString &state);
    void setErrorMessage(const QString &message);
    void setDuration(qint64 durationMs);
    void updateSeekable();

    GstElement *m_playbin = nullptr;
    GstBus *m_bus = nullptr;
    QTimer m_busTimer;
    QTimer m_positionTimer;
    QUrl m_source;
    QString m_backendName;
    QString m_state = QStringLiteral("Stopped");
    QString m_errorMessage;
    qint64 m_positionMs = 0;
    qint64 m_durationMs = 0;
    double m_volume = 0.8;
    bool m_seekable = false;
    bool m_requestedPlaying = false;
};
