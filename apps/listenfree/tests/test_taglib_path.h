#pragma once
#include <QFile>
#include <QString>
#include <string>

// TagLib accepts UTF-16 filenames on Windows and native bytes on Unix.
inline auto testTagLibPath(const QString& path) {
#ifdef Q_OS_WIN
    return path.toStdWString();
#else
    return QFile::encodeName(path).toStdString();
#endif
}
