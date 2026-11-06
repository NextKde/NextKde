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
#include <QDebug>

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

KimpanelBridge::KimpanelBridge(QObject *parent)
    : QObject(parent)
{
    registerFcitxMetaTypes();
    m_adaptor = new ImpanelAdaptor(this);
    m_adaptor2 = new Impanel2Adaptor(this);
}

KimpanelBridge::~KimpanelBridge()
{
    setEnabled(false);
}

bool KimpanelBridge::initialize()
{
    if (m_registeredBus)
        return true;

    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        qWarning() << "[KimpanelBridge] Session bus not connected";
        return false;
    }

    if (!bus.registerObject(QStringLiteral("/org/kde/impanel"), this,
                            QDBusConnection::ExportAdaptors)) {
        qWarning() << "[KimpanelBridge] Failed to register object /org/kde/impanel:"
                   << bus.lastError().message();
        return false;
    }

    if (!bus.registerService(QStringLiteral("org.kde.impanel"))) {
        qWarning() << "[KimpanelBridge] Failed to register service org.kde.impanel:"
                   << bus.lastError().message();
        bus.unregisterObject(QStringLiteral("/org/kde/impanel"));
        return false;
    }

    m_registeredBus = true;
    setupDbusListeners();

    // Broadcast panel created signal so Fcitx5 knows Kimpanel frontend is ready
    emit m_adaptor->PanelCreated();
    emit m_adaptor->PanelCreated2();
    emit m_adaptor2->PanelCreated2();

    // Disable Fcitx5 classicui so Wayland & XWayland apps route to Kimpanel
    manageFcitxClassicUi(true);

    return true;
}

void KimpanelBridge::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;

    m_enabled = enabled;
    auto bus = QDBusConnection::sessionBus();

    if (!m_enabled) {
        manageFcitxClassicUi(false);
        teardownDbusListeners();
        if (m_registeredBus) {
            bus.unregisterService(QStringLiteral("org.kde.impanel"));
            bus.unregisterObject(QStringLiteral("/org/kde/impanel"));
            m_registeredBus = false;
        }
    } else {
        initialize();
    }
    notifyState();
}

void KimpanelBridge::manageFcitxClassicUi(bool disable)
{
    // Sanitize Wayland environment: clearing GTK_IM_MODULE & QT_IM_MODULE ensures
    // applications use native Wayland text-input-v3 instead of legacy client-side
    // immodules (ClientSideInputPanel) that bypass desktop shell rendering.
    if (disable) {
        QProcess::startDetached(QStringLiteral("systemctl"),
                                {QStringLiteral("--user"), QStringLiteral("set-environment"),
                                 QStringLiteral("GTK_IM_MODULE="), QStringLiteral("QT_IM_MODULE=")});
    }

    auto bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return;

    QList<FcitxAddonState> states;
    states.append({QStringLiteral("classicui"), !disable});
    states.append({QStringLiteral("kimpanel"), true});

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.fcitx.Fcitx5"), QStringLiteral("/controller"),
        QStringLiteral("org.fcitx.Fcitx.Controller1"), QStringLiteral("SetAddonsState"));
    msg.setArguments({QVariant::fromValue(states)});
    bus.call(msg, QDBus::NoBlock);

    QDBusMessage reloadMsg = QDBusMessage::createMethodCall(
        QStringLiteral("org.fcitx.Fcitx5"), QStringLiteral("/controller"),
        QStringLiteral("org.fcitx.Fcitx.Controller1"), QStringLiteral("ReloadConfig"));
    bus.call(reloadMsg, QDBus::NoBlock);

    m_disabledClassicUi = disable;
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
    m_spotScale = 1.0;
    m_spotMode = QStringLiteral("absolute");

    if (x == 0 && y == 0 && w == 0 && h == 0) {
        queryKWinCaret();
    } else {
        notifyState();
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

    if (m_spotX == 0 && m_spotY == 0 && m_spotWidth == 0 && m_spotHeight == 0) {
        queryKWinCaret();
    } else {
        notifyState();
    }
}

void KimpanelBridge::queryKWinCaret()
{
    if (m_activeWindowId.isEmpty()) {
        notifyState();
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.KWin"), QStringLiteral("/KOSContextMenuInput"),
        QStringLiteral("org.kos.KWin.ContextMenuInput"), QStringLiteral("clipboardAnchor"));
    msg.setArguments({m_activeWindowId});

    auto *watcher = new QDBusPendingCallWatcher(
        QDBusConnection::sessionBus().asyncCall(msg, 150), this);

    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, watcher] {
        const QDBusMessage reply = watcher->reply();
        watcher->deleteLater();
        if (reply.type() != QDBusMessage::ErrorMessage && !reply.arguments().isEmpty()) {
            m_kwinCaret = QJsonObject::fromVariantMap(
                Detail::variantMapFromDbusValue(reply.arguments().first()));
        } else {
            m_kwinCaret = QJsonObject{{QStringLiteral("available"), false}};
        }
        notifyState();
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
    if (visible && m_spotX == 0 && m_spotY == 0) {
        queryKWinCaret();
    } else {
        notifyState();
    }
}

void KimpanelBridge::onShowLookupTable(bool visible)
{
    m_lookupVisible = visible;
    if (visible && m_spotX == 0 && m_spotY == 0) {
        queryKWinCaret();
    } else {
        notifyState();
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
    emit m_adaptor->ReloadConfig();
}

QJsonObject KimpanelBridge::currentState() const
{
    const bool isVisible = m_enabled && (m_lookupVisible || m_preeditVisible || m_auxVisible);

    return QJsonObject{
        {QStringLiteral("enabled"), m_enabled},
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
    emit stateChanged(currentState());
}

} // namespace KosPlatform
