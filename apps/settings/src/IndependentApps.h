#pragma once

#include "FlatpakAppsClient.h"

#include <QVariantList>

// Signed catalog entries; executable installation behavior stays in compiled adapters.
class IndependentApps final : public QObject {
    Q_OBJECT
public:
    explicit IndependentApps(QObject* parent = nullptr);
    QVariantList apps() const;
    bool busy() const { return m_flatpak.busy(); }
    bool hasActiveMutation() const { return m_flatpak.hasActiveMutation(); }
    void refresh();
    void perform(const QString& id, const QString& action);
    void confirmPlan(const QString& id, const QString& planId);
    void cancel(const QString& id);
    void open(const QString& id);
    void openLog(const QString& id);
    void openRepository(const QString& id);
signals:
    void changed();
    void taskFinished(const QString& name, const QString& code);
private:
    friend class IndependentAppsTest;
    void syncCatalog();
    int indexOf(const QString& id) const;
    FlatpakAppsClient m_flatpak;
    QVariantList m_apps;
    QVariantMap m_flatpakResults;
    QString m_catalogContext;
};
