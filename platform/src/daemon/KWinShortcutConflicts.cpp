#include "KWinShortcutConflicts.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDebug>
#include <QHash>
#include <QKeyCombination>
#include <QKeySequence>
#include <QVariant>

namespace KosPlatform {

namespace {

const QString kAccelService = QStringLiteral("org.kde.kglobalaccel");
const QString kAccelPath = QStringLiteral("/kglobalaccel");
const QString kAccelInterface = QStringLiteral("org.kde.KGlobalAccel");

// kglobalacceld's `setShortcut` flags (the uint on the D-Bus call). SetPresent
// brings a shortcut back from the conflict-deactivated state — the daemon's
// `setInactive` is `setIsPresent(false)`, and nothing else clears that flag.
// 0x1/0x2 are the historical SetPresent/NoAutoloading numbering, 0x4 the
// modern NoAutoloading. 0x3 covers SetPresent under both numberings and is
// what re-recording the shortcut in System Settings effectively sends;
// verified against Plasma 6.7.4, where 0x3 revives a killed KWin action while
// 0x4 alone (keys updated, present flag untouched) does not.
constexpr uint kSetPresentFlags = 0x1 | 0x2;

constexpr int kCallTimeoutMs = 2000;

struct KWinAction {
    // {componentUnique, actionUnique, componentFriendly, actionFriendly} —
    // the actionId form the daemon's setShortcut expects.
    QStringList actionId;
    QList<int> keys;
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

// The D-Bus reply is a(ssssssaiai): for every shortcut, the action id, its
// friendly name, the owning component and context, then the active keys and
// the defaults. Only KWin actions are collected, only their active keys kept.
bool parseShortcutInfos(const QVariant &value, QList<KWinAction> *out)
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
        array >> actionUnique >> actionFriendly >> componentUnique
              >> componentFriendly >> contextUnique >> contextFriendly;
        array.beginArray();
        while (!array.atEnd()) {
            int key = 0;
            array >> key;
            keys.append(key);
        }
        array.endArray();
        // The defaults are walked for cursor consistency, then discarded.
        array.beginArray();
        while (!array.atEnd()) {
            int ignored = 0;
            array >> ignored;
        }
        array.endArray();
        array.endStructure();

        if (componentUnique == QLatin1String("kwin")) {
            out->append(KWinAction{
                QStringList{componentUnique, actionUnique, componentFriendly,
                            actionFriendly},
                keys,
            });
        }
    }
    array.endArray();
    return true;
}

// Queries the KWin actions that hold `key`. On failure `error` is set and the
// result is empty — the caller decides whether that is fatal (it is not).
QList<KWinAction> keyHolders(const QDBusConnection &bus, int key,
                             QString *error)
{
    QDBusMessage call = QDBusMessage::createMethodCall(
        kAccelService, kAccelPath, kAccelInterface,
        QStringLiteral("getGlobalShortcutsByKey"));
    call.setArguments({key});
    const QDBusMessage reply = bus.call(call, QDBus::Block, kCallTimeoutMs);
    if (reply.type() == QDBusMessage::ErrorMessage) {
        if (error)
            *error = QStringLiteral("KGlobalAccel query for %1 failed: %2")
                         .arg(keyText(key), reply.errorMessage());
        return {};
    }
    QList<KWinAction> actions;
    if (!parseShortcutInfos(reply.arguments().value(0), &actions)) {
        if (error)
            *error = QStringLiteral(
                         "KGlobalAccel reply for %1 was not understood")
                         .arg(keyText(key));
        return {};
    }
    return actions;
}

} // namespace

QStringList releaseKWinKeyConflicts(const QStringList &combos, QString *error)
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

    // Collect first, release second: one KWin action can hold two of the
    // combos, and the registry view goes stale the moment the first release
    // lands. Collecting gives every action one release computed from its full
    // original key set.
    QHash<QString, KWinAction> kwinActions;
    for (const int key : comboKeys) {
        QString queryError;
        const QList<KWinAction> holders = keyHolders(bus, key, &queryError);
        if (!queryError.isEmpty()) {
            if (error)
                *error = queryError;
            return {};
        }
        for (const KWinAction &action : holders) {
            if (action.keys.contains(key))
                kwinActions.insert(action.actionId.at(1), action);
        }
    }

    QStringList released;
    for (const KWinAction &action : kwinActions) {
        QList<int> releasedKeys;
        QList<int> remaining;
        for (const int key : action.keys) {
            if (comboKeys.contains(key))
                releasedKeys.append(key);
            else
                remaining.append(key);
        }
        // Every key of the action is taken by KOS (full replacement, standard
        // conflict handling) — or none is (nothing to do). Either way this
        // repair stays out of it.
        if (releasedKeys.isEmpty() || remaining.isEmpty())
            continue;

        QDBusMessage call = QDBusMessage::createMethodCall(
            kAccelService, kAccelPath, kAccelInterface,
            QStringLiteral("setShortcut"));
        call.setArguments({action.actionId, QVariant::fromValue(remaining),
                           QVariant::fromValue(kSetPresentFlags)});
        const QDBusMessage reply = bus.call(call, QDBus::Block, kCallTimeoutMs);
        if (reply.type() == QDBusMessage::ErrorMessage) {
            qWarning().noquote()
                << "[kos-platform] releasing KWin shortcut keys failed for"
                << action.actionId.at(1) << ":" << reply.errorMessage();
            continue;
        }

        QStringList releasedText;
        QStringList remainingText;
        for (const int key : releasedKeys)
            releasedText.append(keyText(key));
        for (const int key : remaining)
            remainingText.append(keyText(key));
        released.append(QStringLiteral("%1: released %2 (kept %3)")
                            .arg(action.actionId.at(1),
                                 releasedText.join(QStringLiteral(", ")),
                                 remainingText.join(QStringLiteral(", "))));
    }
    return released;
}

} // namespace KosPlatform
