#pragma once

#include <QElapsedTimer>
#include <QFile>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>

// One process owns each operation, independently of the lifetime of its QML page.
class AppStore final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap music READ music NOTIFY changed)
public:
    explicit AppStore(const QString& resourcesDirectory, QObject* parent = nullptr);
    ~AppStore() override;
    QVariantMap music() const { return m_state; }
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void install();
    Q_INVOKABLE void uninstall();
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void open();
    Q_INVOKABLE void openLog();
    Q_INVOKABLE void openRepository();
signals:
    void changed();
private:
    void begin(const QString& action);
    friend class AppStoreTest;
    void downloadNext(int index, int attempt = 1);
    void scheduleRetry(int index, int attempt);
    void processStage(const QString& stage);
    void run(const QString& action);
    void consumeOutput();
    void consumeLine(const QByteArray& line);
    void finish(int exitCode, QProcess::ExitStatus status);
    void fail(const QString& code, const QString& message = {});
    void setStage(const QString& stage);
    void appendLog(const QByteArray& bytes);
    QString installerDirectory() const;
    QString dataDirectory() const;
    bool validFile(const QString& relative) const;
    void stopProcess(int signal);

    QVariantMap m_state;
    QJsonObject m_release;
    QFile m_log;
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_reply;
    QProcess m_process;
    QTimer m_killTimer;
    QTimer m_deadline;
    QTimer m_retryTimer;
    QTimer m_elapsedTimer;
    QElapsedTimer m_elapsed;
    // Milliseconds; tests shorten these deadlines without running real installers.
    QString m_downloadBaseUrl = QStringLiteral("https://raw.githubusercontent.com/NextKde/KMusic/");
    int m_bootstrapTimeout = 30000;
    int m_downloadTimeout = 5 * 60 * 1000;
    int m_retryDelay = 2000;
    int m_sourceAttempt = 1;
    int m_retryIndex = 0;
    int m_retryAttempt = 1;
    bool m_leftDownload = false;
    QString m_timeoutCode;
    QByteArray m_output;
    QJsonObject m_result;
    QString m_requestedAction;
    QString m_action;
    bool m_protocolError = false;
    bool m_cancelled = false;
    bool m_published = false;
    int m_resultCount = 0;
    qint64 m_processGroup = 0;
};
