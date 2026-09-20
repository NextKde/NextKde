#include "KWinBridge.h"

#include <QDBusConnection>
#include <QDBusError>
#include <QDBusInterface>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusReply>
#include <QDBusUnixFileDescriptor>
#include <QDateTime>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QPointer>
#include <QQueue>
#include <QRegularExpression>
#include <QSet>
#include <QSocketNotifier>
#include <QStandardPaths>
#include <QSettings>
#include <QSize>
#include <QThreadPool>
#include <QTimer>
#include <QGuiApplication>
#include <QCoreApplication>
#include <QTextStream>

#include <QtConcurrent>

#include <KIconLoader>

#include <algorithm>
#include <atomic>
#include <array>
#include <cerrno>
#include <memory>
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>

namespace KosPlatform {
namespace {

KWinEventHandler g_eventHandler;
class Bridge;
Bridge *g_bridge = nullptr;

// KWin screenshot captures stream up to tens of MB of RGBA through a pipe.
// Running many at once multiplies that bandwidth and decode cost; keep a
// small concurrency window and park the rest on a bounded queue.
constexpr int kMaxThumbnailConcurrency = 2;
constexpr qsizetype kMaxThumbnailQueue = 32;

class Bridge final : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.kos.Platform")

public slots:
    // KWin effects expose animationStarted as a D-Bus signal. Keep the
    // subscription inside the resident platform process so Shell does not
    // need to spawn a gdbus monitor of its own.
    void AnimationStarted(const QString &appId, const QString &windowId,
                          const QString &transition, int durationMs)
    {
        publishEvent(QJsonObject{
            {QStringLiteral("type"), QStringLiteral("animation.started")},
            {QStringLiteral("appId"), appId},
            {QStringLiteral("windowId"), windowId},
            {QStringLiteral("transition"), transition},
            {QStringLiteral("durationMs"), durationMs},
        });
    }

    void Publish(const QString &payload)
    {
        QJsonParseError error;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &error);
        if (error.error != QJsonParseError::NoError || !document.isObject()) {
            QTextStream(stderr) << "Invalid KWin event: " << error.errorString() << Qt::endl;
            return;
        }

        QJsonObject event = document.object();
        if (event.value(QStringLiteral("type")) == QStringLiteral("snapshot")) {
            // Resolving each window's fallback icon can scan hundreds of
            // desktop files and the whole icon tree. Do it off the D-Bus
            // thread so geometry snapshots never stall the bridge.
            decorateSnapshotIcons(event);
            return;
        }
        publishEvent(event);
    }

    QString TakeCommand()
    {
        return m_commands.isEmpty() ? QString{} : m_commands.dequeue();
    }

    void Enqueue(const QString &payload)
    {
        QJsonParseError error;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &error);
        if (error.error != QJsonParseError::NoError || !document.isObject())
            return;

        const QString command = QString::fromUtf8(document.toJson(QJsonDocument::Compact));
        const QString action = document.object().value(QStringLiteral("action")).toString();

        // Thumbnail capture uses KWin's restricted ScreenShot2 API directly.
        // The KWin Script has no pixel access, but it already gives us the
        // authoritative UUID that ScreenShot2 accepts on Wayland.
        if (action == QStringLiteral("thumbnail")) {
            const QString id = document.object().value(QStringLiteral("id")).toString();
            if (!id.isEmpty())
                QTimer::singleShot(0, this, [this, id] { captureThumbnail(id); });
            return;
        }

        // A Dock click expresses the latest focus intent. Keeping older
        // activate requests makes rapid clicks feel delayed and can focus a
        // window the user has already moved away from. Preserve close and
        // minimize requests, but replace queued activations with the latest.
        if (action == QStringLiteral("activate")) {
            QQueue<QString> retained;
            while (!m_commands.isEmpty()) {
                const QString queued = m_commands.dequeue();
                QJsonParseError queuedError;
                const QJsonDocument queuedDocument = QJsonDocument::fromJson(
                    queued.toUtf8(), &queuedError);
                const bool isActivation = queuedError.error == QJsonParseError::NoError
                    && queuedDocument.isObject()
                    && queuedDocument.object().value(QStringLiteral("action")).toString()
                        == QStringLiteral("activate");
                if (!isActivation)
                    retained.enqueue(queued);
            }
            m_commands = retained;
        }

        m_commands.enqueue(command);
    }

    QString Ping() const
    {
        return QStringLiteral("ready");
    }

public:
    explicit Bridge(QObject *parent = nullptr)
        : QObject(parent)
    {
        // All icon work — the desktop-file index, KIconLoader lookups and the
        // full directory fallback scan — lives on this single worker thread.
        // One thread means the caches below need no locking and KIconLoader
        // is only ever touched from a thread it was constructed on.
        m_iconPool.setMaxThreadCount(1);
        // Prewarm the desktop index so the first window snapshot does not
        // wait for several hundred .desktop files to be parsed.
        const QPointer<Bridge> self(this);
        QtConcurrent::run(&m_iconPool, [self] {
            if (self)
                self->ensureDesktopIndex();
        });
    }

private:
    void publishEvent(const QJsonObject &event)
    {
        if (g_eventHandler)
            g_eventHandler(event);
        // Socket subscribers receive the event above. Full JSON on stdout is
        // diagnostic only; avoid serializing and flushing every geometry tick.
        static const bool traceEvents = qEnvironmentVariableIntValue("KOS_PLATFORM_TRACE_EVENTS") == 1;
        if (traceEvents) {
            QTextStream(stdout) << "EVENT "
                                << QJsonDocument(event).toJson(QJsonDocument::Compact)
                                << Qt::endl;
        }
    }

    void publishThumbnailError(const QString &id, const QString &message)
    {
        QJsonObject event;
        event.insert(QStringLiteral("type"), QStringLiteral("thumbnail"));
        event.insert(QStringLiteral("id"), id);
        event.insert(QStringLiteral("error"), message);
        publishEvent(event);
    }

    void publishThumbnailDebug(const QString &id, const QString &stage)
    {
        QJsonObject event;
        event.insert(QStringLiteral("type"), QStringLiteral("thumbnail-debug"));
        event.insert(QStringLiteral("id"), id);
        event.insert(QStringLiteral("stage"), stage);
        publishEvent(event);
    }

    // Runs on the D-Bus thread: hand the snapshot to the icon worker. During
    // a drag the script can publish several snapshots per second; each new
    // ticket supersedes the previous one, so stale snapshots are dropped
    // instead of queueing obsolete work ahead of the latest state.
    void decorateSnapshotIcons(const QJsonObject &event)
    {
        const quint64 ticket = ++m_iconTicket;
        const QPointer<Bridge> self(this);
        QtConcurrent::run(&m_iconPool, [self, ticket, event]() mutable {
            if (!self || ticket != self->m_iconTicket)
                return;
            QJsonObject decorated = event;
            QJsonArray windows = decorated.value(QStringLiteral("windows")).toArray();
            for (int i = 0; i < windows.size(); ++i) {
                QJsonObject window = windows.at(i).toObject();
                const QString icon = self->findFallbackIcon(
                    window.value(QStringLiteral("appId")).toString());
                if (!icon.isEmpty())
                    window.insert(QStringLiteral("iconPath"), icon);
                windows[i] = window;
            }
            decorated.insert(QStringLiteral("windows"), windows);
            QMetaObject::invokeMethod(self, [self, ticket, decorated] {
                if (self && ticket == self->m_iconTicket)
                    self->publishSnapshot(decorated);
            }, Qt::QueuedConnection);
        });
    }

    // Runs on the D-Bus thread after the icon worker stamps the ticket.
    void publishSnapshot(const QJsonObject &event)
    {
        // Thumbnails are keyed by KWin's window id, which dies with the
        // window. Diff against the snapshot so closed windows release their
        // PNG file and any queued capture request instead of leaking.
        QSet<QString> ids;
        const QJsonArray windows = event.value(QStringLiteral("windows")).toArray();
        for (const auto &value : windows)
            ids.insert(value.toObject().value(QStringLiteral("id")).toString());
        for (auto it = m_thumbnailPaths.begin(); it != m_thumbnailPaths.end();) {
            if (!ids.contains(it.key())) {
                QFile::remove(it.value());
                it = m_thumbnailPaths.erase(it);
            } else {
                ++it;
            }
        }
        if (!m_thumbnailQueue.isEmpty()) {
            QQueue<QString> retained;
            for (const QString &queuedId : std::as_const(m_thumbnailQueue)) {
                if (ids.contains(queuedId))
                    retained.enqueue(queuedId);
            }
            m_thumbnailQueue = retained;
        }
        m_lastWindowIds = ids;
        publishEvent(event);
    }

    void captureThumbnail(const QString &id)
    {
        if (m_thumbnailInFlight.contains(id) || m_thumbnailQueue.contains(id))
            return;
        if (int(m_thumbnailInFlight.size()) >= kMaxThumbnailConcurrency) {
            if (m_thumbnailQueue.size() < kMaxThumbnailQueue) {
                m_thumbnailQueue.enqueue(id);
            } else {
                // Reject explicitly so the shell's pending mark clears
                // instead of waiting on an event that never arrives.
                publishThumbnailError(id,
                    QStringLiteral("Thumbnail capture queue is full"));
            }
            return;
        }
        m_thumbnailInFlight.insert(id);
        beginThumbnailCapture(id);
    }

    void beginThumbnailCapture(const QString &id)
    {
        publishThumbnailDebug(id, QStringLiteral("begin"));

        int pipeFds[2];
        if (::pipe(pipeFds) != 0) {
            publishThumbnailError(id, QStringLiteral("Cannot create screenshot pipe"));
            endThumbnailCapture(id);
            return;
        }
        // Keep one local write descriptor so we can close it deterministically
        // after the D-Bus call. QDBusUnixFileDescriptor owns a duplicate.
        const int dbusWriteFd = ::dup(pipeFds[1]);
        if (dbusWriteFd == -1) {
            ::close(pipeFds[0]);
            ::close(pipeFds[1]);
            publishThumbnailError(id, QStringLiteral("Cannot duplicate screenshot pipe"));
            endThumbnailCapture(id);
            return;
        }

        // KWin may start writing the raw RGBA frame before it delivers the
        // delayed D-Bus reply. A 4K window readily exceeds a pipe buffer; if
        // we wait for that reply before reading, KWin and this process can
        // deadlock. Start draining immediately in a worker thread.
        const auto expectedBytes = std::make_shared<std::atomic<qint64>>(-1);
        const auto deadlineMs = std::make_shared<std::atomic<qint64>>(-1);
        auto pixelsFuture = QtConcurrent::run([readFd = pipeFds[0], expectedBytes, deadlineMs] {
            const auto cleanup = [readFd] { ::close(readFd); };
            const int flags = ::fcntl(readFd, F_GETFL);
            if (flags == -1 || ::fcntl(readFd, F_SETFL, flags | O_NONBLOCK) == -1) {
                cleanup();
                return QByteArray{};
            }
            QByteArray bytes;
            std::array<char, 64 * 1024> buffer;
            for (;;) {
                const qint64 expected = expectedBytes->load();
                if (expected >= 0 && bytes.size() >= expected) {
                    cleanup();
                    return bytes.left(expected);
                }
                const qint64 deadline = deadlineMs->load();
                if (expected >= 0 && deadline > 0
                        && QDateTime::currentMSecsSinceEpoch() >= deadline) {
                    cleanup();
                    return bytes;
                }

                pollfd pollFd = { readFd, POLLIN | POLLHUP, 0 };
                if (::poll(&pollFd, 1, 50) <= 0)
                    continue;
                const ssize_t bytesRead = ::read(readFd, buffer.data(), buffer.size());
                if (bytesRead > 0) {
                    bytes.append(buffer.data(), bytesRead);
                    continue;
                }
                if (bytesRead == -1 && (errno == EAGAIN || errno == EINTR))
                    continue;
                cleanup();
                if (bytesRead <= 0)
                    return bytes;
            }
        });

        QVariantMap options;
        options.insert(QStringLiteral("include-decoration"), true);
        // ScreenShot2 writes raw pixels to this descriptor after its D-Bus
        // reply describes the image dimensions and QImage format.
        QDBusUnixFileDescriptor writePipe(dbusWriteFd);
        QDBusInterface screenshot(QStringLiteral("org.kde.KWin"),
                                  QStringLiteral("/org/kde/KWin/ScreenShot2"),
                                  QStringLiteral("org.kde.KWin.ScreenShot2"));
        // Async so a slow or stuck KWin reply never blocks every other bridge
        // request; the pipe reader drains independently of the reply anyway.
        const QDBusPendingCall pending = screenshot.asyncCall(
            QStringLiteral("CaptureWindow"), id, options,
            QVariant::fromValue(writePipe));
        // Our own write end is a descriptor distinct from the one the message
        // owns; without this close the reader never sees EOF after KWin has
        // finished writing the frame.
        ::close(pipeFds[1]);

        auto *watcher = new QDBusPendingCallWatcher(pending, this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this,
                [this, id, expectedBytes, deadlineMs, pixelsFuture](QDBusPendingCallWatcher *self) {
            self->deleteLater();
            const QDBusPendingReply<QVariantMap> reply = *self;
            publishThumbnailDebug(id, reply.isError()
                ? QStringLiteral("dbus-error")
                : QStringLiteral("dbus-reply"));
            if (reply.isError()) {
                expectedBytes->store(0);
                // The reader exits on the expected-size check within one poll
                // cycle; reap it off-thread so this callback never blocks.
                QtConcurrent::run([pixelsFuture]() mutable { pixelsFuture.waitForFinished(); });
                publishThumbnailError(id, reply.error().message());
                endThumbnailCapture(id);
                return;
            }

            const QVariantMap result = reply.value();
            const int width = result.value(QStringLiteral("width")).toInt();
            const int height = result.value(QStringLiteral("height")).toInt();
            const int stride = result.value(QStringLiteral("stride")).toInt();
            const auto format = static_cast<QImage::Format>(
                result.value(QStringLiteral("format")).toInt());
            const qint64 expectedSize = qint64(stride) * height;
            publishThumbnailDebug(id, QStringLiteral("meta=%1x%2 stride=%3 format=%4 type=%5")
                .arg(width).arg(height).arg(stride).arg(int(format))
                .arg(result.value(QStringLiteral("type")).toString()));
            expectedBytes->store(std::max<qint64>(0, expectedSize));
            deadlineMs->store(QDateTime::currentMSecsSinceEpoch() + 4000);

            // A 4K frame is tens of MB of pixels plus a PNG encode; decode,
            // scale and save off the D-Bus thread.
            const quint64 serial = ++m_thumbnailSerial;
            const QPointer<Bridge> guard(this);
            QtConcurrent::run([guard, id, pixelsFuture, width, height, stride,
                               format, expectedSize, serial]() mutable {
                const QByteArray bytes = pixelsFuture.result();
                if (!guard)
                    return;
                QMetaObject::invokeMethod(guard, [guard, id] {
                    if (guard)
                        guard->publishThumbnailDebug(
                            id, QStringLiteral("pixels-drained"));
                }, Qt::QueuedConnection);

                auto fail = [guard, id](const QString &message) {
                    QMetaObject::invokeMethod(guard, [guard, id, message] {
                        if (!guard)
                            return;
                        guard->publishThumbnailError(id, message);
                        guard->endThumbnailCapture(id);
                    }, Qt::QueuedConnection);
                };
                if (width <= 0 || height <= 0 || stride <= 0
                        || format == QImage::Format_Invalid
                        || bytes.size() < expectedSize) {
                    fail(QStringLiteral("KWin returned an invalid screenshot"));
                    return;
                }

                QImage image(reinterpret_cast<const uchar *>(bytes.constData()),
                             width, height, stride, format);
                // The preview is rendered at roughly 316x184 logical pixels.
                // Keep a 2x source so it remains crisp on high-DPI outputs
                // rather than being upscaled by Qt Quick from a 360px
                // thumbnail.
                image = image.copy().scaled(QSize(720, 440), Qt::KeepAspectRatio,
                                            Qt::SmoothTransformation);
                if (image.isNull()) {
                    fail(QStringLiteral("Cannot decode KWin screenshot"));
                    return;
                }

                const QString runtimeDir = QStandardPaths::writableLocation(
                        QStandardPaths::RuntimeLocation)
                    + QStringLiteral("/quickshell/window-thumbnails");
                QDir().mkpath(runtimeDir);
                QString safeId = id;
                safeId.remove(QRegularExpression(QStringLiteral("[^A-Za-z0-9_-]")));
                const QString path = runtimeDir + QLatin1Char('/') + safeId
                    + QLatin1Char('-') + QString::number(serial)
                    + QStringLiteral(".png");
                if (!image.save(path, "PNG")) {
                    fail(QStringLiteral("Cannot save thumbnail PNG"));
                    return;
                }
                const int imageWidth = image.width();
                const int imageHeight = image.height();
                QMetaObject::invokeMethod(guard, [guard, id, path,
                                                  imageWidth, imageHeight] {
                    if (guard)
                        guard->finishThumbnail(id, path, imageWidth, imageHeight);
                }, Qt::QueuedConnection);
            });
        });
    }

    // Runs on the D-Bus thread once the worker saved the PNG.
    void finishThumbnail(const QString &id, const QString &path,
                         int width, int height)
    {
        // The window can close while a capture drains; drop the PNG instead of
        // handing the shell a file it would immediately discard.
        if (!m_lastWindowIds.isEmpty() && !m_lastWindowIds.contains(id)) {
            QFile::remove(path);
            endThumbnailCapture(id);
            return;
        }
        const QString previousPath = m_thumbnailPaths.value(id);
        if (!previousPath.isEmpty() && previousPath != path)
            QFile::remove(previousPath);
        m_thumbnailPaths.insert(id, path);
        endThumbnailCapture(id);

        QJsonObject event;
        event.insert(QStringLiteral("type"), QStringLiteral("thumbnail"));
        event.insert(QStringLiteral("id"), id);
        event.insert(QStringLiteral("path"), path);
        event.insert(QStringLiteral("width"), width);
        event.insert(QStringLiteral("height"), height);
        publishEvent(event);
    }

    void endThumbnailCapture(const QString &id)
    {
        m_thumbnailInFlight.remove(id);
        while (int(m_thumbnailInFlight.size()) < kMaxThumbnailConcurrency
                && !m_thumbnailQueue.isEmpty()) {
            const QString next = m_thumbnailQueue.dequeue();
            if (m_thumbnailInFlight.contains(next))
                continue;
            m_thumbnailInFlight.insert(next);
            beginThumbnailCapture(next);
        }
    }

    // Everything below runs exclusively on m_iconPool's single worker thread.

    static QString normalizeName(QString value) {
        value = value.toLower(); value.remove(QStringLiteral(".desktop"));
        QString result;
        for (const QChar c : value) if (c.isLetterOrNumber()) result.append(c);
        return result;
    }

    void ensureDesktopIndex() {
        if (m_desktopIndexReady) return;
        m_desktopIndexReady = true;
        for (const QString &directory : QStandardPaths::standardLocations(QStandardPaths::ApplicationsLocation)) {
            QDirIterator it(directory, {QStringLiteral("*.desktop")}, QDir::Files);
            while (it.hasNext()) {
                const QString path = it.next(); QSettings desktop(path, QSettings::IniFormat);
                desktop.beginGroup(QStringLiteral("Desktop Entry"));
                const QString icon = desktop.value(QStringLiteral("Icon")).toString().trimmed();
                const QString startup = desktop.value(QStringLiteral("StartupWMClass")).toString().trimmed();
                desktop.endGroup(); if (icon.isEmpty()) continue;
                const QString id = normalizeName(QFileInfo(path).completeBaseName());
                const QString startupId = normalizeName(startup);
                if (!id.isEmpty() && !m_desktopIcons.contains(id)) m_desktopIcons.insert(id, icon);
                if (!startupId.isEmpty() && !m_desktopIcons.contains(startupId)) m_desktopIcons.insert(startupId, icon);
            }
        }
    }

    QString findFallbackIcon(const QString &appId) {
        ensureDesktopIndex();
        // appId -> desktop icon name. Both hits and misses are cached: without
        // the negative entry every snapshot re-ran the O(N) substring scan for
        // appIds that match no desktop file.
        const QString appKey = normalizeName(appId);
        QString iconName;
        if (m_appIconName.contains(appKey)) {
            iconName = m_appIconName.value(appKey);
        } else {
            iconName = m_desktopIcons.value(appKey);
            if (iconName.isEmpty()) {
                for (auto it = m_desktopIcons.cbegin(); it != m_desktopIcons.cend(); ++it) {
                    if (it.key().contains(appKey) || appKey.contains(it.key())) { iconName = it.value(); break; }
                }
            }
            m_appIconName.insert(appKey, iconName);
        }
        const QString requestedIcon = iconName.isEmpty() ? appId : iconName;
        if (requestedIcon.startsWith(QLatin1Char('/')) && QFileInfo::exists(requestedIcon))
            return requestedIcon;

        const QString key = normalizeName(requestedIcon);
        if (key.isEmpty()) return {};
        // iconName -> resolved path. Inserted even when empty below, so misses
        // (including the directory scan coming back empty) are also cached.
        if (m_iconCache.contains(key)) return m_iconCache.value(key);

        // This is the same lookup used by KDE's kiconfinder6: KIconLoader is
        // aware of kdeglobals, the selected icon theme and its inheritance.
        // In particular, a desktop entry such as spotify-launcher resolves to
        // the themed Spotify artwork instead of its hicolor fallback.
        const QString themedIcon = KIconLoader::global()->iconPath(
            requestedIcon, KIconLoader::Desktop, true);
        if (!themedIcon.isEmpty()) {
            m_iconCache.insert(key, themedIcon);
            return themedIcon;
        }

        QString bestPath; int bestScore = -1;
        const QRegularExpression sizeExpression(QStringLiteral("/(\\d+)x\\d+/"));
        for (const QString &root : QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation)) {
            QDirIterator it(root + QStringLiteral("/icons"), {QStringLiteral("*.png"), QStringLiteral("*.svg"), QStringLiteral("*.xpm")}, QDir::Files, QDirIterator::Subdirectories);
            while (it.hasNext()) {
                const QString path = it.next(); const QString name = normalizeName(QFileInfo(path).baseName());
                if (name.isEmpty() || (name != key && !name.contains(key))) continue;
                int score = name == key ? 10000 : 5000 - (name.size() - key.size());
                if (path.contains(QStringLiteral("/apps/"))) score += 1000;
                if (path.contains(QStringLiteral("scalable"))) score += 500;
                const auto match = sizeExpression.match(path); if (match.hasMatch()) score += match.captured(1).toInt();
                if (score > bestScore) { bestScore = score; bestPath = path; }
            }
        }
        m_iconCache.insert(key, bestPath); return bestPath;
    }

    QQueue<QString> m_commands;
    QHash<QString, QString> m_desktopIcons;
    QHash<QString, QString> m_appIconName;
    QHash<QString, QString> m_iconCache;
    QSet<QString> m_lastWindowIds;
    QHash<QString, QString> m_thumbnailPaths;
    QSet<QString> m_thumbnailInFlight;
    QQueue<QString> m_thumbnailQueue;
    quint64 m_thumbnailSerial = 0;
    bool m_desktopIndexReady = false;
    std::atomic<quint64> m_iconTicket{0};
    // Serialises icon work onto one thread and lets stale snapshots early-out.
    // Declared last so it is destroyed first: ~QThreadPool waits for the
    // worker while the caches above are still alive.
    QThreadPool m_iconPool;
};

} // namespace

bool startKWinBridge(const KWinEventHandler &handler)
{
    g_eventHandler = handler;
    QDBusConnection bus = QDBusConnection::sessionBus();

    if (!bus.registerService(QStringLiteral("org.kos.Platform"))) {
        QTextStream(stderr) << "Could not register D-Bus service: "
                            << bus.lastError().message() << Qt::endl;
        return false;
    }

    g_bridge = new Bridge(qApp);
    if (!bus.registerObject(QStringLiteral("/Platform"), g_bridge,
                            QDBusConnection::ExportAllSlots)) {
        QTextStream(stderr) << "Could not register D-Bus object: "
                            << bus.lastError().message() << Qt::endl;
        delete g_bridge;
        g_bridge = nullptr;
        return false;
    }

    // Forward the private effect signal into the platform JSONL event stream.
    // The connection is harmless while the optional effect is not installed;
    // KWin simply has no signal source yet and the daemon remains available.
    if (!bus.connect(QStringLiteral("org.kde.KWin"),
                    QStringLiteral("/KOSDockWindowAnimation"),
                    QStringLiteral("org.kos.KWin.DockWindowAnimation"),
                    QStringLiteral("animationStarted"),
                    g_bridge,
                    SLOT(AnimationStarted(QString,QString,QString,int)))) {
        QTextStream(stderr) << "Could not subscribe to Dock animation signal: "
                            << bus.lastError().message() << Qt::endl;
    }

    // KWin's script is deliberately loaded by the same resident process. The
    // D-Bus bridge is usable even when KWin is unavailable; the call simply
    // fails and the rest of the platform adapters keep serving clients.
    QTimer::singleShot(0, [] {
        QDBusInterface scripting(QStringLiteral("org.kde.KWin"),
                                 QStringLiteral("/Scripting"),
                                 QStringLiteral("org.kde.kwin.Scripting"));
        if (!scripting.isValid())
            return;
        const QString script = qEnvironmentVariable("KOS_PLATFORM_KWIN_SCRIPT");
        if (script.isEmpty())
            return;
        scripting.call(QStringLiteral("unloadScript"),
                       QStringLiteral("kos-window-bridge"));
        const QDBusMessage loaded = scripting.call(QStringLiteral("loadScript"),
                                                    script,
                                                    QStringLiteral("kos-window-bridge"));
        if (loaded.type() == QDBusMessage::ErrorMessage)
            return;
        scripting.call(QStringLiteral("start"));
    });
    return true;
}

bool enqueueKWinCommand(const QJsonObject &command)
{
    if (!g_bridge)
        return false;
    g_bridge->Enqueue(QString::fromUtf8(
        QJsonDocument(command).toJson(QJsonDocument::Compact)));
    return true;
}

} // namespace KosPlatform

#include "KWinBridge.moc"
