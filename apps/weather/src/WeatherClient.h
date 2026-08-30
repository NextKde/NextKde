#pragma once

#include <QByteArray>
#include <QFileSystemWatcher>
#include <QLocalSocket>
#include <QObject>
#include <QQueue>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <qqmlintegration.h>

class WeatherClient final : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool ready READ ready NOTIFY snapshotChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY snapshotChanged)
    Q_PROPERTY(bool stale READ stale NOTIFY snapshotChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY searchingChanged)
    Q_PROPERTY(QString status READ status NOTIFY snapshotChanged)
    Q_PROPERTY(QString units READ units NOTIFY snapshotChanged)
    Q_PROPERTY(QString errorMessage READ errorMessage NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantMap location READ location NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList locations READ locations NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantMap current READ current NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList hourly READ hourly NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList daily READ daily NOTIFY snapshotChanged)
    Q_PROPERTY(QVariantList searchResults READ searchResults NOTIFY searchResultsChanged)
    Q_PROPERTY(qint64 fetchedAt READ fetchedAt NOTIFY snapshotChanged)
    Q_PROPERTY(qint64 staleAt READ staleAt NOTIFY snapshotChanged)

public:
    explicit WeatherClient(QObject *parent = nullptr);

    bool ready() const;
    bool connected() const;
    bool loading() const;
    bool stale() const;
    bool searching() const;
    QString status() const;
    QString units() const;
    QString errorMessage() const;
    QVariantMap location() const;
    QVariantList locations() const;
    QVariantMap current() const;
    QVariantList hourly() const;
    QVariantList daily() const;
    QVariantList searchResults() const;
    qint64 fetchedAt() const;
    qint64 staleAt() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void searchLocations(const QString &query);
    Q_INVOKABLE void selectLocation(const QVariantMap &location);
    Q_INVOKABLE void setUnits(const QString &units);
    Q_INVOKABLE void clearSearch();

signals:
    void snapshotChanged();
    void connectedChanged();
    void searchingChanged();
    void searchResultsChanged();

private:
    void connectSocket();
    void onSocketConnected();
    void onSocketDisconnected();
    void onSocketError(QLocalSocket::LocalSocketError error);
    void readSocketLines();
    void processSocketLine(const QByteArray &line);
    void sendRequest(const QVariantMap &request);
    void flushRequests();
    void reloadSnapshot();
    void ensureSnapshotWatch();
    void setTransportError(const QString &message);

    QString m_snapshotDirectory;
    QString m_snapshotPath;
    QString m_socketPath;
    QLocalSocket m_socket;
    QFileSystemWatcher m_watcher;
    QTimer m_reconnectTimer;
    QTimer m_snapshotFallbackTimer;
    QByteArray m_readBuffer;
    QQueue<QByteArray> m_pendingRequests;

    bool m_ready = false;
    bool m_loading = false;
    bool m_searching = false;
    QString m_status = QStringLiteral("idle");
    QString m_units = QStringLiteral("metric");
    QString m_errorMessage;
    QVariantMap m_location;
    QVariantList m_locations;
    QVariantMap m_current;
    QVariantList m_hourly;
    QVariantList m_daily;
    QVariantList m_searchResults;
    qint64 m_fetchedAt = 0;
    qint64 m_staleAt = 0;
};
