#include "IndependentApps.h"
#include "AppCatalog.h"

#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>

IndependentApps::IndependentApps(QObject* parent)
    : QObject(parent)
{
    syncCatalog();
    connect(&m_flatpak, &FlatpakAppsClient::changed, this, [this] { syncCatalog(); emit changed(); });
    connect(&m_flatpak, &FlatpakAppsClient::operationFinished, this,
        [this](const QString& appId, const QString& code, const QString& message) {
            m_flatpakResults[appId] = QVariantMap{{"code", code}, {"message", message},
                {"diskSpace", m_flatpak.state(appId).value("diskSpace")}};
            const auto state = m_flatpak.state(appId);
            if (state.contains("plan")) {
                emit changed();
                return;
            }
            refresh();
        });
    connect(&m_flatpak, &FlatpakAppsClient::mutationFinished, this,
        [this](const QString& appId, const QString& code) {
            for (const auto& entry : m_apps) {
                const auto state = entry.toMap();
                if (state.value("appId").toString() == appId) {
                    emit taskFinished(state.value("name").toString(), code);
                    break;
                }
            }
        });
}

void IndependentApps::syncCatalog()
{
    const auto context = AppCatalog::contextToken();
    if (context != m_catalogContext) { m_apps.clear(); m_flatpakResults.clear(); m_catalogContext = context; }
    QVariantList next;
    for (const auto& value : AppCatalog::apps()) {
        const auto entry = value.toMap();
        // Declarative packages belong to the platform plugin registry, not Flatpak.
        if (entry.value("format").toString() == QLatin1String("declarative-widget")) continue;
        const auto appId = entry.value("appId").toString();
        const auto key = entry.value("key").toString();
        const auto id = entry.value("sourceId").toString() == "nextkde" ? key : appId;
        QVariantMap state;
        for (const auto& previous : m_apps) if (previous.toMap().value("appId").toString() == appId) state = previous.toMap();
        state["id"] = id; state["appId"] = appId;
        state["name"] = entry.value("name").toMap().value("en");
        state["nameLocales"] = entry.value("name");
        state["description"] = entry.value("description").toMap().value("en");
        state["descriptionLocales"] = entry.value("description");
        state["repository"] = "https://github.com/" + entry.value("repository").toString();
        state["sourceId"] = entry.value("sourceId");
        state["catalogActive"] = entry.value("active");
        state["catalogError"] = entry.value("error");
        state["format"] = entry.value("format");
        state["releaseTag"] = entry.value("releaseTag");
        state["testInstalled"] = AppCatalog::receipt(appId).value("entry").toMap().value("testMode").toBool();
        state["developerSignature"] = !entry.value("publisher").toMap().isEmpty();
        state["iconName"] = "grid";
        state["iconSource"] = AppCatalog::iconFile(entry);
        state["catalogVersion"] = entry.value("release").toMap().value("version");
        state["catalogApproved"] = !entry.value("release").toMap().isEmpty();
        next.append(state);
    }
    m_apps = next;
}

QVariantList IndependentApps::apps() const
{
    auto result = m_apps;
    for (int i = 0; i < result.size(); ++i) {
        auto state = result[i].toMap();
        const auto inventory = m_flatpak.state(state.value("appId").toString());
        const auto installations = inventory.value("installations").toList();
        // Only the current Flatpak identity is part of Settings inventory.
        // Native programs may coexist: they neither count as installed Flatpaks nor
        // block installation. Native cleanup is an independent, optional action.
        state["installed"] = false;
        state["managed"] = false;
        state["statusKnown"] = inventory.value("known").toBool();
        state["version"] = "";
        state["updateAvailable"] = false;
        state["flatpak"] = inventory;
        const auto progress = inventory.value("progressState").toMap();
        if (inventory.value("busy").toBool()) {
            state["busy"] = true;
            state["stage"] = progress.value("cancelling").toBool() ? QVariant("cancelling") : inventory.value("stage");
        }
        if (!inventory.value("logPath").toString().isEmpty()) {
            state["logPath"] = inventory.value("logPath");
        }
        if (inventory.value("busy").toBool()) {
            state["elapsedSeconds"] = progress.value("elapsedSeconds");
            state["progress"] = progress.value("progress").toInt() < 0 ? -1.0 : progress.value("progress").toDouble() / 100.0;
            state["transactionStatus"] = progress.value("status");
        }
        const auto appId = state.value("appId").toString();
        if (m_flatpakResults.contains(appId)) {
            const auto outcome = m_flatpakResults.value(appId).toMap();
            const auto code = outcome.value("code").toString();
            const bool environmentRecovered = inventory.value("known").toBool()
                && (code == "FLATPAK_NOT_INSTALLED" || code == "WORKER_UNAVAILABLE");
            if (!environmentRecovered) {
                state["code"] = outcome.value("code");
                state["message"] = outcome.value("message");
                state["diskSpace"] = outcome.value("diskSpace");
            }
        }
        if (!installations.isEmpty()) {
            const auto installation = installations.first().toMap();
            state["installed"] = true;
            state["managed"] = inventory.value("known").toBool() && installations.size() == 1
                && installation.value("scope").toString() == "user";
            if (inventory.value("busy").toBool()) {
                state["busy"] = true; state["stage"] = progress.value("cancelling").toBool() ? QVariant("cancelling") : inventory.value("stage");
            }
            // Cached installations do not prove that the environment still works.
            state["statusKnown"] = inventory.value("known").toBool();
            state["backend"] = "flatpak";
            state["version"] = installation.value("version");
            state["scope"] = installation.value("scope");
            state["origin"] = installation.value("origin");
            const auto source = installation.value("source").toMap();
            state["flatpakSource"] = source;
            state["bundleManaged"] = installation.value("bundleManaged");
            state["canCheckUpdates"] = !inventory.value("querying").toBool() && inventory.value("canDiscover").toBool();
            state["flatpakUpdate"] = inventory.value("update");
            state["latestVersion"] = inventory.value("update").toMap().value("version");
            state["updateAvailable"] = inventory.value("canDiscover").toBool() && state.value("managed").toBool()
                && inventory.value("update").toMap().value("available").toBool();
            state["dependencies"] = QVariantList{};
        } else {
            state["backend"] = inventory.value("canDiscover").toBool() ? "flatpak-ready" : "flatpak-unavailable";
            // Install only needs a discoverable signed release; whether one exists is
            // answered by the prepare step, not by a prior update check.
            state["available"] = inventory.value("known").toBool() && inventory.value("canDiscover").toBool();
            state["canCheckUpdates"] = !inventory.value("querying").toBool() && inventory.value("known").toBool() && inventory.value("canDiscover").toBool();
            state["latestVersion"] = inventory.value("update").toMap().value("version");
            state["updateAvailable"] = false;
            if (inventory.value("busy").toBool()) {
                state["busy"] = true; state["stage"] = progress.value("cancelling").toBool() ? QVariant("cancelling") : inventory.value("stage");
            }
        }
        state["available"] = state.value("available").toBool() && state.value("catalogActive").toBool()
            && state.value("format").toString() == "flatpak";
        state["canCheckUpdates"] = state.value("canCheckUpdates").toBool() && state.value("catalogActive").toBool();
        state["updateAvailable"] = state.value("updateAvailable").toBool() && state.value("catalogActive").toBool();
        const auto updateRecord = AppCatalog::readState("update-" + state.value("appId").toString());
        state["lastChecked"] = updateRecord.value("checkedAt");
        result[i] = state;
    }
    QVariantList visible;
    for (const auto& value : result) {
        const auto state = value.toMap();
        if (state.value("catalogActive").toBool() || state.value("installed").toBool()
            || !state.value("catalogError").toString().isEmpty()) visible.append(state);
    }
    return visible;
}
int IndependentApps::indexOf(const QString& id) const
{
    for (int i = 0; i < m_apps.size(); ++i)
        if (m_apps[i].toMap().value("id").toString() == id) return i;
    return -1;
}

void IndependentApps::refresh()
{
    syncCatalog();
    m_flatpak.refresh();
    // Source lifecycle remains an explicit CLI operation, never a fallback
    // for the Flatpak application catalogue.
}
void IndependentApps::perform(const QString& id, const QString& action)
{
    const int index = indexOf(id);
    if (index < 0 || busy()) return;
    if (action != "install" && action != "update" && action != "uninstall" && action != "check-update") return;
    const auto descriptor = m_apps[index].toMap();
    const auto appId = descriptor.value("appId").toString();
    if (descriptor.value("format").toString() != "flatpak") return;
    if (action != "uninstall" && !descriptor.value("catalogActive").toBool()) return;
    m_flatpakResults.remove(appId);
    const auto flatpak = m_flatpak.state(appId);
    if (action == "install" || action == "update") {
        const bool installing = action == "install";
        auto state = m_apps[index].toMap();
        state["code"] = "";
        state["message"] = "";
        state["flatpak"] = QVariantMap{};
        m_apps[index] = state;
        if ((installing && state.value("installed").toBool())
            || (!installing && flatpak.value("installations").toList().isEmpty())
            || !m_flatpak.preparePlan(appId, installing)) {
            state["code"] = "FLATPAK_UNAVAILABLE";
            state["message"] = flatpak.value("error").toString();
            m_apps[index] = state;
            emit changed();
        }
        return;
    }
    if (action == "check-update") {
        if (!m_flatpak.checkUpdates(appId)) {
            auto state = m_apps[index].toMap(); state["code"] = flatpak.value("publisherConfigured").toBool() ? "FLATPAK_UNAVAILABLE" : "BUNDLE_KEY_MISSING";
            state["message"] = flatpak.value("error").toString();
            m_apps[index] = state; emit changed();
        }
        return;
    }
    if (action == "uninstall" && !flatpak.value("installations").toList().isEmpty()) {
        if (!m_flatpak.uninstall(appId)) {
            auto state = m_apps[index].toMap(); state["code"] = "FLATPAK_EXTERNAL";
            m_apps[index] = state; emit changed();
        }
        return;
    }
}
void IndependentApps::confirmPlan(const QString& id, const QString& planId)
{
    const int index = indexOf(id);
    if (index < 0 || planId.isEmpty() || planId.size() > 128 || busy()) return;
    const auto appId = m_apps[index].toMap().value("appId").toString();
    const auto inventory = m_flatpak.state(appId);
    const auto plan = m_flatpak.plan(appId);
    if (!inventory.value("known").toBool() || inventory.value("querying").toBool()
        || inventory.value("busy").toBool() || plan.value("planId").toString() != planId
        || !m_flatpak.confirmPlan(appId, planId)) {
        auto state = m_apps[index].toMap();
        state["code"] = "PLAN_CHANGED";
        state["message"] = "The installation plan is no longer current. Prepare a fresh plan before continuing.";
        m_apps[index] = state;
        emit changed();
    }
}

void IndependentApps::cancel(const QString& id)
{
    const int index = indexOf(id);
    if (index >= 0 && m_flatpak.state(m_apps[index].toMap().value("appId").toString()).value("busy").toBool())
        m_flatpak.cancel();
}
void IndependentApps::open(const QString& id)
{
    const int index = indexOf(id);
    if (index < 0 || busy()) return;
    auto state = m_apps[index].toMap();
    const auto flatpak = m_flatpak.state(state.value("appId").toString());
    const auto installations = flatpak.value("installations").toList();
    if (!installations.isEmpty()) {
        if (!flatpak.value("known").toBool() || installations.size() != 1) {
            state["code"] = "FLATPAK_EXTERNAL"; m_apps[index] = state; emit changed(); return;
        }
        const auto installation = installations.first().toMap();
        QStringList arguments;
        if (installation.value("scope").toString() == "user") arguments << "--user";
        else arguments << "--installation=" + installation.value("installationId").toString();
        arguments << "run" << "--arch=" + installation.value("arch").toString()
            << "--branch=" + installation.value("branch").toString() << state.value("appId").toString();
        const auto executable = QStandardPaths::findExecutable(QStringLiteral("flatpak"));
        if (executable.isEmpty() || !QProcess::startDetached(executable, arguments)) {
            state["code"] = "OPEN_FAILED"; m_apps[index] = state; emit changed();
        }
        return;
    }
}
void IndependentApps::openLog(const QString& id)
{
    const int index = indexOf(id); if (index < 0) return;
    const auto stateHome = qEnvironmentVariable("XDG_STATE_HOME", QDir::homePath() + "/.local/state");
    QVariantMap state;
    for (const auto& item : apps()) if (item.toMap().value("id").toString() == id) state = item.toMap();
    const auto path = QFileInfo(state.value("logPath").toString()).canonicalFilePath();
    const auto root = QFileInfo(stateHome + "/kos-settings/app-store").canonicalFilePath();
    if (!root.isEmpty() && !path.isEmpty() && path.startsWith(root + '/'))
        QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}
void IndependentApps::openRepository(const QString& id)
{
    const int index = indexOf(id);
    if (index >= 0) QDesktopServices::openUrl(QUrl(m_apps[index].toMap().value("repository").toString()));
}

