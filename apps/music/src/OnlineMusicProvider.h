#pragma once

#include "MusicTypes.h"

#include <QNetworkAccessManager>
#include <QObject>

class OnlineMusicProvider final : public QObject {
    Q_OBJECT

public:
    explicit OnlineMusicProvider(QObject *parent = nullptr);

    bool searching() const;
    QString errorMessage() const;
    void search(const QString &query, int limit = 30);
    static QList<TrackRecord> parseNeteaseSearch(const QByteArray &payload,
                                                 QString *errorMessage = nullptr,
                                                 const QString &query = {});

signals:
    void searchingChanged();
    void resultsReady(const QList<TrackRecord> &tracks);
    void errorMessageChanged();

private:
    void setSearching(bool searching);
    void setError(const QString &message);

    QNetworkAccessManager m_network;
    QNetworkReply *m_reply = nullptr;
    QString m_errorMessage;
    quint64 m_generation = 0;
    bool m_searching = false;
};
