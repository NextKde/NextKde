// Compatibility entry point only: every task opens in the Calendar application.
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <algorithm>
#include <QStandardPaths>
#include <QDebug>
#include <vector>
#include <unistd.h>
#include <cerrno>
#include <cstring>

int main(int argc, char *argv[])
{
    QCoreApplication app(argc, argv);
    const QDir directory(QCoreApplication::applicationDirPath());
    QString executable = directory.filePath(QStringLiteral("kos-calendar"));
    if (!QFileInfo::exists(executable))
        executable = directory.filePath(QStringLiteral("../calendar/kos-calendar"));
    if (!QFileInfo::exists(executable))
        executable = QStandardPaths::findExecutable(QStringLiteral("kos-calendar"));
    if (executable.isEmpty()) {
        qCritical() << "KOS Calendar is required to open reminders.";
        return 127;
    }
    QStringList arguments = app.arguments().mid(1);
    const bool hasView = std::any_of(arguments.cbegin(), arguments.cend(), [](const QString &arg) {
        return arg == QStringLiteral("--view") || arg.startsWith(QStringLiteral("--view="));
    });
    if (!hasView) arguments = QStringList{QStringLiteral("--view"), QStringLiteral("reminders")} + arguments;
    QList<QByteArray> encoded{QFile::encodeName(executable)};
    for (const auto &argument : arguments) encoded.append(argument.toLocal8Bit());
    std::vector<char *> raw;
    for (auto &argument : encoded) raw.push_back(argument.data());
    raw.push_back(nullptr);
    execv(encoded.front().constData(), raw.data());
    qCritical() << "Cannot open KOS Calendar:" << std::strerror(errno);
    return 127;
}
