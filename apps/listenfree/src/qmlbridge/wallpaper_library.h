#pragma once
#include <QObject>
#include <QFutureWatcher>
#include <QVariantList>
#include <QUrl>
#include <atomic>
#include <memory>

namespace listenfree::qmlbridge {
struct WallpaperScan {
    QVariantList items;
    QStringList roots;
    int skipped = 0;
    bool limited = false;
};
class WallpaperLibrary final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString summary READ summary NOTIFY changed)
    Q_PROPERTY(QStringList directories READ directories NOTIFY changed)
public:
    explicit WallpaperLibrary(QObject* parent = nullptr, const QStringList& steamRoots = {});
    ~WallpaperLibrary() override;
    QVariantList items() const { return result_.items; }
    bool busy() const { return busy_; }
    QString summary() const;
    QStringList directories() const { return result_.roots; }
    Q_INVOKABLE void scan(const QUrl& extraFolder = {});
    Q_INVOKABLE void cancel();
    static QStringList steamRoots();
    static WallpaperScan discover(const QStringList& steamRoots, const QString& extraFolder,
                                  const std::shared_ptr<std::atomic_bool>& cancelled);
signals:
    void changed();
private:
    QFutureWatcher<WallpaperScan> watcher_;
    std::shared_ptr<std::atomic_bool> cancelled_;
    WallpaperScan result_;
    QUrl pending_;
    QStringList roots_;
    bool busy_ = false, rescan_ = false;
};
}
