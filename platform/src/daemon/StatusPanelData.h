#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QRegularExpression>

namespace KosPlatform {
// ss -O keeps each socket on one line. Only counters with a visible owner
// can be attributed; shared descriptors are counted once, never per owner.
inline QJsonObject parseApplicationTraffic(const QByteArray &output) {
    QJsonArray sockets;
    static const QRegularExpression owner(QStringLiteral("users:\\(\\(\"([^\"]+)\",pid=(\\d+)"));
    static const QRegularExpression inode(QStringLiteral("\\bino:(\\d+)"));
    static const QRegularExpression rx(QStringLiteral("\\bbytes_received:(\\d+)"));
    static const QRegularExpression tx(QStringLiteral("\\bbytes_sent:(\\d+)"));
    for (const QString &line : QString::fromUtf8(output).split('\n')) {
        const auto process = owner.match(line);
        const auto identity = inode.match(line);
        if (!process.hasMatch() || !identity.hasMatch()) continue;
        const auto received = rx.match(line), sent = tx.match(line);
        sockets.append(QJsonObject{{QStringLiteral("id"), identity.captured(1)},
            {QStringLiteral("name"), process.captured(1)},
            {QStringLiteral("pid"), process.captured(2).toInt()},
            {QStringLiteral("rxBytes"), received.captured(1).toDouble()},
            {QStringLiteral("txBytes"), sent.captured(1).toDouble()}});
    }
    return {{QStringLiteral("sockets"), sockets}, {QStringLiteral("scope"), QStringLiteral("user-tcp")}};
}
inline QJsonObject parsePowerProfiles(const QByteArray &output) {
    QJsonArray profiles;
    QString active;
    static const QRegularExpression profile(QStringLiteral("^\\s*(\\*)?\\s*(power-saver|balanced|performance):\\s*$"));
    QString degraded;
    for (const QString &line : QString::fromUtf8(output).split('\n')) {
        const auto match = profile.match(line);
        if (match.hasMatch()) {
            profiles.append(match.captured(2));
            if (!match.captured(1).isEmpty()) active = match.captured(2);
        }
        if (line.trimmed().startsWith(QStringLiteral("Degraded:")))
            degraded = line.section(':', 1).trimmed();
    }
    return {{QStringLiteral("profiles"), profiles}, {QStringLiteral("activeProfile"), active},
        {QStringLiteral("degraded"), degraded == QStringLiteral("no") ? QString() : degraded}};
}
}
