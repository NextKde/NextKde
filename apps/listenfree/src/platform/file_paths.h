#pragma once
#include <QDir>
#include <QString>

namespace listenfree::platform {
#ifdef Q_OS_WIN
inline constexpr Qt::CaseSensitivity filePathSensitivity = Qt::CaseInsensitive;
#else
inline constexpr Qt::CaseSensitivity filePathSensitivity = Qt::CaseSensitive;
#endif
inline QString filePathKey(const QString& path) {
    const auto normalized = QDir::fromNativeSeparators(path);
    return filePathSensitivity == Qt::CaseInsensitive ? normalized.toCaseFolded() : normalized;
}
}
