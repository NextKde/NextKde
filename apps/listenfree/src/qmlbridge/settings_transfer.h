#pragma once
#include "controllers.h"
#include "infrastructure/database/database.h"
#include <QJsonObject>

namespace listenfree::qmlbridge {
// Transfers public preferences only. A preview is immutable until applied or replaced.
class SettingsTransfer final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList categories READ categories NOTIFY categoriesChanged)
    Q_PROPERTY(QString preview READ preview NOTIFY previewChanged)
public:
    SettingsTransfer(infrastructure::database::Database& db, SettingsController& settings,
                     LibraryController& library, QObject* parent = nullptr);
    QVariantList categories() const;
    QString preview() const { return preview_; }
    Q_INVOKABLE bool exportFile(const QUrl& url, const QStringList& categories);
    Q_INVOKABLE bool inspectFile(const QUrl& url);
    Q_INVOKABLE bool applyImport(const QStringList& categories);
    Q_INVOKABLE bool resetDefaults(const QStringList& categories);
    static QJsonObject schema();
signals:
    void categoriesChanged();
    void previewChanged();
    void notice(const QString& message);
private:
    infrastructure::database::Database& db_;
    SettingsController& settings_;
    LibraryController& library_;
    QJsonObject pending_;
    QStringList pendingRoots_;
    QString preview_;
    bool previewReady_{false}, createPaths_{false};
    bool apply(const QJsonObject& values, const QStringList& roots);
};
}
