#include "nextkde_theme.h"
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QGuiApplication>
#include <QPalette>
#include <QStandardPaths>
#include <QStyleHints>

namespace listenfree {
NextKdeTheme::NextKdeTheme(QObject* parent, const QString& configPath) : QObject(parent) {
    path_ = configPath.isEmpty() ? QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation)
        + "/quickshell/kos/appearance/config.json" : configPath;
    connect(&watcher_, &QFileSystemWatcher::fileChanged, this, [this] { reload(); });
    connect(&watcher_, &QFileSystemWatcher::directoryChanged, this, [this] { reload(); });
    connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged, this, &NextKdeTheme::changed);
    connect(qGuiApp, &QGuiApplication::paletteChanged, this, &NextKdeTheme::changed);
    // Retry also covers startup before the shell has created its state directory.
    retry_.setInterval(2000);
    connect(&retry_, &QTimer::timeout, this, &NextKdeTheme::reload);
    retry_.start();
    reload();
}
void NextKdeTheme::reload() {
    const auto directory = QFileInfo(path_).absolutePath();
    if (QDir(directory).exists() && !watcher_.directories().contains(directory)) watcher_.addPath(directory);
    if (QFileInfo::exists(path_) && !watcher_.files().contains(path_)) watcher_.addPath(path_);
    QFile file(path_);
    QString mode;
    if (file.open(QIODevice::ReadOnly)) {
        QJsonParseError error;
        const auto document = QJsonDocument::fromJson(file.readAll(), &error);
        if (error.error != QJsonParseError::NoError) return; // Preserve last complete write.
        mode = document.object().value("themeMode").toString();
    }
    if (mode != desktopMode_) { desktopMode_ = mode; emit changed(); }
}
bool NextKdeTheme::resolve(const QString& appMode, const QString& desktopMode, bool systemDark) {
    if (appMode == "Dark") return true;
    if (appMode == "Light") return false;
    if (desktopMode == "dark") return true;
    if (desktopMode == "light") return false;
    return systemDark;
}
bool NextKdeTheme::dark() const {
    const auto scheme = QGuiApplication::styleHints()->colorScheme();
    const auto color = QGuiApplication::palette().color(QPalette::Window);
    const bool systemDark = scheme == Qt::ColorScheme::Unknown
        ? color.redF() * .2126 + color.greenF() * .7152 + color.blueF() * .0722 < .5
        : scheme == Qt::ColorScheme::Dark;
    return resolve("System", desktopMode_, systemDark);
}
}
