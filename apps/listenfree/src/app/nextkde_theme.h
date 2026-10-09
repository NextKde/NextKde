#pragma once
#include <QObject>
#include <QFileSystemWatcher>
#include <QTimer>

namespace listenfree {
class NextKdeTheme final : public QObject {
    Q_OBJECT
public:
    explicit NextKdeTheme(QObject* parent = nullptr, const QString& configPath = {});
    bool dark() const;
    static bool resolve(const QString& appMode, const QString& desktopMode, bool systemDark);
signals:
    void changed();
private:
    QString path_, desktopMode_;
    QFileSystemWatcher watcher_;
    QTimer retry_;
    void reload();
};
}
