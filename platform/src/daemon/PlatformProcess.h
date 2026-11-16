#pragma once

#include <QJsonObject>
#include <QProcess>

// Implementation-only contracts; not part of the JSONL protocol.
namespace KosPlatform::Detail {

inline constexpr int kDefaultCommandTimeoutMs = 8000;

void armProcessWatchdog(QProcess *process, int timeoutMs);

QJsonObject parseOutput(const QByteArray &output, int exitCode);

} // namespace KosPlatform::Detail
