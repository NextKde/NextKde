#pragma once

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
    void downloadNext(int index);
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
