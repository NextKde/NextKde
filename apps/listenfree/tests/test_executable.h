#pragma once
#include <QCoreApplication>
#include <QString>

inline QString testExecutable(const QString& name) {
#ifdef Q_OS_WIN
    return QCoreApplication::applicationDirPath() + '/' + name + ".exe";
#else
    return QCoreApplication::applicationDirPath() + '/' + name;
#endif
}
