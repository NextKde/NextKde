// The KWin shortcut repair, against a fake kglobalaccel on a private session
// bus (the test runs under dbus-run-session): the fake answers
// /component/kwin's allShortcutInfos with the a(ssssssaiai) shape the real
// daemon uses and records setShortcut calls, so the test pins both the wire
// format and the exact repairs — release Meta+Tab from "Walk Through
// Windows" while keeping Alt+Tab and SetPresent, heal that same action after
// it lost its present state, and leave everything else untouched.

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
    for (QList<int> *target : {&info.keys, &info.defaults}) {
        target->clear();
        argument.beginArray();
        while (!argument.atEnd()) {
            int key = 0;
            argument >> key;
            target->append(key);
        }
        argument.endArray();
    }
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
    QList<int> defaults;
};

class FakeKGlobalAccel : public QObject, protected QDBusContext
{
    Q_OBJECT
    // The same type annotation kglobalacceld's introspection carries, mapping
    // the struct list onto a(ssssssaiai).
    Q_CLASSINFO("D-Bus Introspection", ""
"  <interface name=\"org.kde.kglobalaccel.Component\">\n"
"    <method name=\"allShortcutInfos\">\n"
"      <arg direction=\"out\" type=\"a(ssssssaiai)\" name=\"shortcuts\"/>\n"
"      <annotation name=\"org.qtproject.QtDBus.QtTypeName.Out0\" value=\"QList&lt;ShortcutInfo&gt;\"/>\n"
"    </method>\n"
"  </interface>\n")
public:
    struct Release {
        QStringList actionId;
        QList<int> keys;
        uint flags = 0;
    };

    QList<HeldShortcut> held;
    int queries = 0;
    QList<Release> releases;

public slots:
    QList<ShortcutInfo> allShortcutInfos()
    {
        ++queries;
        QList<ShortcutInfo> reply;
        for (const HeldShortcut &shortcut : held) {
            reply.append(ShortcutInfo{shortcut.actionUnique,
                                      shortcut.actionFriendly,
                                      shortcut.componentUnique,
                                      shortcut.componentFriendly,
                                      QStringLiteral("default"),
                                      QStringLiteral("Default Context"),
                                      shortcut.keys,
                                      shortcut.defaults});
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
        require(bus.registerObject(QStringLiteral("/component/kwin"),
                                   QStringLiteral("org.kde.kglobalaccel.Component"),
                                   &fake, QDBusConnection::ExportAllSlots),
                "component object registration");
        require(bus.registerObject(QStringLiteral("/kglobalaccel"),
                                   QStringLiteral("org.kde.KGlobalAccel"), &fake,
                                   QDBusConnection::ExportAllSlots),
                "accel object registration");

        const int altTab = key("Alt+Tab");
        const int metaTab = key("Meta+Tab");
        const QStringList walkThroughId{QStringLiteral("kwin"),
                                        QStringLiteral("Walk Through Windows"),
                                        QStringLiteral("KWin"),
                                        QStringLiteral("遍历窗口")};

        // 1. The regression this repair exists for: KOS takes Meta+Tab, and
        //    KWin's "Walk Through Windows" holds {Meta+Tab, Alt+Tab} — the
        //    repair must release Meta+Tab and keep the action alive on
        //    Alt+Tab, carrying the SetPresent flag that revives it.
        fake.held = {
            {QStringLiteral("Walk Through Windows"), QStringLiteral("遍历窗口"),
             QStringLiteral("kwin"), QStringLiteral("KWin"), {metaTab, altTab},
             {metaTab, altTab}},
        };
        fake.releases.clear();
        QString error;
        QStringList repaired = KosPlatform::repairKWinKeyConflicts(
            {QStringLiteral("Meta+Tab")}, &error);
        require(error.isEmpty(), "query must not fail");
        require(fake.queries == 1, "exactly one allShortcutInfos query");
        require(repaired.size() == 1, "exactly one repair expected");
        require(repaired.first().contains(QStringLiteral("Walk Through Windows")),
                "the repair must name the action");
        require(repaired.first().contains(QStringLiteral("Meta+Tab")),
                "the repair must report the released key");
        require(repaired.first().contains(QStringLiteral("Alt+Tab")),
                "the repair must report the kept key");
        require(fake.releases.size() == 1, "exactly one setShortcut expected");
        require(fake.releases.first().actionId == walkThroughId,
                "actionId must carry the registry's four fields");
        require(fake.releases.first().keys == QList<int>{altTab},
                "Alt+Tab must survive the release");
        // The wire value is the point: SetPresent (0x1/0x2 across daemon
        // generations) with no-autoloading semantics; 0x4 alone does not
        // revive a dead action (verified on Plasma 6.7.4).
        require(fake.releases.first().flags == 0x3u, "SetPresent flags");

        // 2. The heal case: the conflict is already released (the action only
        //    holds Alt+Tab), but a lost present state stops it from firing
        //    while the registry still lists it. The default keys still
        //    involve Meta+Tab, so the action is re-presented.
        fake.held = {
            {QStringLiteral("Walk Through Windows"), QStringLiteral("遍历窗口"),
             QStringLiteral("kwin"), QStringLiteral("KWin"), {altTab},
             {altTab, metaTab}},
        };
        fake.releases.clear();
        repaired = KosPlatform::repairKWinKeyConflicts(
            {QStringLiteral("Meta+Tab")}, &error);
        require(error.isEmpty(), "heal must not error");
        require(repaired.size() == 1, "the victim must be healed");
        require(repaired.first().contains(QStringLiteral("re-presented")),
                "the repair must say it re-presented the action");
        require(fake.releases.size() == 1, "exactly one setShortcut expected");
        require(fake.releases.first().keys == QList<int>{altTab},
                "the active keys must not change");
        require(fake.releases.first().flags == 0x3u, "SetPresent flags");

        // 3. A single-key action whose only key KOS takes is fully replaced;
        //    the repair stays out of it (standard conflict handling owns it).
        fake.held = {
            {QStringLiteral("Show Desktop"), QStringLiteral("暂时显示桌面"),
             QStringLiteral("kwin"), QStringLiteral("KWin"), {key("Meta+D")},
             {key("Meta+D")}},
        };
        fake.releases.clear();
        repaired = KosPlatform::repairKWinKeyConflicts(
            {QStringLiteral("Meta+D")}, &error);
        require(error.isEmpty(), "single-key action must not error");
        require(repaired.isEmpty(), "nothing to report for a full replacement");
        require(fake.releases.isEmpty(),
                "a fully replaced action must be left alone");

        // 4. Actions KOS never collides with — neither by active nor by
        //    default keys — are never touched, even when they hold other
        //    Meta chords; other components' rows are ignored on principle.
        fake.held = {
            {QStringLiteral("Expose"), QStringLiteral("显示/隐藏窗口平铺"),
             QStringLiteral("kwin"), QStringLiteral("KWin"),
             {QKeySequence(QStringLiteral("Ctrl+F9"))[0].toCombined(),
              key("Meta+F9")},
             {QKeySequence(QStringLiteral("Ctrl+F9"))[0].toCombined(),
              key("Meta+F9")}},
            {QStringLiteral("some-action"), QStringLiteral("Some Action"),
             QStringLiteral("plasmashell"), QStringLiteral("Plasma"),
             {metaTab}, {metaTab}},
        };
        fake.releases.clear();
        repaired = KosPlatform::repairKWinKeyConflicts(
            {QStringLiteral("Meta+Tab")}, &error);
        require(repaired.isEmpty(), "non-involved actions are not repaired");
        require(fake.releases.isEmpty(), "non-involved actions are not rewritten");

        // 5. Nothing listed: nothing happens.
        fake.held.clear();
        fake.releases.clear();
        repaired = KosPlatform::repairKWinKeyConflicts(
            {QStringLiteral("Meta+Y")}, &error);
        require(error.isEmpty(), "empty registry is not an error");
        require(repaired.isEmpty() && fake.releases.isEmpty(),
                "no holder, no repair");
    } catch (const std::exception &e) {
        qCritical() << "FAILED:" << e.what();
        return 1;
    }
    qInfo() << "kwin shortcut conflict repair: OK";
    return 0;
}

#include "test_shortcut_conflicts.moc"
