#pragma once

#include "MusicTypes.h"

#include <QNetworkAccessManager>
#include <QObject>
#include <QVariantList>

class QNetworkReply;

class LyricsService final : public QObject {
    Q_OBJECT

public:
    explicit LyricsService(QString cachePath, QObject *parent = nullptr);

    QVariantList lines() const;
    int currentLineIndex() const;
    qint64 loadedTrackId() const;
    bool loading() const;
    QString errorMessage() const;

    void load(const TrackRecord &track);
    void setPositionMs(qint64 positionMs);
    static QVariantList parseLrc(const QString &text);

signals:
    void lyricsChanged();
    void currentLineChanged();
    void loadingChanged();
    void errorMessageChanged();

private:
    void loadOnline(const TrackRecord &track);
    void applyLyrics(const QString &text, const QString &error = {});
    void setLoading(bool loading);
    void setError(const QString &message);
    QString cacheFile(const TrackRecord &track) const;

    QString m_cachePath;
    QVariantList m_lines;
    QNetworkAccessManager m_network;
    QNetworkReply *m_reply = nullptr;
    QString m_errorMessage;
    quint64 m_generation = 0;
    qint64 m_loadedTrackId = -1;
    int m_currentLineIndex = -1;
    bool m_loading = false;
};
