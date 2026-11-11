#include "KimpanelBridge.h"
#include "PlatformDbus.h"

#include <QDBusArgument>
#include <QDBusMetaType>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QRegularExpression>
#include <QProcess>
#include <QStandardPaths>
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QSaveFile>
#include <QJsonDocument>
#include <QDebug>
#include <KConfigGroup>
#include <KSharedConfig>
#include <QDBusServiceWatcher>
#include <QEventLoop>
#include <QTimer>

namespace KosPlatform {

struct FcitxAddonState {
    QString name;
    bool enabled = false;
};

struct FcitxAddonInfo {
    QString name;
    QString label;
    QString comment;
    int category = 0;
    bool enabled = false;
    bool canToggle = false;
};

} // namespace KosPlatform

Q_DECLARE_METATYPE(KosPlatform::FcitxAddonState)
Q_DECLARE_METATYPE(KosPlatform::FcitxAddonInfo)

inline QDBusArgument &operator<<(QDBusArgument &arg, const KosPlatform::FcitxAddonState &s) {
    arg.beginStructure();
    arg << s.name << s.enabled;
    arg.endStructure();
    return arg;
}

inline const QDBusArgument &operator>>(const QDBusArgument &arg, KosPlatform::FcitxAddonState &s) {
    arg.beginStructure();
    arg >> s.name >> s.enabled;
    arg.endStructure();
    return arg;
}

inline QDBusArgument &operator<<(QDBusArgument &arg, const KosPlatform::FcitxAddonInfo &info) {
    arg.beginStructure();
    arg << info.name << info.label << info.comment << info.category << info.canToggle << info.enabled;
    arg.endStructure();
    return arg;
}

inline const QDBusArgument &operator>>(const QDBusArgument &arg, KosPlatform::FcitxAddonInfo &info) {
    arg.beginStructure();
    arg >> info.name >> info.label >> info.comment >> info.category >> info.canToggle >> info.enabled;
    arg.endStructure();
    return arg;
}

namespace KosPlatform {

namespace {

static bool s_metaTypesRegistered = false;
void registerFcitxMetaTypes() {
    if (s_metaTypesRegistered) return;
    qDBusRegisterMetaType<FcitxAddonState>();
    qDBusRegisterMetaType<QList<FcitxAddonState>>();
    qDBusRegisterMetaType<FcitxAddonInfo>();
    qDBusRegisterMetaType<QList<FcitxAddonInfo>>();
    s_metaTypesRegistered = true;
}

} // namespace

ImpanelAdaptor::ImpanelAdaptor(KimpanelBridge *parent)
    : QDBusAbstractAdaptor(parent)
{
    setAutoRelaySignals(true);
}

Impanel2Adaptor::Impanel2Adaptor(KimpanelBridge *parent)
    : QDBusAbstractAdaptor(parent)
{
    setAutoRelaySignals(true);
}

void Impanel2Adaptor::SetSpotRect(int x, int y, int w, int h)
{
    static_cast<KimpanelBridge *>(parent())->handleSetSpotRect(x, y, w, h);
}

void Impanel2Adaptor::SetRelativeSpotRect(int x, int y, int w, int h)
{
    static_cast<KimpanelBridge *>(parent())->handleSetRelativeSpotRect(x, y, w, h);
}

void Impanel2Adaptor::SetRelativeSpotRectV2(int x, int y, int w, int h, double scale)
{
    static_cast<KimpanelBridge *>(parent())->handleSetRelativeSpotRectV2(x, y, w, h, scale);
}

void Impanel2Adaptor::SetLookupTable(const QStringList &labels, const QStringList &texts,
                                     const QStringList &attrs, bool hasPrev, bool hasNext,
                                     int cursor, int layout)
{
    static_cast<KimpanelBridge *>(parent())->handleSetLookupTable(
        labels, texts, attrs, hasPrev, hasNext, cursor, layout);
}

QString KimpanelBridge::configPath()
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
        + QStringLiteral("/kos");
    return dir + QStringLiteral("/inputmethod.json");
}

bool KimpanelBridge::loadPersistedEnabled()
{
    QFile file(configPath());
    if (!file.open(QIODevice::ReadOnly)) {
        return false; // Default OFF for safety
    }
    const auto doc = QJsonDocument::fromJson(file.readAll());
    return doc.object().value(QStringLiteral("enabled")).toBool(false);
}

bool KimpanelBridge::savePersistedEnabled(bool enabled)
{
    const QString path = configPath();
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "[KimpanelBridge] Failed to open config for writing:" << path;
        return false;
    }
    QJsonObject obj{{QStringLiteral("enabled"), enabled}};
    file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    return file.commit();
}

KimpanelBridge::KimpanelBridge(QObject *parent)
    : QObject(parent)
{
    registerFcitxMetaTypes();
    m_adaptor = new ImpanelAdaptor(this);
    m_adaptor2 = new Impanel2Adaptor(this);
    m_userEnabled = loadPersistedEnabled();
    recoverOriginalFcitxAddons();
}

KimpanelBridge::~KimpanelBridge()
{
    m_destroying = true;
    disconnect(this, &KimpanelBridge::stateChanged, nullptr, nullptr);
    disconnect(this, &KimpanelBridge::menuRequested, nullptr, nullptr);
    releaseTakeover();
}

bool KimpanelBridge::setUserEnabled(bool enabled)
{
    if (m_transitioning)
        return false;
    const bool previous = m_userEnabled;
    if (savePersistedEnabled(enabled)) {
        m_userEnabled = enabled;
        m_error.clear();
        syncTakeoverState();
        if ((!enabled && m_addonsChanged)
            || (enabled && m_shellConnected && !m_takeoverActive)) {
            m_userEnabled = previous;
            savePersistedEnabled(previous);
            notifyState();
            return false;
        }
        return m_error.isEmpty();
    }
    return false;
}

void KimpanelBridge::setShellConnected(bool connected)
{
    if (m_shellConnected == connected)
        return;
    m_shellConnected = connected;
    syncTakeoverState();
}

void KimpanelBridge::syncTakeoverState()
{
    if (m_transitioning)
        return;
    const bool shouldBeActive = m_userEnabled && m_shellConnected;
    if (shouldBeActive && !m_takeoverActive) {
        acquireTakeover();
    } else if (!shouldBeActive && m_takeoverActive) {
        releaseTakeover();
    }
    notifyState();
}

bool KimpanelBridge::backupOriginalFcitxAddons()
{
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return false;

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.fcitx.Fcitx5"), QStringLiteral("/controller"),
        QStringLiteral("org.fcitx.Fcitx.Controller1"), QStringLiteral("GetAddons"));

    QDBusMessage reply = bus.call(msg, QDBus::Block, 500);
    if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()) {
        const QDBusArgument arg = reply.arguments().first().value<QDBusArgument>();
        QList<FcitxAddonInfo> addons;
        arg >> addons;
        bool foundClassic = false, foundKimpanel = false;
        for (const auto &addon : addons) {
            if (addon.name == QStringLiteral("classicui")) {
                m_origClassicUiEnabled = addon.enabled;
                foundClassic = true;
            } else if (addon.name == QStringLiteral("kimpanel")) {
                m_origKimpanelEnabled = addon.enabled;
                foundKimpanel = true;
            }
        }
        m_hasOriginalAddonState = foundClassic && foundKimpanel;
        return m_hasOriginalAddonState;
    }
    return false;
}

QString KimpanelBridge::recoveryPath() const
{
    return QFileInfo(configPath()).dir().filePath(QStringLiteral("inputmethod-recovery.json"));
}

bool KimpanelBridge::saveRecoveryState()
{
    QDir().mkpath(QFileInfo(recoveryPath()).absolutePath());
    QSaveFile file(recoveryPath());
    if (!file.open(QIODevice::WriteOnly))
        return false;
    const KConfigGroup wayland(KSharedConfig::openConfig(QStringLiteral("kwinrc")), QStringLiteral("Wayland"));
    file.write(QJsonDocument(QJsonObject{
        {QStringLiteral("classicui"), m_origClassicUiEnabled},
        {QStringLiteral("kimpanel"), m_origKimpanelEnabled},
        {QStringLiteral("kwinInputMethod"), wayland.readEntry("InputMethod", QString())}
    }).toJson());
    return file.commit();
}

void KimpanelBridge::recoverOriginalFcitxAddons()
{
    QFile file(recoveryPath());
    if (!file.open(QIODevice::ReadOnly))
        return;
    const auto state = QJsonDocument::fromJson(file.readAll()).object();
    if (!state.value(QStringLiteral("classicui")).isBool()
        || !state.value(QStringLiteral("kimpanel")).isBool()) {
        m_error = QStringLiteral("Invalid input method recovery state");
        return;
    }
    m_origClassicUiEnabled = state.value(QStringLiteral("classicui")).toBool();
    m_origKimpanelEnabled = state.value(QStringLiteral("kimpanel")).toBool();
    m_hasOriginalAddonState = m_addonsChanged = true;
    // A process interrupted between the two KWin notifications must not leave
    // the compositor's input-method command empty after its next startup.
    auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    KConfigGroup wayland(config, QStringLiteral("Wayland"));
    const QString previous = state.value(QStringLiteral("kwinInputMethod")).toString();
    if (wayland.readEntry("InputMethod", QString()).isEmpty() && !previous.isEmpty()) {
        wayland.writeEntry("InputMethod", previous, KConfigBase::Notify);
        config->sync();
    }
    releaseTakeover();
}

bool KimpanelBridge::restartFcitx()
{
    // ReloadConfig reloads settings, but cannot unload the already loaded
    // Classic UI. KWin must recreate its own child and its private IM socket;
    // fcitx5 -r / Restart would lose that socket in a compositor-owned session.
    auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    config->reparseConfiguration();
    KConfigGroup wayland(config, QStringLiteral("Wayland"));
    const QString command = wayland.readEntry("InputMethod", QString());
    const KConfig desktop(command, KConfig::SimpleConfig);
    const QString exec = KConfigGroup(&desktop, QStringLiteral("Desktop Entry")).readEntry("Exec", QString());
    if (command.isEmpty() || !exec.contains(QStringLiteral("fcitx5"))) {
        m_error = QStringLiteral("Fcitx5 must be managed by KWin to switch candidate windows");
        return false;
    }
    const auto bus = QDBusConnection::sessionBus();
    const QString service = QStringLiteral("org.fcitx.Fcitx5");
    const QString oldOwner = bus.interface()->serviceOwner(service).value();
    QEventLoop loop;
    QTimer timeout;
    timeout.setSingleShot(true);
    QDBusServiceWatcher watcher(service, bus, QDBusServiceWatcher::WatchForOwnerChange);
    bool restored = false, restarted = false;
    auto restoreCommand = [&] {
        if (restored) return;
        restored = true;
        wayland.writeEntry("InputMethod", command, KConfigBase::Notify);
        config->sync();
    };
    connect(&watcher, &QDBusServiceWatcher::serviceOwnerChanged, &loop,
            [&](const QString &, const QString &, const QString &owner) {
        if (owner.isEmpty()) restoreCommand();
        else if (restored && owner != oldOwner) {
            restarted = true;
            loop.quit();
        }
    });
    connect(&timeout, &QTimer::timeout, &loop, &QEventLoop::quit);
    const bool requestedTakeover = m_userEnabled && m_shellConnected;
    m_transitioning = true;
    notifyState();
    wayland.writeEntry("InputMethod", QString(), KConfigBase::Notify);
    config->sync();
    timeout.start(5000);
    loop.exec();
    restoreCommand();
    m_transitioning = false;
    if (!restarted)
        m_error = QStringLiteral("KWin could not reload the input method; native UI recovery is pending");
    if (!m_destroying && requestedTakeover != (m_userEnabled && m_shellConnected))
        QTimer::singleShot(0, this, [this] { syncTakeoverState(); });
    return restarted;
}

bool KimpanelBridge::setFcitxAddons(bool classicUi, bool kimpanel)
{
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return false;

    QList<FcitxAddonState> states;
    states.append({QStringLiteral("classicui"), classicUi});
    states.append({QStringLiteral("kimpanel"), kimpanel});

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.fcitx.Fcitx5"), QStringLiteral("/controller"),
        QStringLiteral("org.fcitx.Fcitx.Controller1"), QStringLiteral("SetAddonsState"));
    msg.setArguments({QVariant::fromValue(states)});
    QDBusMessage reply = bus.call(msg, QDBus::Block, 500);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning() << "[KimpanelBridge] SetAddonsState failed:" << reply.errorMessage();
        m_error = reply.errorMessage();
        return false;
    }

    QDBusMessage reloadMsg = QDBusMessage::createMethodCall(
        QStringLiteral("org.fcitx.Fcitx5"), QStringLiteral("/controller"),
        QStringLiteral("org.fcitx.Fcitx.Controller1"), QStringLiteral("ReloadConfig"));
    const auto reloadReply = bus.call(reloadMsg, QDBus::Block, 500);
    if (reloadReply.type() == QDBusMessage::ErrorMessage) {
        m_error = reloadReply.errorMessage();
        return false;
    }
    return true;
}

bool KimpanelBridge::acquireTakeover()
{
    if (m_takeoverActive)
        return true;

    const KConfigGroup wayland(KSharedConfig::openConfig(QStringLiteral("kwinrc")), QStringLiteral("Wayland"));
    const KConfig desktop(wayland.readEntry("InputMethod", QString()), KConfig::SimpleConfig);
    if (!KConfigGroup(&desktop, QStringLiteral("Desktop Entry")).readEntry("Exec", QString()).contains(QStringLiteral("fcitx5"))) {
        m_error = QStringLiteral("Fcitx5 must be managed by KWin to switch candidate windows");
        return false;
    }

    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qWarning() << "[KimpanelBridge] Session bus not connected";
        return false;
    }

    if (m_addonsChanged || !backupOriginalFcitxAddons()) {
        m_error = QStringLiteral("Could not back up the original Fcitx5 configuration");
        return false;
    }

    if (!m_registeredBus) {
        if (!bus.registerObject(QStringLiteral("/org/kde/impanel"), this,
                                QDBusConnection::ExportAdaptors)) {
            qWarning() << "[KimpanelBridge] Failed to register object /org/kde/impanel:"
                       << bus.lastError().message();
            return false;
        }

        if (!bus.registerService(QStringLiteral("org.kde.impanel"))) {
            qWarning() << "[KimpanelBridge] Failed to register service org.kde.impanel:"
                       << bus.lastError().message();
            m_error = bus.lastError().message();
            bus.unregisterObject(QStringLiteral("/org/kde/impanel"));
            return false;
        }
        m_registeredBus = true;
    }

    setupDbusListeners();

    if (!saveRecoveryState()) {
        m_error = QStringLiteral("Could not save input method recovery state");
        releaseTakeover();
        return false;
    }
    m_addonsChanged = true;
    if (!setFcitxAddons(false /* classicui */, true /* kimpanel */) || !restartFcitx()) {
        qWarning() << "[KimpanelBridge] Failed to configure Fcitx5 addons for takeover";
        releaseTakeover();
        return false;
    }

    emit m_adaptor->PanelCreated();
    emit m_adaptor->PanelCreated2();
    emit m_adaptor2->PanelCreated2();

    m_takeoverActive = true;
    if (!m_userEnabled || !m_shellConnected) {
        releaseTakeover();
        return false;
    }
    return true;
}

void KimpanelBridge::releaseTakeover()
{
    teardownDbusListeners();

    auto bus = QDBusConnection::sessionBus();
    if (m_registeredBus) {
        bus.unregisterService(QStringLiteral("org.kde.impanel"));
        bus.unregisterObject(QStringLiteral("/org/kde/impanel"));
        m_registeredBus = false;
    }

    m_takeoverActive = false;
    if (m_addonsChanged && m_hasOriginalAddonState) {
        if (setFcitxAddons(m_origClassicUiEnabled, m_origKimpanelEnabled) && restartFcitx()) {
            m_addonsChanged = m_hasOriginalAddonState = false;
            QFile::remove(recoveryPath());
        } else {
            m_error = QStringLiteral("Could not restore native input method UI; recovery state was retained");
        }
    }
}

void KimpanelBridge::reassertTakeover()
{
    if (!m_takeoverActive)
        return;
    setFcitxAddons(false /* classicui */, true /* kimpanel */);
}

void KimpanelBridge::setupDbusListeners()
{
    auto bus = QDBusConnection::sessionBus();
    const QString service = QString(); // Listen to any sender for /kimpanel
    const QString path = QStringLiteral("/kimpanel");
    const QString iface = QStringLiteral("org.kde.kimpanel.inputmethod");

    bus.connect(service, path, iface, QStringLiteral("ShowAux"), this, SLOT(onShowAux(bool)));
    bus.connect(service, path, iface, QStringLiteral("ShowPreedit"), this, SLOT(onShowPreedit(bool)));
    bus.connect(service, path, iface, QStringLiteral("ShowLookupTable"), this, SLOT(onShowLookupTable(bool)));
    bus.connect(service, path, iface, QStringLiteral("UpdateLookupTableCursor"), this, SLOT(onUpdateLookupTableCursor(int)));
    bus.connect(service, path, iface, QStringLiteral("UpdatePreeditCaret"), this, SLOT(onUpdatePreeditCaret(int)));
    bus.connect(service, path, iface, QStringLiteral("UpdatePreeditText"), this, SLOT(onUpdatePreeditText(QString,QString)));
    bus.connect(service, path, iface, QStringLiteral("UpdateAux"), this, SLOT(onUpdateAux(QString,QString)));
    bus.connect(service, path, iface, QStringLiteral("UpdateSpotLocation"), this, SLOT(onUpdateSpotLocation(int,int)));
    bus.connect(service, path, iface, QStringLiteral("UpdateScreen"), this, SLOT(onUpdateScreen(int)));
    bus.connect(service, path, iface, QStringLiteral("Enable"), this, SLOT(onEnable(bool)));
    bus.connect(service, path, iface, QStringLiteral("RegisterProperties"), this, SLOT(onRegisterProperties(QStringList)));
    bus.connect(service, path, iface, QStringLiteral("UpdateProperty"), this, SLOT(onUpdateProperty(QString)));
    bus.connect(service, path, iface, QStringLiteral("RemoveProperty"), this, SLOT(onRemoveProperty(QString)));
    bus.connect(service, path, iface, QStringLiteral("ExecMenu"), this, SLOT(onExecMenu(QStringList)));
    bus.connect(service, path, iface, QStringLiteral("ExecDialog"), this, SLOT(onExecDialog(QString)));
}

void KimpanelBridge::teardownDbusListeners()
{
    auto bus = QDBusConnection::sessionBus();
    const QString service = QString();
    const QString path = QStringLiteral("/kimpanel");
    const QString iface = QStringLiteral("org.kde.kimpanel.inputmethod");

    bus.disconnect(service, path, iface, QStringLiteral("ShowAux"), this, SLOT(onShowAux(bool)));
    bus.disconnect(service, path, iface, QStringLiteral("ShowPreedit"), this, SLOT(onShowPreedit(bool)));
    bus.disconnect(service, path, iface, QStringLiteral("ShowLookupTable"), this, SLOT(onShowLookupTable(bool)));
    bus.disconnect(service, path, iface, QStringLiteral("UpdateLookupTableCursor"), this, SLOT(onUpdateLookupTableCursor(int)));
    bus.disconnect(service, path, iface, QStringLiteral("UpdatePreeditCaret"), this, SLOT(onUpdatePreeditCaret(int)));
    bus.disconnect(service, path, iface, QStringLiteral("UpdatePreeditText"), this, SLOT(onUpdatePreeditText(QString,QString)));
    bus.disconnect(service, path, iface, QStringLiteral("UpdateAux"), this, SLOT(onUpdateAux(QString,QString)));
    bus.disconnect(service, path, iface, QStringLiteral("UpdateSpotLocation"), this, SLOT(onUpdateSpotLocation(int,int)));
    bus.disconnect(service, path, iface, QStringLiteral("UpdateScreen"), this, SLOT(onUpdateScreen(int)));
    bus.disconnect(service, path, iface, QStringLiteral("Enable"), this, SLOT(onEnable(bool)));
    bus.disconnect(service, path, iface, QStringLiteral("RegisterProperties"), this, SLOT(onRegisterProperties(QStringList)));
    bus.disconnect(service, path, iface, QStringLiteral("UpdateProperty"), this, SLOT(onUpdateProperty(QString)));
    bus.disconnect(service, path, iface, QStringLiteral("RemoveProperty"), this, SLOT(onRemoveProperty(QString)));
    bus.disconnect(service, path, iface, QStringLiteral("ExecMenu"), this, SLOT(onExecMenu(QStringList)));
    bus.disconnect(service, path, iface, QStringLiteral("ExecDialog"), this, SLOT(onExecDialog(QString)));
}

void KimpanelBridge::handleSetSpotRect(int x, int y, int w, int h)
{
    m_spotX = x;
    m_spotY = y;
    m_spotWidth = w;
    m_spotHeight = h;
    const KConfigGroup xwayland(KSharedConfig::openConfig(QStringLiteral("kwinrc")), QStringLiteral("Xwayland"));
    m_spotScale = qMax(1.0, xwayland.readEntry("Scale", 1.0));
    m_spotMode = QStringLiteral("absolute");

    notifyState();
    if (x == 0 && y == 0 && w == 0 && h == 0) {
        queryKWinCaret();
    }
}

void KimpanelBridge::handleSetRelativeSpotRect(int x, int y, int w, int h)
{
    handleSetRelativeSpotRectV2(x, y, w, h, 1.0);
}

void KimpanelBridge::handleSetRelativeSpotRectV2(int x, int y, int w, int h, double scale)
{
    m_spotX = x;
    m_spotY = y;
    m_spotWidth = w;
    m_spotHeight = h;
    m_spotScale = scale > 0.0 ? scale : 1.0;
    m_spotMode = QStringLiteral("relative");
    notifyState();
}

void KimpanelBridge::handleSetLookupTable(const QStringList &labels, const QStringList &texts,
                                          const QStringList &attrs, bool hasPrev, bool hasNext,
                                          int cursor, int layout)
{
    Q_UNUSED(attrs);
    m_hasPrev = hasPrev;
    m_hasNext = hasNext;
    m_cursorIndex = cursor;
    m_layout = layout;

    QJsonArray candidates;
    const int count = qMin(labels.size(), texts.size());
    static const QRegularExpression commentRegex(QStringLiteral(R"(^([^\s]+)\s+(.+)$)"));

    for (int i = 0; i < count; ++i) {
        const QString rawLabel = labels.at(i);
        const QString rawText = texts.at(i);

        QString candidateText = rawText;
        QString comment;

        const auto match = commentRegex.match(rawText);
        if (match.hasMatch()) {
            candidateText = match.captured(1);
            comment = match.captured(2).trimmed();
        }

        candidates.append(QJsonObject{
            {QStringLiteral("label"), rawLabel},
            {QStringLiteral("text"), candidateText},
            {QStringLiteral("comment"), comment}
        });
    }

    m_candidates = candidates;
    m_lookupVisible = !m_candidates.isEmpty();

    // Always push candidate updates immediately so the shell never starves,
    // while querying a fresh KWin caret in parallel if needed.
    notifyState();

    if (m_spotX == 0 && m_spotY == 0 && m_spotWidth == 0 && m_spotHeight == 0) {
        queryKWinCaret();
    }
}

void KimpanelBridge::setActiveWindowId(const QString &windowId)
{
    if (m_activeWindowId == windowId)
        return;
    m_activeWindowId = windowId;
    m_spotX = m_spotY = m_spotWidth = m_spotHeight = 0;
    ++m_kwinCaretSerial;
    m_kwinCaret = QJsonObject{
        {QStringLiteral("available"), false},
        {QStringLiteral("windowId"), windowId},
        {QStringLiteral("serial"), static_cast<double>(m_kwinCaretSerial)}
    };
}

void KimpanelBridge::queryKWinCaret()
{
    if (m_activeWindowId.isEmpty()) {
        return;
    }

    const quint64 requestId = ++m_kwinCaretSerial;
    const QString targetWindowId = m_activeWindowId;

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.KWin"), QStringLiteral("/KOSContextMenuInput"),
        QStringLiteral("org.kos.KWin.ContextMenuInput"), QStringLiteral("clipboardAnchor"));
    msg.setArguments({targetWindowId});

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg, 150), this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, watcher, requestId, targetWindowId] {
        const QDBusMessage reply = watcher->reply();
        watcher->deleteLater();
        if (m_activeWindowId != targetWindowId) {
            return;
        }
        if (requestId == m_kwinCaretSerial) {
            if (reply.type() != QDBusMessage::ErrorMessage && !reply.arguments().isEmpty()) {
                QJsonObject caret = QJsonObject::fromVariantMap(
                    Detail::variantMapFromDbusValue(reply.arguments().first()));
                caret.insert(QStringLiteral("windowId"), targetWindowId);
                caret.insert(QStringLiteral("serial"), static_cast<double>(requestId));
                m_kwinCaret = caret;
            } else {
                m_kwinCaret = QJsonObject{
                    {QStringLiteral("available"), false},
                    {QStringLiteral("windowId"), targetWindowId},
                    {QStringLiteral("serial"), static_cast<double>(requestId)}
                };
            }
            notifyState();
        }
    });
}

void KimpanelBridge::onShowAux(bool visible)
{
    m_auxVisible = visible;
    notifyState();
}

void KimpanelBridge::onShowPreedit(bool visible)
{
    m_preeditVisible = visible;
    notifyState();
    if (visible && m_spotX == 0 && m_spotY == 0) {
        queryKWinCaret();
    }
}

void KimpanelBridge::onShowLookupTable(bool visible)
{
    m_lookupVisible = visible;
    notifyState();
    if (visible && m_spotX == 0 && m_spotY == 0) {
        queryKWinCaret();
    }
}

void KimpanelBridge::onUpdateLookupTableCursor(int cursor)
{
    m_cursorIndex = cursor;
    notifyState();
}

void KimpanelBridge::onUpdatePreeditCaret(int caret)
{
    m_preeditCaret = caret;
    notifyState();
}

void KimpanelBridge::onUpdatePreeditText(const QString &text, const QString &attr)
{
    Q_UNUSED(attr);
    m_preeditText = text;
    if (!text.isEmpty()) {
        m_preeditVisible = true;
    } else if (m_candidates.isEmpty()) {
        m_preeditVisible = false;
    }
    notifyState();
}

void KimpanelBridge::onUpdateAux(const QString &text, const QString &attr)
{
    Q_UNUSED(attr);
    m_auxText = text;
    if (!text.isEmpty()) {
        m_auxVisible = true;
    } else if (m_candidates.isEmpty() && m_preeditText.isEmpty()) {
        m_auxVisible = false;
    }
    notifyState();
}

void KimpanelBridge::onUpdateSpotLocation(int x, int y)
{
    m_spotX = x;
    m_spotY = y;
    notifyState();
}

void KimpanelBridge::onUpdateScreen(int screen)
{
    Q_UNUSED(screen);
}

void KimpanelBridge::onEnable(bool enabled)
{
    m_imEnabled = enabled;
    notifyState();
}

void KimpanelBridge::onRegisterProperties(const QStringList &props)
{
    m_properties = QJsonArray();
    for (const auto &p : props) {
        parseAndStoreProperty(p);
    }
    notifyState();
}

void KimpanelBridge::onUpdateProperty(const QString &prop)
{
    parseAndStoreProperty(prop);
    notifyState();
}

void KimpanelBridge::onRemoveProperty(const QString &prop)
{
    QJsonArray updated;
    const QString idPrefix = prop.section(QLatin1Char(':'), 0, 0);
    for (const auto &val : m_properties) {
        const QJsonObject obj = val.toObject();
        if (obj.value(QStringLiteral("id")).toString() != idPrefix) {
            updated.append(obj);
        }
    }
    m_properties = updated;
    notifyState();
}

void KimpanelBridge::parseAndStoreProperty(const QString &prop)
{
    const QStringList parts = prop.split(QLatin1Char(':'));
    if (parts.isEmpty())
        return;

    const QString id = parts.value(0);
    const QString shortText = parts.value(1);
    const QString icon = parts.value(2);
    const QString label = parts.value(3);
    const QString type = parts.value(4);
    const QString key = id.startsWith(QStringLiteral("/Fcitx/")) ? id.mid(7) : id;

    if (key == QStringLiteral("im")) {
        if (!shortText.isEmpty() && shortText != QStringLiteral("不可用"))
            m_imLabel = shortText;
        if (!icon.isEmpty())
            m_imIcon = icon;
        if (!label.isEmpty())
            m_imName = label;
    }

    QJsonObject propObj{
        {QStringLiteral("id"), id},
        {QStringLiteral("key"), key},
        {QStringLiteral("shortText"), shortText},
        {QStringLiteral("icon"), icon},
        {QStringLiteral("label"), label},
        {QStringLiteral("isMenu"), type == QStringLiteral("menu")}
    };

    bool replaced = false;
    for (int i = 0; i < m_properties.size(); ++i) {
        if (m_properties[i].toObject().value(QStringLiteral("id")).toString() == id) {
            m_properties[i] = propObj;
            replaced = true;
            break;
        }
    }
    if (!replaced) {
        m_properties.append(propObj);
    }
}

void KimpanelBridge::onExecMenu(const QStringList &items)
{
    QJsonArray menuItems;
    for (const auto &item : items) {
        const QStringList parts = item.split(QLatin1Char(':'));
        const QString id = parts.value(0);
        const QString text = parts.value(1);
        const QString icon = parts.value(2);
        menuItems.append(QJsonObject{
            {QStringLiteral("id"), id},
            {QStringLiteral("text"), text},
            {QStringLiteral("icon"), icon}
        });
    }
    emit menuRequested(QJsonObject{{QStringLiteral("items"), menuItems}});
}

void KimpanelBridge::onExecDialog(const QString &dialog)
{
    Q_UNUSED(dialog);
}

void KimpanelBridge::selectCandidate(int index)
{
    emit m_adaptor->SelectCandidate(index);
}

void KimpanelBridge::pageUp()
{
    emit m_adaptor->LookupTablePageUp();
}

void KimpanelBridge::pageDown()
{
    emit m_adaptor->LookupTablePageDown();
}

void KimpanelBridge::triggerProperty(const QString &property)
{
    emit m_adaptor->TriggerProperty(property);
}

void KimpanelBridge::configure()
{
    emit m_adaptor->Configure();
}

void KimpanelBridge::reloadConfig()
{
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return;
    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.fcitx.Fcitx5"), QStringLiteral("/controller"),
        QStringLiteral("org.fcitx.Fcitx.Controller1"), QStringLiteral("ReloadConfig"));
    bus.call(msg, QDBus::NoBlock);
}

QJsonObject KimpanelBridge::currentState() const
{
    const bool isVisible = m_takeoverActive && (m_lookupVisible || m_preeditVisible || m_auxVisible);

    return QJsonObject{
        {QStringLiteral("userEnabled"), m_userEnabled},
        {QStringLiteral("enabled"), m_takeoverActive},
        {QStringLiteral("takeoverActive"), m_takeoverActive},
        {QStringLiteral("changing"), m_transitioning},
        {QStringLiteral("error"), m_error},
        {QStringLiteral("visible"), isVisible},
        {QStringLiteral("lookupVisible"), m_lookupVisible},
        {QStringLiteral("preeditVisible"), m_preeditVisible},
        {QStringLiteral("preeditText"), m_preeditText},
        {QStringLiteral("preeditCaret"), m_preeditCaret},
        {QStringLiteral("auxVisible"), m_auxVisible},
        {QStringLiteral("auxText"), m_auxText},
        {QStringLiteral("cursorIndex"), m_cursorIndex},
        {QStringLiteral("hasPrev"), m_hasPrev},
        {QStringLiteral("hasNext"), m_hasNext},
        {QStringLiteral("layout"), m_layout},
        {QStringLiteral("candidates"), m_candidates},
        {QStringLiteral("spot"), QJsonObject{
            {QStringLiteral("x"), m_spotX},
            {QStringLiteral("y"), m_spotY},
            {QStringLiteral("width"), m_spotWidth},
            {QStringLiteral("height"), m_spotHeight},
            {QStringLiteral("scale"), m_spotScale},
            {QStringLiteral("mode"), m_spotMode}
        }},
        {QStringLiteral("caret"), m_kwinCaret},
        {QStringLiteral("imLabel"), m_imLabel},
        {QStringLiteral("imIcon"), m_imIcon},
        {QStringLiteral("imName"), m_imName},
        {QStringLiteral("properties"), m_properties}
    };
}

void KimpanelBridge::notifyState()
{
    if (!m_destroying)
        emit stateChanged(currentState());
}

} // namespace KosPlatform
