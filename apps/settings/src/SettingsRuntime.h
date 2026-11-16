#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QUrl>

class QQmlApplicationEngine;

struct SettingsEntry {
    QString qmlPath;
    // Non-empty only when qmlPath lies in a checkout: the root whose edits are
    // watched while the window is open. Empty means "load once, never reload",
    // which is every case the user is not developing against.
    QString checkoutRoot;
    // Named in the log line, which is the only thing that tells the three trees
    // apart from the outside -- they render identically, so a wrong choice shows
    // up as nothing at all.
    QString source;
};

SettingsEntry chooseSettingsEntry(bool developmentSession, const QString& sessionShellDir);

class SettingsQmlReloader final : public QObject {
public:
    SettingsQmlReloader(QQmlApplicationEngine* engine, const QUrl& entryPoint,
        const QString& checkoutRoot, QObject* parent = nullptr);
    void start();

private:
    static QStringList qmlFiles(const QString& directory);
    void refreshWatches();
    bool compiles();
    void reload();
    QQmlApplicationEngine* m_engine = nullptr;
    QUrl m_entryPoint;
    QStringList m_directories;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};
