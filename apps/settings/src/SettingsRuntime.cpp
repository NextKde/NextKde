#include "SettingsRuntime.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QQmlApplicationEngine>
#include <QQmlComponent>

SettingsEntry chooseSettingsEntry(bool developmentSession, const QString& sessionShellDir)
{
    SettingsEntry entry;
    if (developmentSession && !sessionShellDir.isEmpty()) {
        // `KOS_SHELL_DIR` names the Shell directory, so the checkout is one
        // level up from it and the pages sit in `apps/settings`. Derived from
        // the session rather than from SETTINGS_QML_DIR, so the window runs the
        // same tree as the Shell it is editing even when the two were built from
        // different paths.
        const QString qmlPath = QDir::cleanPath(
            QDir(sessionShellDir).filePath(QStringLiteral("../apps/settings/main.qml")));
        if (QFileInfo::exists(qmlPath)) {
            entry.qmlPath = qmlPath;
            entry.checkoutRoot
                = QDir::cleanPath(QDir(sessionShellDir).filePath(QStringLiteral("..")));
            entry.source = QStringLiteral("session checkout");
            return entry;
        }
    }

    // Cleaned so the logged path is the one a reader can paste into a shell:
    // `~/.local/bin/../share/...` is what the join produces, not what exists.
    const QString installedCopy = QDir::cleanPath(QDir(QCoreApplication::applicationDirPath())
            .filePath(QStringLiteral("../share/kos/settings/main.qml")));
    if (QFileInfo::exists(installedCopy)) {
        entry.qmlPath = installedCopy;
        entry.source = QStringLiteral("installed copy");
        return entry;
    }

    entry.qmlPath = QDir::cleanPath(
        QDir(QStringLiteral(SETTINGS_QML_DIR)).filePath(QStringLiteral("main.qml")));
    entry.source = QStringLiteral("build tree");
    return entry;
}

// Rebuilds the window when the checkout it was loaded from changes. Two rules
// keep this from being a way to lose the window: the reload is debounced,
// because one editor save is not one event (a write plus a rename), and the new
// text is compiled before anything is torn down, so a file that does not parse
// reports its errors and leaves the current UI on screen.
SettingsQmlReloader::SettingsQmlReloader(QQmlApplicationEngine* engine, const QUrl& entryPoint,
    const QString& checkoutRoot, QObject* parent)
    : QObject(parent)
    , m_engine(engine)
    , m_entryPoint(entryPoint)
{
    // Only a checkout is watched. The installed copy is a destination, not
    // an edit surface: it changes when someone installs, and rebuilding the
    // window under a running user at that moment would be a surprise rather
    // than a feature -- with the shell's own copy the same `kosctl install`
    // is explicitly kept from hot-reloading anything.
    if (checkoutRoot.isEmpty())
        return;

    const QString pages = QFileInfo(entryPoint.toLocalFile()).absolutePath();
    if (!pages.isEmpty())
        m_directories.append(pages);
    // The pages import the shared tree by relative path, so both halves of
    // the window are part of the same edit loop. Only the directory itself
    // is listed here; qmlFiles() walks it.
    const QString shared = QDir(checkoutRoot).filePath(QStringLiteral("shared/qml"));
    if (QFileInfo(shared).isDir())
        m_directories.append(shared);
}

void SettingsQmlReloader::start()
{
    if (m_directories.isEmpty())
        return;

    m_debounce.setSingleShot(true);
    m_debounce.setInterval(300);
    connect(&m_debounce, &QTimer::timeout, this, [this] { reload(); });
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this,
        [this](const QString&) { m_debounce.start(); });
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this](const QString&) {
        refreshWatches();
        m_debounce.start();
    });
    refreshWatches();
}

QStringList SettingsQmlReloader::qmlFiles(const QString& directory)
{
    QStringList files;
    QDirIterator iterator(directory, { QStringLiteral("*.qml"), QStringLiteral("*.mjs") },
        QDir::Files, QDirIterator::Subdirectories);
    while (iterator.hasNext())
        files.append(iterator.next());
    return files;
}

void SettingsQmlReloader::refreshWatches()
{
    // Every subdirectory holding watched files needs a directory watch of its
    // own: an editor's atomic save replaces the file in place, which kills that
    // file's watch, and only a directoryChanged on the *containing* directory
    // fires for the replacement. pages/ and components/ sit below the watched
    // root, so watching roots alone never sees their saves.
    QStringList missingFiles;
    QStringList missingDirectories;
    QStringList queue = m_directories;
    while (!queue.isEmpty()) {
        const QString directory = queue.takeFirst();
        if (!QFileInfo(directory).isDir())
            continue;
        if (!m_watcher.directories().contains(directory))
            missingDirectories.append(directory);
        QDirIterator subdirs(directory, QDir::Dirs | QDir::NoDotAndDotDot);
        while (subdirs.hasNext())
            queue.append(subdirs.next());
        for (const QString& file : qmlFiles(directory)) {
            if (!m_watcher.files().contains(file))
                missingFiles.append(file);
        }
    }
    if (!missingDirectories.isEmpty())
        m_watcher.addPaths(missingDirectories);
    if (!missingFiles.isEmpty())
        m_watcher.addPaths(missingFiles);
}

bool SettingsQmlReloader::compiles()
{
    QQmlEngine validator;
    validator.setImportPathList(m_engine->importPathList());
    QQmlComponent component(&validator, m_entryPoint);
    if (!component.isError())
        return true;
    qWarning().noquote() << "kos-settings: QML changed but does not compile, keeping the window"
                            " as it is:"
                         << component.errorString().trimmed();
    return false;
}

void SettingsQmlReloader::reload()
{
    // Refresh before the compile check, not after: an atomic save kills the
    // saved file's watch, and the failed compile must not be the thing that
    // keeps the watch dead -- the fix the user writes next would then never be
    // seen, and the stale window would look like the watcher gave up.
    refreshWatches();
    if (!compiles())
        return;

    const QList<QObject*> roots = m_engine->rootObjects();
    for (QObject* root : roots)
        delete root;
    m_engine->clearComponentCache();
    m_engine->load(m_entryPoint);
    if (m_engine->rootObjects().isEmpty()) {
        // Only reachable for text that compiles and still fails to build its
        // root object. Say so instead of leaving an empty screen behind: the
        // watcher is still live, so the next change that works brings the
        // window back.
        qWarning().noquote() << "kos-settings: reload failed, the window is gone until the next"
                                " change that loads";
        return;
    }
    qInfo().noquote() << "kos-settings: reloaded" << m_entryPoint.toLocalFile();
    refreshWatches();
}
