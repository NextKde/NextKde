#include "AppStore.h"

// All catalogue entries use the same Flatpak lifecycle. Native installations
// may coexist; they neither block Flatpak operations nor act as launch fallbacks.
AppStore::AppStore(const QString& directory, QObject* parent)
    : QObject(parent), m_independent(directory, this)
{
    connect(&m_independent, &IndependentApps::changed, this, &AppStore::changed);
    connect(&m_independent, &IndependentApps::taskFinished, this, &AppStore::taskFinished);
    refresh();
}
AppStore::~AppStore() = default;
QVariantList AppStore::apps() const { return m_independent.apps(); }
QVariantMap AppStore::music() const
{
    for (const auto& app : apps())
        if (app.toMap().value("id").toString() == "kmusic") return app.toMap();
    return {};
}
bool AppStore::anyBusy() const { return m_independent.busy(); }
bool AppStore::hasActiveMutation() const { return m_independent.hasActiveMutation(); }
void AppStore::refresh() { if (!anyBusy()) m_independent.refresh(); }
void AppStore::refreshApps() { refresh(); }
void AppStore::install() { install("kmusic"); }
void AppStore::uninstall() { uninstall("kmusic"); }
void AppStore::cancel() { cancel("kmusic"); }
void AppStore::open() { open("kmusic"); }
void AppStore::openLog() { openLog("kmusic"); }
void AppStore::openRepository() { openRepository("kmusic"); }
void AppStore::install(const QString& id) { if (!anyBusy()) m_independent.perform(id, "install"); }
void AppStore::uninstall(const QString& id) { if (!anyBusy()) m_independent.perform(id, "uninstall"); }
void AppStore::update(const QString& id) { if (!anyBusy()) m_independent.perform(id, "update"); }
void AppStore::checkUpdates(const QString& id) { if (!anyBusy()) m_independent.perform(id, "check-update"); }
void AppStore::confirmPlan(const QString& id, const QString& planId)
{ if (!anyBusy()) m_independent.confirmPlan(id, planId); }
void AppStore::cancel(const QString& id) { m_independent.cancel(id); }
void AppStore::open(const QString& id) { if (!anyBusy()) m_independent.open(id); }
void AppStore::openLog(const QString& id) { m_independent.openLog(id); }
void AppStore::openRepository(const QString& id) { m_independent.openRepository(id); }
void AppStore::cleanupProgram(const QString&, const QString&) {}

