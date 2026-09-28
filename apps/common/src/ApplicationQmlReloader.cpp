#include "KosApp/ApplicationQmlReloader.h"

#include <QDebug>
#include <QDirIterator>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QQmlComponent>
#include <QQmlEngine>

#include <utility>

namespace Kos::App {

ApplicationQmlReloader::ApplicationQmlReloader(QQmlEngine *engine, QUrl entryPoint,
                                               QStringList watchDirectories,
                                               std::function<bool()> reload,
                                               QString logName, QObject *parent)
    : QObject(parent)
    , m_engine(engine)
    , m_entryPoint(std::move(entryPoint))
    , m_directories(std::move(watchDirectories))
    , m_reload(std::move(reload))
    , m_logName(std::move(logName))
    , m_watcher(new QFileSystemWatcher(this))
{
}

void ApplicationQmlReloader::start()
{
    if (!m_reload || m_directories.isEmpty())
        return;

    m_debounce.setSingleShot(true);
    m_debounce.setInterval(300);
    connect(&m_debounce, &QTimer::timeout, this, [this] { handleChange(); });
    connect(m_watcher, &QFileSystemWatcher::fileChanged, this,
            [this](const QString &) { m_debounce.start(); });
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
        refreshWatches();
        m_debounce.start();
    });
    refreshWatches();
}

// Both suffixes matter: the tree may import plain .mjs helpers alongside the
// .qml components, and those are edited the same way.
QStringList ApplicationQmlReloader::qmlFiles(const QString &directory)
{
    QStringList files;
    QDirIterator iterator(directory,
                          {QStringLiteral("*.qml"), QStringLiteral("*.mjs")},
                          QDir::Files, QDirIterator::Subdirectories);
    while (iterator.hasNext())
        files.append(iterator.next());
    return files;
}

// Watches are per path, not per directory, so they have to be re-listed after
// every change: an editor that saves by writing a new file over the old one
// drops the watch on the old inode.
void ApplicationQmlReloader::refreshWatches()
{
    QStringList missingFiles;
    QStringList missingDirectories;
    for (const QString &directory : std::as_const(m_directories)) {
        if (!QFileInfo(directory).isDir())
            continue;
        if (!m_watcher->directories().contains(directory))
            missingDirectories.append(directory);
        for (const QString &file : qmlFiles(directory)) {
            if (!m_watcher->files().contains(file))
                missingFiles.append(file);
        }
    }
    if (!missingDirectories.isEmpty())
        m_watcher->addPaths(missingDirectories);
    if (!missingFiles.isEmpty())
        m_watcher->addPaths(missingFiles);
}

// Compiled on a throwaway engine on purpose: the live one caches compiled QML
// by URL, so asking it about the file it already loaded answers from the cache
// -- it would pass text that no longer compiles, and the reload that followed
// would tear the window down. A fresh engine reads from disk, which is the
// whole question here.
//
// Every component in the watched tree is compiled, not just the entry point:
// the entry instantiates its siblings lazily, so a sibling that stopped
// parsing would otherwise pass the gate and only fail after the window is
// already gone.
bool ApplicationQmlReloader::compiles()
{
    QQmlEngine validator;
    validator.setImportPathList(m_engine->importPathList());

    QStringList candidates{m_entryPoint.toLocalFile()};
    for (const QString &directory : std::as_const(m_directories))
        candidates.append(qmlFiles(directory));
    candidates.removeDuplicates();

    for (const QString &file : std::as_const(candidates)) {
        QQmlComponent component(&validator, QUrl::fromLocalFile(file));
        if (component.isError()) {
            qWarning().noquote()
                << m_logName
                << ": QML changed but does not compile, keeping the window as it is:"
                << component.errorString().trimmed();
            return false;
        }
    }
    return true;
}

void ApplicationQmlReloader::handleChange()
{
    if (!compiles())
        return;
    if (!m_reload())
        return;
    qInfo().noquote() << m_logName << ": reloaded" << m_entryPoint.toLocalFile();
    refreshWatches();
}

} // namespace Kos::App
