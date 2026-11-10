#include "AppStore.h"
#include "AppCatalog.h"
#include <QCoreApplication>
#include <QDateTime>
#include <QtConcurrentRun>

// All catalogue entries use the same Flatpak lifecycle. Native installations
// may coexist; they neither block Flatpak operations nor act as launch fallbacks.
AppStore::AppStore(const QString& directory, QObject* parent)
    : QObject(parent), m_independent(directory, this)
{
    connect(&m_independent, &IndependentApps::changed, this, &AppStore::changed);
    connect(&m_independent, &IndependentApps::taskFinished, this, &AppStore::taskFinished);
    connect(&m_catalogRefresh, &QFutureWatcher<QString>::finished, this, [this] {
        m_catalogError = m_catalogRefresh.result();
        const auto check = m_checkAfterRefresh; m_checkAfterRefresh.clear();
        if (m_catalogError.isEmpty() && !check.isEmpty()) m_independent.perform(check, "check-update");
        else m_independent.refresh();
        emit changed();
    });
    connect(&m_releases, &QFutureWatcher<QVariantMap>::finished, this, [this] {
        m_releaseResult = m_releaseContext == AppCatalog::contextToken() ? m_releases.result() : QVariantMap{};
        emit changed();
    });
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
void AppStore::checkUpdates(const QString& id)
{
    if (anyBusy() || catalogBusy()) return;
    if (testMode()) { m_independent.perform(id, "check-update"); return; }
    m_checkAfterRefresh = id; refreshCatalog();
}
void AppStore::confirmPlan(const QString& id, const QString& planId)
{ if (!anyBusy()) m_independent.confirmPlan(id, planId); }
void AppStore::cancel(const QString& id) { m_independent.cancel(id); }
void AppStore::open(const QString& id) { if (!anyBusy()) m_independent.open(id); }
void AppStore::openLog(const QString& id) { m_independent.openLog(id); }
void AppStore::openRepository(const QString& id) { m_independent.openRepository(id); }
void AppStore::cleanupProgram(const QString&, const QString&) {}


bool AppStore::testMode() const { return AppCatalog::testMode(); }
QString AppStore::setTestMode(bool enabled)
{
    if (anyBusy() || catalogBusy() || releasesBusy()) return "BUSY";
    const auto error = AppCatalog::setTestMode(enabled);
    if (error.isEmpty()) { m_catalogError.clear(); m_releaseResult.clear(); m_independent.refresh(); }
    emit changed(); return error;
}
void AppStore::loadReleases(const QString& repository)
{
    if (!testMode() || releasesBusy()) return;
    m_releaseResult.clear(); m_releaseContext = AppCatalog::contextToken();
    m_releases.setFuture(QtConcurrent::run([repository] { return AppCatalog::releaseChoices(repository); }));
    emit changed();
}
QString AppStore::selectSourceRelease(const QString& id, const QString& repository, const QString& tag)
{
    if (anyBusy() || catalogBusy()) return "BUSY";
    const auto error = AppCatalog::selectSourceRelease(id, repository, tag.trimmed());
    if (error.isEmpty()) refreshCatalog();
    emit changed(); return error;
}
QString AppStore::selectAppRelease(const QString& id, const QString& repository, const QString& tag)
{
    if (anyBusy() || catalogBusy()) return "BUSY";
    const auto error = AppCatalog::selectAppRelease(id, repository, tag.trimmed());
    if (error.isEmpty()) m_independent.refresh();
    emit changed(); return error;
}
QVariantList AppStore::sources() const { return AppCatalog::sources(); }
QVariantMap AppStore::updateStatus() const { return AppCatalog::readState("update-status"); }
bool AppStore::automaticUpdates() const { return !testMode() && AppCatalog::readState("preferences").value("automaticUpdates", true).toBool(); }
bool AppStore::updateNotifications() const { return AppCatalog::readState("preferences").value("updateNotifications", true).toBool(); }
void AppStore::setAutomaticUpdates(bool enabled)
{
    if (testMode()) return;
    auto preferences = AppCatalog::readState("preferences"); preferences["automaticUpdates"] = enabled;
    AppCatalog::writeState("preferences", preferences); emit changed();
}
void AppStore::setUpdateNotifications(bool enabled)
{
    auto preferences = AppCatalog::readState("preferences"); preferences["updateNotifications"] = enabled;
    AppCatalog::writeState("preferences", preferences); emit changed();
}
int AppStore::updateCount() const
{
    int count = 0;
    for (const auto& item : apps()) if (item.toMap().value("updateAvailable").toBool()) ++count;
    return count;
}
void AppStore::refreshCatalog()
{
    if (catalogBusy() || hasActiveMutation()) return;
    m_catalogRefresh.setFuture(QtConcurrent::run([] { return AppCatalog::refresh(); })); emit changed();
}
void AppStore::ensureCatalogFresh()
{
    if (catalogBusy() || hasActiveMutation()) return;
    // Decide freshness and fetch data on a worker while the page keeps its inventory.
    m_catalogRefresh.setFuture(QtConcurrent::run([] { return AppCatalog::refresh([] { return false; }, true); }));
    emit changed();
}
QString AppStore::addSource(const QString& id, const QString& repository, const QString& fingerprint, const QString& file)
{
    if (hasActiveMutation() || catalogBusy()) return "BUSY";
    const auto error = AppCatalog::addSource(id.trimmed(), repository.trimmed(), fingerprint.trimmed().toUpper(), file.trimmed());
    if (error.isEmpty()) refreshCatalog();
    emit changed(); return error;
}
QString AppStore::removeSource(const QString& id)
{
    if (hasActiveMutation() || catalogBusy()) return "BUSY";
    const auto error = AppCatalog::removeSource(id);
    m_independent.refresh(); emit changed(); return error;
}
bool AppStore::startUpdateAgent(bool checkNow)
{
    QProcess process;
    process.setProgram(QCoreApplication::applicationDirPath() + "/kos-app-update-agent");
    if (checkNow) process.setArguments({"--check-now"});
    // A detached session service must not keep its launcher's capture pipes open.
    process.setStandardInputFile(QProcess::nullDevice());
    process.setStandardOutputFile(QProcess::nullDevice());
    process.setStandardErrorFile(QProcess::nullDevice());
    return process.startDetached();
}
void AppStore::checkAllUpdates()
{
    if (!startUpdateAgent(true)) {
        m_catalogError = "Could not start the application update service"; emit changed();
    }
}
