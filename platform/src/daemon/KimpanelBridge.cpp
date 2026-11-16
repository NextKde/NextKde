#include "KimpanelBridge.h"
#include "PlatformDbus.h"

#include <QDBusArgument>
#include <QDBusMetaType>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QRegularExpression>
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
#include <QElapsedTimer>

namespace KosPlatform {

struct FcitxAddonState {
    QString name;
    bool enabled = false;
};

} // namespace KosPlatform

Q_DECLARE_METATYPE(KosPlatform::FcitxAddonState)

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

namespace KosPlatform {

namespace {

static bool s_metaTypesRegistered = false;
void registerFcitxMetaTypes() {
    if (s_metaTypesRegistered) return;
    qDBusRegisterMetaType<FcitxAddonState>();
    qDBusRegisterMetaType<QList<FcitxAddonState>>();
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
    m_stateTimer.setSingleShot(true);
    m_stateTimer.setInterval(0);
    connect(&m_stateTimer, &QTimer::timeout, this, [this] { notifyState(); });
    m_adaptor = new ImpanelAdaptor(this);
    m_adaptor2 = new Impanel2Adaptor(this);
    m_userEnabled = loadPersistedEnabled();
    recoverOriginalFcitxAddons();
    auto *fcitxWatcher = new QDBusServiceWatcher(QStringLiteral("org.fcitx.Fcitx5"),
        QDBusConnection::sessionBus(), QDBusServiceWatcher::WatchForRegistration, this);
    connect(fcitxWatcher, &QDBusServiceWatcher::serviceRegistered, this, [this] {
        recoverOriginalFcitxAddons();
        syncTakeoverState();
    });
    auto *panelWatcher = new QDBusServiceWatcher(QStringLiteral("org.nextkde.FcitxPanel"),
        QDBusConnection::sessionBus(), QDBusServiceWatcher::WatchForUnregistration, this);
    connect(panelWatcher, &QDBusServiceWatcher::serviceUnregistered, this, [this] {
        QTimer::singleShot(500, this, [this] {
            if (m_takeoverActive && !m_transitioning && !waitForPanelAdapter()) {
                releaseTakeover();
                notifyState();
            }
        });
    });
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

QString KimpanelBridge::recoveryPath() const
{
    return QFileInfo(configPath()).dir().filePath(QStringLiteral("inputmethod-recovery.json"));
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
    const bool classicUi = state.value(QStringLiteral("classicui")).toBool();
    const bool kimpanel = state.value(QStringLiteral("kimpanel")).toBool();
    m_addonsChanged = true;
    // A process interrupted between the two KWin notifications must not leave
    // the compositor's input-method command empty after its next startup.
    auto config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    KConfigGroup wayland(config, QStringLiteral("Wayland"));
    const QString previous = state.value(QStringLiteral("kwinInputMethod")).toString();
    if (wayland.readEntry("InputMethod", QString()).isEmpty() && !previous.isEmpty()) {
        wayland.writeEntry("InputMethod", previous, KConfigBase::Notify);
        config->sync();
    }
    if (setFcitxAddons(classicUi, kimpanel)) {
        m_addonsChanged = false;
        QFile::remove(recoveryPath());
    }
}

bool KimpanelBridge::setFcitxAddons(bool classicUi, bool kimpanel)
{
    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return false;

    // Resolve first: calling a well-known name during KWin startup can
    // activate a second Fcitx without KWin's private input-method socket.
    const QString owner = bus.interface()->serviceOwner(QStringLiteral("org.fcitx.Fcitx5")).value();
    if (owner.isEmpty())
        return false;

    QList<FcitxAddonState> states;
    states.append({QStringLiteral("classicui"), classicUi});
    states.append({QStringLiteral("kimpanel"), kimpanel});

    QDBusMessage msg = QDBusMessage::createMethodCall(
        owner, QStringLiteral("/controller"),
        QStringLiteral("org.fcitx.Fcitx.Controller1"), QStringLiteral("SetAddonsState"));
    msg.setArguments({QVariant::fromValue(states)});
    QDBusMessage reply = bus.call(msg, QDBus::Block, 500);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        qWarning() << "[KimpanelBridge] SetAddonsState failed:" << reply.errorMessage();
        m_error = reply.errorMessage();
        return false;
    }

    return true;
}

bool KimpanelBridge::waitForPanelAdapter()
{
    const auto bus = QDBusConnection::sessionBus();
    QElapsedTimer deadline;
    deadline.start();
    // Fcitx's service can appear just before its module receives the desktop
    // lease. Keep processing bus events without reporting a premature success.
    const bool previousTransition = m_transitioning;
    m_transitioning = true;
    bool ready = false;
    while (deadline.elapsed() < 1500) {
        const QString owner = bus.interface()->serviceOwner(QStringLiteral("org.fcitx.Fcitx5")).value();
        if (!owner.isEmpty()
            && owner == bus.interface()->serviceOwner(QStringLiteral("org.nextkde.FcitxPanel")).value()) {
            auto call = [&](const QString &method) {
                return bus.call(QDBusMessage::createMethodCall(owner,
                    QStringLiteral("/org/nextkde/FcitxPanel"),
                    QStringLiteral("org.nextkde.FcitxPanel1"), method), QDBus::Block, 250);
            };
            const auto version = call(QStringLiteral("Version"));
            const auto native = call(QStringLiteral("NativeUiAvailable"));
            const auto active = call(QStringLiteral("Active"));
            ready = version.type() == QDBusMessage::ReplyMessage && version.arguments().size() == 1
                && version.arguments().first().toUInt() == 3
                && native.type() == QDBusMessage::ReplyMessage && native.arguments().size() == 1
                && native.arguments().first().toBool()
                && active.type() == QDBusMessage::ReplyMessage && active.arguments().size() == 1
                && active.arguments().first().toBool();
            if (ready) break;
        }
        QEventLoop loop;
        QTimer::singleShot(50, &loop, &QEventLoop::quit);
        loop.exec();
        if (!m_userEnabled || !m_shellConnected) break;
    }
    m_transitioning = previousTransition;
    if (!ready)
        m_error = QStringLiteral("NextKde panel requires the updated extension and native Classic UI; log out and back in after installation");
    return ready;
}

bool KimpanelBridge::acquireTakeover()
{
    if (m_takeoverActive)
        return true;

    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qWarning() << "[KimpanelBridge] Session bus not connected";
        return false;
    }

    if (m_addonsChanged) {
        recoverOriginalFcitxAddons();
        if (m_addonsChanged) {
            m_error = QStringLiteral("Could not restore legacy Fcitx5 addon settings");
            return false;
        }
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
        // A separate lease keeps the adapter inert when another desktop owns
        // Kimpanel, and lets Fcitx restore client callbacks when this peer dies.
        if (!bus.registerService(QStringLiteral("org.nextkde.InputPanel"))) {
            m_error = bus.lastError().message();
            bus.unregisterService(QStringLiteral("org.kde.impanel"));
            bus.unregisterObject(QStringLiteral("/org/kde/impanel"));
            return false;
        }
        m_registeredBus = true;
    }

    setupDbusListeners();

    // Fcitx selects Kimpanel on availability and suspends Classic UI itself.
    // Keep both loaded so releasing the lease restores native UI immediately.
    if (!waitForPanelAdapter()) {
        releaseTakeover();
        return false;
    }

    emit m_adaptor->PanelCreated();
    emit m_adaptor->PanelCreated2();
    emit m_adaptor2->PanelCreated2();

    m_error.clear();
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
        bus.unregisterService(QStringLiteral("org.nextkde.InputPanel"));
        bus.unregisterService(QStringLiteral("org.kde.impanel"));
        bus.unregisterObject(QStringLiteral("/org/kde/impanel"));
        m_registeredBus = false;
    }

    m_takeoverActive = false;
}

void KimpanelBridge::reassertTakeover()
{
    if (!m_takeoverActive)
        return;
    emit m_adaptor->PanelCreated();
    emit m_adaptor2->PanelCreated2();
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

    notifyState(false);
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
    notifyState(false);
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

    const bool wasVisible = m_lookupVisible;
    m_candidates = candidates;
    m_lookupVisible = !m_candidates.isEmpty();

    // Visibility edges flush immediately; content-only updates share the
    // pending snapshot without waiting for a caret query or a fixed delay.
    notifyState(wasVisible != m_lookupVisible);

    if (m_spotX == 0 && m_spotY == 0 && m_spotWidth == 0 && m_spotHeight == 0) {
        queryKWinCaret();
    }
}

void KimpanelBridge::setActiveWindowId(const QString &windowId)
{
    if (m_activeWindowId == windowId)
        return;
    // Keep a pending snapshot on its original window's side of the boundary.
    if (m_stateTimer.isActive())
        notifyState();
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
    if (m_auxVisible == visible)
        return;
    m_auxVisible = visible;
    notifyState();
}

void KimpanelBridge::onShowPreedit(bool visible)
{
    const bool changed = m_preeditVisible != visible;
    m_preeditVisible = visible;
    if (changed)
        notifyState();
    if (visible && m_spotX == 0 && m_spotY == 0) {
        queryKWinCaret();
    }
}

void KimpanelBridge::onShowLookupTable(bool visible)
{
    const bool changed = m_lookupVisible != visible;
    m_lookupVisible = visible;
    if (changed)
        notifyState();
    if (visible && m_spotX == 0 && m_spotY == 0) {
        queryKWinCaret();
    }
}

void KimpanelBridge::onUpdateLookupTableCursor(int cursor)
{
    if (m_cursorIndex == cursor)
        return;
    m_cursorIndex = cursor;
    notifyState(false);
}

void KimpanelBridge::onUpdatePreeditCaret(int caret)
{
    if (m_preeditCaret == caret)
        return;
    m_preeditCaret = caret;
    notifyState(false);
}

void KimpanelBridge::onUpdatePreeditText(const QString &text, const QString &attr)
{
    Q_UNUSED(attr);
    const bool wasVisible = m_preeditVisible;
    m_preeditText = text;
    if (!text.isEmpty()) {
        m_preeditVisible = true;
    } else if (m_candidates.isEmpty()) {
        m_preeditVisible = false;
    }
    notifyState(wasVisible != m_preeditVisible);
}

void KimpanelBridge::onUpdateAux(const QString &text, const QString &attr)
{
    Q_UNUSED(attr);
    const bool wasVisible = m_auxVisible;
    m_auxText = text;
    if (!text.isEmpty()) {
        m_auxVisible = true;
    } else if (m_candidates.isEmpty() && m_preeditText.isEmpty()) {
        m_auxVisible = false;
    }
    notifyState(wasVisible != m_auxVisible);
}

void KimpanelBridge::onUpdateSpotLocation(int x, int y)
{
    if (m_spotX == x && m_spotY == y)
        return;
    m_spotX = x;
    m_spotY = y;
    notifyState(false);
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
    if (!m_takeoverActive) return;
    auto bus = QDBusConnection::sessionBus();
    const QString owner = bus.interface()->serviceOwner(QStringLiteral("org.nextkde.FcitxPanel")).value();
    if (owner.isEmpty()) return;
    auto message = QDBusMessage::createMethodCall(owner, QStringLiteral("/org/nextkde/FcitxPanel"),
        QStringLiteral("org.nextkde.FcitxPanel1"), QStringLiteral("SelectCandidate"));
    message.setArguments({index});
    bus.call(message, QDBus::NoBlock);
}

void KimpanelBridge::pageUp()
{
    if (!m_takeoverActive) return;
    auto bus = QDBusConnection::sessionBus();
    const QString owner = bus.interface()->serviceOwner(QStringLiteral("org.nextkde.FcitxPanel")).value();
    if (owner.isEmpty()) return;
    auto message = QDBusMessage::createMethodCall(owner, QStringLiteral("/org/nextkde/FcitxPanel"),
        QStringLiteral("org.nextkde.FcitxPanel1"), QStringLiteral("PageUp"));
    bus.call(message, QDBus::NoBlock);
}

void KimpanelBridge::pageDown()
{
    if (!m_takeoverActive) return;
    auto bus = QDBusConnection::sessionBus();
    const QString owner = bus.interface()->serviceOwner(QStringLiteral("org.nextkde.FcitxPanel")).value();
    if (owner.isEmpty()) return;
    auto message = QDBusMessage::createMethodCall(owner, QStringLiteral("/org/nextkde/FcitxPanel"),
        QStringLiteral("org.nextkde.FcitxPanel1"), QStringLiteral("PageDown"));
    bus.call(message, QDBus::NoBlock);
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
    const QString owner = bus.interface()->serviceOwner(QStringLiteral("org.fcitx.Fcitx5")).value();
    if (owner.isEmpty())
        return;
    QDBusMessage msg = QDBusMessage::createMethodCall(
        owner, QStringLiteral("/controller"),
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

void KimpanelBridge::notifyState(bool immediate)
{
    if (m_destroying)
        return;
    if (!immediate) {
        // Do not restart: continuous typing must never postpone publication.
        if (!m_stateTimer.isActive())
            m_stateTimer.start();
        return;
    }

    m_stateTimer.stop();
    const QJsonObject state = currentState();
    if (state == m_lastPublishedState)
        return;
    m_lastPublishedState = state;
    emit stateChanged(state);
}

} // namespace KosPlatform
