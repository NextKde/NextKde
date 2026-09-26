#pragma once

#include "MusicTypes.h"

#include <QHash>
#include <QNetworkAccessManager>
#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QVariantList>

class QNetworkReply;
class QTimer;

class LxSourceService final : public QObject {
    Q_OBJECT

public:
    explicit LxSourceService(QString dataPath, QObject *parent = nullptr);
    ~LxSourceService() override;

    QVariantList sources() const;
    QString activeSourceId() const;
    QString state() const;
    QString errorMessage() const;
    QStringList availableQualities(const QString &platform = QStringLiteral("wy")) const;

    void importSource(const QString &pathOrUrl);
    void activateSource(const QString &sourceId);
    void useSourceForPlayback(const QString &sourceId);
    void removeSource(const QString &sourceId);
    void resolve(qint64 trackId, const QString &platform,
                 const QString &sourceData, const QString &quality = QStringLiteral("128k"));
    void cancelResolves();

signals:
    void sourcesChanged();
    void stateChanged();
    void errorMessageChanged();
    void capabilitiesChanged();
    void sourceImported(const QString &name);
    void resolved(qint64 trackId, const QUrl &url);
    void resolveFailed(qint64 trackId, const QString &message);

private:
    struct PendingCommand {
        QString operation;
        qint64 trackId = -1;
        QTimer *timer = nullptr;
    };

    void loadIndex();
    bool saveIndex();
    void installScript(const QByteArray &script, const QString &origin);
    void startHost();
    void stopHost(bool notifyPending = true);
    void failHost(const QString &message);
    void sendLoad();
    QString sendCommand(const QJsonObject &command, const QString &operation,
                        qint64 trackId = -1);
    void readHostOutput();
    void handleHostReply(const QJsonObject &reply);
    QVariantMap sourceForId(const QString &sourceId) const;
    QString hostProgram() const;
    void setState(const QString &state);
    void setError(const QString &message);

    QString m_dataPath;
    QString m_sourcesPath;
    QVariantList m_sources;
    QString m_activeSourceId;
    QString m_runtimeSourceId;
    QString m_state = QStringLiteral("inactive");
    QString m_errorMessage;
    QHash<QString, QStringList> m_supportedQualities;
    QProcess m_host;
    QByteArray m_hostBuffer;
    QHash<QString, PendingCommand> m_pending;
    QNetworkAccessManager m_network;
    QNetworkReply *m_importReply = nullptr;
    bool m_stoppingHost = false;
};
