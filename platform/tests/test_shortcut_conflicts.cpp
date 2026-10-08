// The KWin conflict repair, against a fake kglobalaccel on a private session
// bus (the test runs under dbus-run-session): the fake answers
// getGlobalShortcutsByKey with the a(ssssssaiai) shape the real daemon uses
// and records setShortcut calls, so the test pins both the wire format and
// the exact repair — release Meta+Tab from "Walk Through Windows", keep
// Alt+Tab, SetPresent set — plus the cases the repair must not touch.

#include "../src/daemon/KWinShortcutConflicts.h"

#include <QCoreApplication>
#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusContext>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDebug>
#include <QKeyCombination>
#include <QKeySequence>
#include <stdexcept>

// One entry of the a(ssssssaiai) reply, shaped like the real daemon's
// introspection (id, friendly name, component, context, keys, defaults).
// Global scope on purpose: Qt6 metatypes want a nameable type.
struct ShortcutInfo {
    QString actionUnique;
    QString actionFriendly;
    QString componentUnique;
    QString componentFriendly;
    QString contextUnique;
    QString contextFriendly;
    QList<int> keys;
    QList<int> defaults;
};

QDBusArgument &operator<<(QDBusArgument &argument, const ShortcutInfo &info)
{
    argument.beginStructure();
    argument << info.actionUnique << info.actionFriendly
             << info.componentUnique << info.componentFriendly
             << info.contextUnique << info.contextFriendly;
    // The element type is stated explicitly: QtDBus probes custom types by
    // marshalling a default instance, and a bare beginArray() over an empty
    // list corrupts that probe.
    argument.beginArray(QMetaType::fromType<int>());
    for (const int key : info.keys)
        argument << key;
    argument.endArray();
    argument.beginArray(QMetaType::fromType<int>());
    for (const int key : info.defaults)
        argument << key;
    argument.endArray();
    argument.endStructure();
    return argument;
}

const QDBusArgument &operator>>(const QDBusArgument &argument,
                                ShortcutInfo &info)
{
    argument.beginStructure();
    argument >> info.actionUnique >> info.actionFriendly
             >> info.componentUnique >> info.componentFriendly
             >> info.contextUnique >> info.contextFriendly;
    info.keys.clear();
    argument.beginArray();
    while (!argument.atEnd()) {
        int key = 0;
        argument >> key;
        info.keys.append(key);
    }
    argument.endArray();
    info.defaults.clear();
    argument.beginArray();
    while (!argument.atEnd()) {
        int key = 0;
        argument >> key;
        info.defaults.append(key);
    }
    argument.endArray();
    argument.endStructure();
    return argument;
}

Q_DECLARE_METATYPE(ShortcutInfo)
Q_DECLARE_METATYPE(QList<ShortcutInfo>)

namespace {

void require(bool ok, const char *message)
{
    if (!ok)
        throw std::runtime_error(message);
}

int key(const char *combo)
{
    const QKeySequence sequence(QString::fromLatin1(combo));
    if (sequence.isEmpty())
        throw std::runtime_error("bad test combo");
    return sequence[0].toCombined();
}

struct HeldShortcut {
    QString actionUnique;
    QString actionFriendly;
    QString componentUnique;
    QString componentFriendly;
    QList<int> keys;
};

class FakeKGlobalAccel : public QObject, protected QDBusContext
{
    Q_OBJECT
    // The same interface shape kglobalacceld exposes, including the type
    // annotation that maps the struct list onto a(ssssssaiai).
    Q_CLASSINFO("D-Bus Interface", "org.kde.KGlobalAccel")
    Q_CLASSINFO("D-Bus Introspection", ""
"  <interface name=\"org.kde.KGlobalAccel\">\n"
"    <method name=\"getGlobalShortcutsByKey\">\n"
"      <arg direction=\"in\" type=\"i\" name=\"key\"/>\n"
"      <arg direction=\"out\" type=\"a(ssssssaiai)\" name=\"shortcuts\"/>\n"
"      <annotation name=\"org.qtproject.QtDBus.QtTypeName.Out0\" value=\"QList&lt;ShortcutInfo&gt;\"/>\n"
"    </method>\n"
"    <method name=\"setShortcut\">\n"
"      <arg direction=\"in\" type=\"as\" name=\"actionId\"/>\n"
"      <arg direction=\"in\" type=\"ai\" name=\"keys\"/>\n"
"      <arg direction=\"in\" type=\"u\" name=\"flags\"/>\n"
"      <arg direction=\"out\" type=\"ai\" name=\"result\"/>\n"
"    </method>\n"
"  </interface>\n")
public:
    struct Release {
        QStringList actionId;
        QList<int> keys;
        uint flags = 0;
    };

    QList<HeldShortcut> held;
    QList<int> queriedKeys;
    QList<Release> releases;

public slots:
    QList<ShortcutInfo> getGlobalShortcutsByKey(int key)
    {
        queriedKeys.append(key);
        QList<ShortcutInfo> reply;
        for (const HeldShortcut &shortcut : held) {
            if (!shortcut.keys.contains(key))
                continue;
            reply.append(ShortcutInfo{shortcut.actionUnique,
                                      shortcut.actionFriendly,
                                      shortcut.componentUnique,
                                      shortcut.componentFriendly,
                                      QStringLiteral("default"),
                                      QStringLiteral("Default Context"),
                                      shortcut.keys,
                                      shortcut.keys});
        }
        return reply;
    }

    QList<int> setShortcut(const QStringList &actionId, const QList<int> &keys,
                           uint flags)
    {
        releases.append(Release{actionId, keys, flags});
        return keys;
    }
};

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    try {
        qDBusRegisterMetaType<ShortcutInfo>();
        qDBusRegisterMetaType<QList<ShortcutInfo>>();
        QDBusConnection bus = QDBusConnection::sessionBus();
        require(bus.isConnected(), "no session bus (run under dbus-run-session)");
        FakeKGlobalAccel fake;
        require(bus.registerService(QStringLiteral("org.kde.kglobalaccel")),
                "kglobalaccel service registration");
        require(bus.registerObject(QStringLiteral("/kglobalaccel"),
                                   QStringLiteral("org.kde.KGlobalAccel"), &fake,
                                   QDBusConnection::ExportAllSlots),
                "kglobalaccel object registration");

        const int altTab = key("Alt+Tab");
        const int metaTab = key("Meta+Tab");

        // 1. The regression this repair exists for: KOS takes Meta+Tab, and
        //    KWin's "Walk Through Windows" holds {Meta+Tab, Alt+Tab} — the
        //    repair must release Meta+Tab and keep the action alive on
        //    Alt+Tab, carrying the SetPresent flag that revives it.
        fake.held = {
            {QStringLiteral("Walk Through Windows"), QStringLiteral("遍历窗口"),
             QStringLiteral("kwin"), QStringLiteral("KWin"),
             {metaTab, altTab}},
        };
        fake.releases.clear();
        fake.queriedKeys.clear();
        QString error;
        QStringList released =
            KosPlatform::releaseKWinKeyConflicts({QStringLiteral("Meta+Tab")},
                                                 &error);
        require(error.isEmpty(), "query must not fail");
        require(released.size() == 1, "exactly one repair expected");
        require(released.first().contains(QStringLiteral("Walk Through Windows")),
                "the repair must name the action");
        require(released.first().contains(QStringLiteral("Alt+Tab")),
                "the repair must report the kept key");
        require(fake.queriedKeys == QList<int>{metaTab},
                "every combo must be queried");
        require(fake.releases.size() == 1, "exactly one setShortcut expected");
        require(fake.releases.first().actionId
                    == QStringList{QStringLiteral("kwin"),
                                   QStringLiteral("Walk Through Windows"),
                                   QStringLiteral("KWin"),
                                   QStringLiteral("遍历窗口")},
                "actionId must carry the registry's four fields");
        require(fake.releases.first().keys == QList<int>{altTab},
                "Alt+Tab must survive the release");
        // The wire value is the point: SetPresent (0x1/0x2 across daemon
        // generations) with no-autoloading semantics; 0x4 alone does not
        // revive a conflict-deactivated action (verified on Plasma 6.7.4).
        require(fake.releases.first().flags == 0x3u, "SetPresent flags");

        // 2. A single-key action whose only key KOS takes is fully replaced;
        //    the repair stays out of it (standard conflict handling owns it).
        fake.held = {
            {QStringLiteral("Show Desktop"), QStringLiteral("暂时显示桌面"),
             QStringLiteral("kwin"), QStringLiteral("KWin"), {key("Meta+D")}},
        };
        fake.releases.clear();
        released = KosPlatform::releaseKWinKeyConflicts(
            {QStringLiteral("Meta+D")}, &error);
        require(error.isEmpty(), "single-key action must not error");
        require(released.isEmpty(), "nothing to report for a full replacement");
        require(fake.releases.isEmpty(),
                "a fully replaced action must be left alone");

        // 3. Other components keep KGlobalAccel's own conflict handling.
        fake.held = {
            {QStringLiteral("some-action"), QStringLiteral("Some Action"),
             QStringLiteral("plasmashell"), QStringLiteral("Plasma"),
             {key("Meta+V")}},
        };
        fake.releases.clear();
        released = KosPlatform::releaseKWinKeyConflicts(
            {QStringLiteral("Meta+V")}, &error);
        require(released.isEmpty(), "non-KWin holders are not repaired");
        require(fake.releases.isEmpty(), "non-KWin holders are not rewritten");

        // 4. One action holding two of the combos gets a single release
        //    computed from its full original key set.
        fake.held = {
            {QStringLiteral("Custom Action"), QStringLiteral("Custom"),
             QStringLiteral("kwin"), QStringLiteral("KWin"),
             {key("Meta+B"), key("Meta+V"), key("Meta+W")}},
        };
        fake.releases.clear();
        released = KosPlatform::releaseKWinKeyConflicts(
            {QStringLiteral("Meta+B"), QStringLiteral("Meta+V")}, &error);
        require(released.size() == 1, "one release for one action");
        require(fake.releases.size() == 1, "no per-combo duplicate releases");
        require(fake.releases.first().keys == QList<int>{key("Meta+W")},
                "only the untouched key remains");
        require(fake.releases.first().flags == 0x3u, "SetPresent flags");

        // 5. Nothing holds the key: nothing happens.
        fake.held.clear();
        fake.releases.clear();
        released = KosPlatform::releaseKWinKeyConflicts(
            {QStringLiteral("Meta+Y")}, &error);
        require(error.isEmpty(), "empty registry is not an error");
        require(released.isEmpty() && fake.releases.isEmpty(),
                "no holder, no repair");
    } catch (const std::exception &e) {
        qCritical() << "FAILED:" << e.what();
        return 1;
    }
    qInfo() << "kwin shortcut conflict repair: OK";
    return 0;
}

#include "test_shortcut_conflicts.moc"
