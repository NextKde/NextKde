#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>
#include <QUrl>

#include <functional>

class QQmlEngine;
class QFileSystemWatcher;

namespace Kos::App {

// Rebuilds an application's QML root when the source tree it was loaded from
// changes. This is a development tool: it is only armed when the entry point
// was explicitly loaded from a source path (ApplicationRunner's --watch-qml),
// never for a module loaded from compiled-in resources.
//
// Two rules keep a reload from being a way to lose the window. The reload is
// debounced, because one editor save is not one filesystem event (a write plus
// a rename), and the new text is compiled before anything is torn down, so a
// file that does not parse reports its errors and leaves the current UI on
// screen. The reload callback owns teardown and loading; this class owns the
// watch, the debounce, and the validation that gates it.
//
// Long-lived state must live outside the QML tree for this to be useful: the
// ApplicationRunner hands controllers to QML through initial properties, so
// the window is rebuilt while playback, connections, and service registrations
// survive. QML-owned state (the current page, open dialogs) resets.
class ApplicationQmlReloader final : public QObject {
public:
    ApplicationQmlReloader(QQmlEngine *engine, QUrl entryPoint,
                          QStringList watchDirectories,
                          std::function<bool()> reload, QString logName,
                          QObject *parent = nullptr);

    void start();

private:
    static QStringList qmlFiles(const QString &directory);
    void refreshWatches();
    bool compiles();
    void handleChange();

    QQmlEngine *m_engine = nullptr;
    QUrl m_entryPoint;
    QStringList m_directories;
    std::function<bool()> m_reload;
    QString m_logName;
    QFileSystemWatcher *m_watcher = nullptr;
    QTimer m_debounce;
};

} // namespace Kos::App
