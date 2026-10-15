#include "PlatformServer.h"
#include "PlatformDbus.h"

#include <QByteArray>
#include <QDBusConnection>
#include <QFile>
#include <QFutureWatcher>
#include <QMetaType>
#include <QSet>
#include <QStringList>
#include <QVariant>
#include <QtConcurrent>

namespace KosPlatform {
using namespace Detail;

namespace {

constexpr int kTrayIdentifyCacheTtlMs = 3000;

struct TrayIdentityResult {
    bool ok = false;
    QString code;
    QString message;
    QJsonObject names;
};

// Tokens that name a runtime, a bundle layout or a shell instead of the
// application. They are never used as a display name: "electron" says nothing
// about the app it hosts, and "app" is a directory inside a bundle.
bool trayIdentityGenericToken(const QString &tokenLower)
{
    static const QSet<QString> generic{
        QStringLiteral("app"), QStringLiteral("apprun"),
        QStringLiteral("resources"), QStringLiteral("electron"),
        QStringLiteral("node"), QStringLiteral("chrome"),
        QStringLiteral("chromium"), QStringLiteral("chromium-browser"),
        QStringLiteral("google-chrome"), QStringLiteral("python"),
        QStringLiteral("python2"), QStringLiteral("python3"),
        QStringLiteral("java"), QStringLiteral("wine"), QStringLiteral("wine64"),
        QStringLiteral("sh"), QStringLiteral("bash"), QStringLiteral("env"),
        QStringLiteral("flatpak"), QStringLiteral("snap"),
    };
    // Runtimes are installed under versioned directory names ("electron43",
    // "node20"), which name the runtime just as much as the bare name does.
    QString key = tokenLower;
    while (!key.isEmpty()
           && (key.back().isDigit() || key.back() == QLatin1Char('.')))
        key.chop(1);
    return generic.contains(key);
}

// "remmina" reads better as "Remmina", but a name the application spells with
// separators ("cc-switch") is its own styling and must survive untouched.
QString trayIdentityDisplayName(const QString &token)
{
    if (token.contains(QLatin1Char('-')) || token.contains(QLatin1Char('_')))
        return token;
    QString name = token;
    if (!name.isEmpty() && name.at(0).isLower())
        name[0] = name[0].toUpper();
    return name;
}

// Walks an application path to the component that actually names the app.
// Electron and AppImage wrappers hide it: "/opt/WorkBuddy/app.asar.unpacked"
// and "/opt/Foo/resources/app.asar" both have to step out of the bundle
// before the name is readable, while a path that bottoms out in a runtime
// ("/usr/lib/electron43/electron") names nothing at all.
QString trayIdentityPathName(const QString &path)
{
    static const QStringList bundleSuffixes{
        QStringLiteral(".asar.unpacked"), QStringLiteral(".asar"),
        QStringLiteral(".appimage"), QStringLiteral(".exe"),
    };
    // Bundle layout between the application directory and its binary.
    static const QSet<QString> bundleDirs{
        QStringLiteral("app"), QStringLiteral("apprun"),
        QStringLiteral("resources"),
    };
    // Filesystem layout: reaching one of these means the argument pointed at
    // a runtime or a mount, not at an application.
    static const QSet<QString> layoutDirs{
        QStringLiteral("bin"), QStringLiteral("lib"), QStringLiteral("lib64"),
        QStringLiteral("libexec"), QStringLiteral("sbin"), QStringLiteral("share"),
        QStringLiteral("usr"), QStringLiteral("opt"), QStringLiteral("tmp"),
        QStringLiteral("local"), QStringLiteral("var"), QStringLiteral("run"),
    };

    QStringList parts = path.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    while (!parts.isEmpty()) {
        QString token = parts.constLast();
        bool isBundleFile = false;
        for (const QString &suffix : bundleSuffixes) {
            if (token.endsWith(suffix, Qt::CaseInsensitive)) {
                isBundleFile = true;
                break;
            }
        }
        if (!isBundleFile && token.endsWith(QStringLiteral("-bin"), Qt::CaseInsensitive))
            token.chop(4);
        const QString key = token.toLower();
        if (token.isEmpty() || isBundleFile || bundleDirs.contains(key)
            || layoutDirs.contains(key)) {
            parts.removeLast();
            continue;
        }
        // A generic runtime binary is never the application's name, and its
        // own directory ("electron43") is not one either.
        if (trayIdentityGenericToken(key))
            return {};
        return token;
    }
    return {};
}

// First absolute path on the command line that is not the runtime itself.
QString trayIdentityCmdlineName(const QString &cmd)
{
    const QStringList parts = cmd.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        if (!part.startsWith(QLatin1Char('/')))
            continue;
        const QString name = trayIdentityPathName(part);
        if (!name.isEmpty())
            return name;
    }
    return {};
}

QString trayIdentityAlias(const QString &commLower)
{
    static const QHash<QString, QString> aliases{
        {QStringLiteral("qq"), QStringLiteral("QQ")},
        {QStringLiteral("linuxqq"), QStringLiteral("QQ")},
        {QStringLiteral("antigravity"), QStringLiteral("Antigravity")},
        {QStringLiteral("rustdesk"), QStringLiteral("RustDesk")},
        {QStringLiteral("karing"), QStringLiteral("Karing")},
        {QStringLiteral("sunshine"), QStringLiteral("Sunshine")},
        {QStringLiteral("wechat"), QStringLiteral("微信")},
        {QStringLiteral("fcitx"), QStringLiteral("输入法")},
        {QStringLiteral("fcitx5"), QStringLiteral("输入法")},
        {QStringLiteral("google-chrome"), QStringLiteral("Google Chrome")},
        {QStringLiteral("chrome"), QStringLiteral("Google Chrome")},
        {QStringLiteral("chromium"), QStringLiteral("Chromium")},
        {QStringLiteral("code"), QStringLiteral("VS Code")},
    };
    return aliases.value(commLower);
}

TrayIdentityResult trayIdentifyWorker()
{
    const ScopedBusConnection guard(workerBusName(QStringLiteral("tray")));
    const QDBusConnection bus = QDBusConnection::connectToBus(
        QDBusConnection::SessionBus, guard.name);

    TrayIdentityResult out;
    const QVariant itemsVariant = dbusGetProperty(bus,
        QStringLiteral("org.kde.StatusNotifierWatcher"),
        QStringLiteral("/StatusNotifierWatcher"),
        QStringLiteral("org.kde.StatusNotifierWatcher"),
        QStringLiteral("RegisteredStatusNotifierItems"));
    if (itemsVariant.metaType() != QMetaType::fromType<QStringList>()) {
        out.code = QStringLiteral("tray-unavailable");
        out.message = QStringLiteral("托盘状态不可用");
        return out;
    }

    const QStringList items = itemsVariant.toStringList();
    for (const QString &item : items) {
        const qsizetype slash = item.indexOf(QLatin1Char('/'));
        if (slash <= 0)
            continue;
        const QString service = item.left(slash);
        const QString path = QStringLiteral("/") + item.mid(slash + 1);
        const QString id = dbusGetProperty(bus, service, path,
            QStringLiteral("org.kde.StatusNotifierItem"),
            QStringLiteral("Id")).toString();
        if (id.isEmpty())
            continue;
        const QString title = dbusGetProperty(bus, service, path,
            QStringLiteral("org.kde.StatusNotifierItem"),
            QStringLiteral("Title")).toString();
        const uint pid = dbusUnixProcessId(bus, service);

        // /proc reads are local files; a process that exits between the bus
        // lookup and the read just yields no name.
        QString comm;
        QString cmd;
        if (pid > 0) {
            QFile commFile(QStringLiteral("/proc/%1/comm").arg(pid));
            if (commFile.open(QIODevice::ReadOnly))
                comm = QString::fromUtf8(commFile.readAll()).trimmed().toLower();
            QFile cmdFile(QStringLiteral("/proc/%1/cmdline").arg(pid));
            if (cmdFile.open(QIODevice::ReadOnly)) {
                QByteArray raw = cmdFile.readAll();
                raw.replace('\0', " ");
                // Kept in its original case: the application path carries the
                // app's own spelling ("WorkBuddy"), so lowercasing it here
                // would force an ugly re-capitalisation later.
                cmd = QString::fromUtf8(raw).trimmed();
            }
        }

        // Name in order of how much the source actually knows about the app:
        // a process named after the app itself, then the application path on
        // a command line owned by a generic runtime, then a title the item
        // set itself. An item whose id is a generated token never reaches
        // here with a usable title, so the path is the only remaining signal.
        QString name;
        // A dot in comm means the kernel truncated the name at 15 characters
        // ("com.alibabainc.dingtalk" arrives as "com.alibabainc."), so it is a
        // cut-off identifier rather than a name.
        if (!comm.isEmpty() && !comm.contains(QLatin1Char('.'))
            && !trayIdentityGenericToken(comm)) {
            const QString alias = trayIdentityAlias(comm);
            name = alias.isEmpty() ? trayIdentityDisplayName(comm) : alias;
        }
        if (name.isEmpty()) {
            const QString fromCmd = trayIdentityCmdlineName(cmd);
            if (!fromCmd.isEmpty()) {
                const QString alias = trayIdentityAlias(fromCmd.toLower());
                name = alias.isEmpty() ? trayIdentityDisplayName(fromCmd) : alias;
            }
        }
        if (name.isEmpty())
            name = title.trimmed().section(QLatin1Char('\n'), 0, 0).trimmed();
        if (!name.isEmpty())
            out.names.insert(id, name);
    }
    out.ok = true;
    return out;
}

} // namespace

void PlatformServer::runTrayIdentify(QLocalSocket *socket, const QJsonObject &request)
{
    const QString key = QStringLiteral("tray.identify");
    if (serveCachedReply(socket, request, key)
        || queueIfInFlight(key, socket, request))
        return;

    // The walk is a bounded D-Bus sweep (one Get per item plus a PID lookup)
    // on m_dbusPool, so a slow or wedged watcher cannot stall the socket loop.
    auto *watcher = new QFutureWatcher<TrayIdentityResult>(this);
    connect(watcher, &QFutureWatcher<TrayIdentityResult>::finished, this,
            [this, watcher, key]() {
        watcher->deleteLater();
        const TrayIdentityResult out = watcher->result();
        completeInFlight(key, out.ok,
                         out.ok ? QJsonObject{{QStringLiteral("names"), out.names}}
                                : QJsonObject{},
                         out.code, out.message, true, kTrayIdentifyCacheTtlMs);
    });
    watcher->setFuture(QtConcurrent::run(&m_dbusPool, trayIdentifyWorker));
}

bool PlatformServer::handleTrayOperation(QLocalSocket *socket, const QJsonObject &request)
{
    const QString op = operation(request);
    if (op == QStringLiteral("tray.identify")) {
        runTrayIdentify(socket, request);
        return true;
    }
    return false;
}

} // namespace KosPlatform
