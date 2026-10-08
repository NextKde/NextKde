#include "KWinShortcutConflicts.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDebug>
#include <QKeyCombination>
#include <QKeySequence>
#include <QVariant>

namespace KosPlatform {

namespace {

const QString kAccelService = QStringLiteral("org.kde.kglobalaccel");
const QString kAccelPath = QStringLiteral("/kglobalaccel");
const QString kAccelComponentPath = QStringLiteral("/component/kwin");
const QString kAccelComponentInterface =
    QStringLiteral("org.kde.kglobalaccel.Component");
const QString kAccelInterface = QStringLiteral("org.kde.KGlobalAccel");

// kglobalacceld's `setShortcut` flags (the uint on the D-Bus call). SetPresent
// brings a shortcut back from the non-present state — the daemon's
// `setInactive` is `setIsPresent(false)`, and nothing else clears that flag.
// 0x1/0x2 are the historical SetPresent/NoAutoloading numbering, 0x4 the
// modern NoAutoloading. 0x3 covers SetPresent under both numberings and is
// what re-recording the shortcut in System Settings effectively sends;
// verified against Plasma 6.7.4, where 0x3 revives a dead action while 0x4
// alone (keys updated, present flag untouched) does not.
constexpr uint kSetPresentFlags = 0x1 | 0x2;

constexpr int kCallTimeoutMs = 2000;

struct KWinShortcut {
    // {componentUnique, actionUnique, componentFriendly, actionFriendly} —
    // the actionId form the daemon's setShortcut expects.
    QStringList actionId;
    QList<int> keys;
    QList<int> defaultKeys;
};

int combinedKey(const QString &combo)
{
    const QKeySequence sequence(combo);
    return sequence.isEmpty() ? 0 : sequence[0].toCombined();
}

QString keyText(int combined)
{
    const QKeySequence sequence(QKeyCombination::fromCombined(combined));
    const QString text = sequence.toString(QKeySequence::PortableText);
    return text.isEmpty() ? QString::number(combined) : text;
}

QString keyListText(const QList<int> &keys)
{
    QStringList parts;
    parts.reserve(keys.size());
    for (const int key : keys)
        parts.append(keyText(key));
    return parts.join(QStringLiteral(", "));
}

// The reply is a(ssssssaiai): for every shortcut, the action id, its friendly
// name, the owning component and context, then the active and the default
// keys. Both key sets matter: the active keys are what to keep, the defaults
// identify the actions a KOS combo can ever collide with.
bool parseShortcutInfos(const QVariant &value, QList<KWinShortcut> *out)
{
    if (!value.canConvert<QDBusArgument>())
        return false;
    const QDBusArgument array = value.value<QDBusArgument>();
    array.beginArray();
    while (!array.atEnd()) {
        array.beginStructure();
        QString actionUnique;
        QString actionFriendly;
        QString componentUnique;
        QString componentFriendly;
        QString contextUnique;
        QString contextFriendly;
        QList<int> keys;
        QList<int> defaultKeys;
        array >> actionUnique >> actionFriendly >> componentUnique
              >> componentFriendly >> contextUnique >> contextFriendly;
        for (QList<int> *target : {&keys, &defaultKeys}) {
            target->clear();
            array.beginArray();
            while (!array.atEnd()) {
                int key = 0;
                array >> key;
                target->append(key);
            }
            array.endArray();
        }
        array.endStructure();

        // /component/kwin only ever lists KWin's own shortcuts; the check is
        // defense in depth, not a filter anyone should rely on.
        if (componentUnique != QLatin1String("kwin"))
            continue;

        out->append(KWinShortcut{
            QStringList{componentUnique, actionUnique, componentFriendly,
                        actionFriendly},
            keys,
            defaultKeys,
        });
    }
    array.endArray();
    return true;
}

} // namespace

QStringList repairKWinKeyConflicts(const QStringList &combos, QString *error)
{
    QList<int> comboKeys;
    for (const QString &combo : combos) {
        const int key = combinedKey(combo);
        if (key != 0)
            comboKeys.append(key);
    }
    if (comboKeys.isEmpty())
        return {};

    const QDBusConnection bus = QDBusConnection::sessionBus();
    QDBusMessage call = QDBusMessage::createMethodCall(
        kAccelService, kAccelComponentPath, kAccelComponentInterface,
        QStringLiteral("allShortcutInfos"));
    const QDBusMessage reply = bus.call(call, QDBus::Block, kCallTimeoutMs);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        if (error)
            *error = QStringLiteral("KGlobalAccel query failed: %1")
                         .arg(reply.errorMessage());
        return {};
    }

    QList<KWinShortcut> shortcuts;
    if (!parseShortcutInfos(reply.arguments().value(0), &shortcuts)) {
        if (error)
            *error = QStringLiteral("KGlobalAccel reply was not understood");
        return {};
    }

    QStringList repaired;
    for (const KWinShortcut &shortcut : shortcuts) {
        QList<int> releasedKeys;
        QList<int> remaining;
        for (const int key : shortcut.keys) {
            if (comboKeys.contains(key))
                releasedKeys.append(key);
            else
                remaining.append(key);
        }
        bool collidesEver = false;
        for (const int key : shortcut.defaultKeys) {
            if (comboKeys.contains(key)) {
                collidesEver = true;
                break;
            }
        }
        // Touch exactly two kinds of action: those currently holding a KOS
        // key (release it) and those whose defaults involve one (heal a lost
        // present state). Everything else — including actions fully replaced
        // by KOS, where nothing would remain — is left to KGlobalAccel.
        if (releasedKeys.isEmpty() && !collidesEver)
            continue;
        if (remaining.isEmpty())
            continue;

        QDBusMessage setCall = QDBusMessage::createMethodCall(
            kAccelService, kAccelPath, kAccelInterface,
            QStringLiteral("setShortcut"));
        setCall.setArguments({shortcut.actionId,
                              QVariant::fromValue(remaining),
                              QVariant::fromValue(kSetPresentFlags)});
        const QDBusMessage setReply =
            bus.call(setCall, QDBus::Block, kCallTimeoutMs);
        if (setReply.type() == QDBusMessage::ErrorMessage) {
            qWarning().noquote()
                << "[kos-platform] repairing KWin shortcut failed for"
                << shortcut.actionId.at(1) << ":" << setReply.errorMessage();
            continue;
        }

        if (!releasedKeys.isEmpty()) {
            repaired.append(QStringLiteral("%1: released %2 (kept %3)")
                                .arg(shortcut.actionId.at(1),
                                     keyListText(releasedKeys),
                                     keyListText(remaining)));
        } else {
            repaired.append(QStringLiteral("%1: re-presented (keys %2)")
                                .arg(shortcut.actionId.at(1),
                                     keyListText(remaining)));
        }
    }
    return repaired;
}

} // namespace KosPlatform
