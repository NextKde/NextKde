#pragma once
#include <QLocalServer>
#include <QLockFile>
#include <QPointer>
#include <QQuickWindow>
#include <QLocalSocket>

namespace listenfree {
// The data-directory lock is acquired before SQLite, audio or SourceHost start.
class SingleInstance final : public QObject {
    Q_OBJECT
public:
    enum class Result { Primary, Forwarded, Error };
    explicit SingleInstance(const QString& dataDirectory, QObject* parent = nullptr);
    Result acquire(const QStringList& files = {});
    void setWindow(QQuickWindow* window);
    QString errorString() const { return error_; }
signals:
    void filesRequested(const QStringList& files);
private:
    QLockFile lock_;
    QLocalServer server_;
    QString serverName_, error_, pendingToken_;
    QStringList pendingFiles_;
    QPointer<QQuickWindow> window_;
    bool pendingActivation_{};
    QPointer<QLocalSocket> activationSocket_;
    Qt::WindowState presentedState_{Qt::WindowNoState};
    void activate(const QString& token, const QStringList& files = {});
    void activateInNextKde();
};
}
