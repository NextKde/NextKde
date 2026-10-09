#include "single_instance.h"
#include "media_arguments.h"
#include <QCryptographicHash>
#include <QDir>
#include <QElapsedTimer>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QLocalSocket>
#include <QStandardPaths>
#include <QThread>
#include <QTimer>
#include <QUuid>
#include <KWindowSystem>
#include <utility>

namespace listenfree {
SingleInstance::SingleInstance(const QString& directory, QObject* parent)
    : QObject(parent), lock_(QDir(directory).filePath(".instance.lock")) {
    const auto identity = QFileInfo(directory).canonicalFilePath();
    serverName_ = "kos-listenfree-" + QString::fromLatin1(
        QCryptographicHash::hash(identity.toUtf8(), QCryptographicHash::Sha256).toHex().left(32));
    lock_.setStaleLockTime(0);
    server_.setSocketOptions(QLocalServer::UserAccessOption);
    connect(&server_, &QLocalServer::newConnection, this, [this] {
        while (auto* socket = server_.nextPendingConnection()) {
            socket->setReadBufferSize(65536);
            connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
            const auto read = [this, socket] {
                if (!socket->canReadLine()) {
                    if (socket->bytesAvailable() >= 65536) socket->disconnectFromServer();
                    return;
                }
                const auto request = QJsonDocument::fromJson(socket->readLine(65536)).object();
                if (request.value("command") != "activate") { socket->disconnectFromServer(); return; }
                QStringList files;
                for (const auto& file : request.value("files").toArray()) {
                    if (QFileInfo(file.toString()).isAbsolute()) files.append(file.toString());
                    if (files.size() == 64) break;
                }
                activate(request.value("token").toString().left(4096), mediaFilesFromArguments(files));
                socket->write("ok\n");
                socket->flush();
                socket->disconnectFromServer();
            };
            connect(socket, &QLocalSocket::readyRead, this, read);
            read();
        }
    });
}

SingleInstance::Result SingleInstance::acquire(const QStringList& files) {
    if (lock_.tryLock()) {
        pendingFiles_ = files;
        QLocalServer::removeServer(serverName_); // Only the lock owner removes a stale socket.
        if (server_.listen(serverName_)) return Result::Primary;
        error_ = server_.errorString();
        return Result::Error;
    }
    if (lock_.error() != QLockFile::LockFailedError) {
        error_ = tr("无法锁定 KOS ListenFree 的数据目录。");
        return Result::Error;
    }
    QElapsedTimer elapsed; elapsed.start();
    while (elapsed.elapsed() < 5000) {
        QLocalSocket socket;
        socket.connectToServer(serverName_);
        if (socket.waitForConnected(150)) {
            const auto message = QJsonDocument(QJsonObject{{"command", "activate"},
                {"files", QJsonArray::fromStringList(files)},
                {"token", QString::fromUtf8(qgetenv("XDG_ACTIVATION_TOKEN")).left(4096)}})
                .toJson(QJsonDocument::Compact) + '\n';
            if (message.size() > 65536) { error_ = tr("一次打开的文件过多，请分批打开。"); return Result::Error; }
            socket.write(message);
            socket.flush();
            const int remaining = qMax(1, 5000 - int(elapsed.elapsed()));
            if (socket.canReadLine() || socket.waitForReadyRead(remaining)) {
                if (socket.readLine().trimmed() == "ok") return Result::Forwarded;
            }
            break;
        }
        QThread::msleep(40); // The primary may still be binding its socket.
    }
    error_ = tr("KOS ListenFree 已运行，但暂时无法激活窗口。请稍后重试。");
    return Result::Error;
}

void SingleInstance::activate(const QString& token, const QStringList& files) {
    if (!window_) {
        pendingActivation_ = true; pendingToken_ = token;
        for (const auto& file : files) if (!pendingFiles_.contains(file) && pendingFiles_.size() < 64) pendingFiles_.append(file);
        return;
    }
    if (!files.isEmpty()) emit filesRequested(files);
    if (!token.isEmpty()) KWindowSystem::setCurrentXdgActivationToken(token);
    if (window_->windowState() == Qt::WindowMinimized) {
        if (presentedState_ == Qt::WindowFullScreen) window_->showFullScreen();
        else if (presentedState_ == Qt::WindowMaximized) window_->showMaximized();
        else window_->showNormal();
    } else if (!window_->isVisible()) window_->show();
    window_->raise();
    KWindowSystem::activateWindow(window_);
    if (QGuiApplication::platformName().startsWith("wayland")) activateInNextKde();
}

void SingleInstance::activateInNextKde() {
    // Use the same compositor activation path as the NextKDE Dock. Wayland
    // does not expose minimized state to Qt, and terminal launches may lack
    // an activation token. Keeping the surface preserves restore geometry,
    // fullscreen state and scene-graph resources.
    if (activationSocket_) return;
    auto* socket = new QLocalSocket(this);
    activationSocket_ = socket;
    socket->setReadBufferSize(2 * 1024 * 1024);
    connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
    connect(socket, &QLocalSocket::errorOccurred, socket, &QObject::deleteLater);
    QTimer::singleShot(4000, socket, &QObject::deleteLater);
    const auto write = [socket](const QString& id, const QString& op, const QJsonObject& payload = {}) {
        socket->write(QJsonDocument(QJsonObject{{"version", 1}, {"requestId", id},
            {"operation", op}, {"payload", payload}}).toJson(QJsonDocument::Compact) + '\n');
        socket->flush();
    };
    connect(socket, &QLocalSocket::connected, this, [write] { write("listenfree-snapshot", "kwin.subscribe"); });
    connect(socket, &QLocalSocket::readyRead, this, [this, socket, write] {
        while (socket->canReadLine()) {
            const auto message = QJsonDocument::fromJson(socket->readLine()).object();
            if (message.value("requestId") == "listenfree-activate" && !message.value("ok").toBool()) {
                socket->disconnectFromServer(); return;
            }
            if (message.value("event") == "window.action") {
                const auto result = message.value("payload").toObject();
                if (result.value("ticket").toString() != socket->property("ticket").toString()
                    || !socket->property("activationSent").toBool()) continue;
                socket->disconnectFromServer(); return;
            }
            if (message.value("event") != "window.snapshot" || !window_) continue;
            for (const auto& value : message.value("payload").toObject().value("windows").toArray()) {
                const auto row = value.toObject();
                const auto title = row.value("title").toString();
                if (row.value("pid").toInteger() != QCoreApplication::applicationPid()
                    || (title != window_->title() && !title.startsWith(window_->title() + " —"))) continue;
                if (socket->property("activationSent").toBool()) return;
                const auto id = row.value("id").toString();
                if (id.isEmpty()) continue;
                socket->setProperty("activationSent", true);
                const auto ticket = QUuid::createUuid().toString(QUuid::WithoutBraces);
                socket->setProperty("ticket", ticket);
                write("listenfree-activate", "kwin.command", {{"action", "activate"}, {"id", id}, {"ticket", ticket}});
                return;
            }
        }
    });
    socket->connectToServer(QDir(QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation)).filePath("kos-platform.sock"));
}

void SingleInstance::setWindow(QQuickWindow* window) {
    window_ = window;
    presentedState_ = window->windowState();
    connect(window, &QWindow::windowStateChanged, this, [this](Qt::WindowState state) {
        if (state != Qt::WindowMinimized) presentedState_ = state;
    });
    if (pendingActivation_) { pendingActivation_ = false; activate(std::exchange(pendingToken_, {})); }
    if (!pendingFiles_.isEmpty()) emit filesRequested(std::exchange(pendingFiles_, {}));
}
}
