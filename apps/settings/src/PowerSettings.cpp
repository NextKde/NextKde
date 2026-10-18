#include "PowerSettings.h"
#include "../../../platform/src/daemon/StatusPanelData.h"
#include <QDBusConnection>
#include <QJsonArray>

PowerSettings::PowerSettings(QObject *parent) : QObject(parent)
{
    m_timeout.setSingleShot(true);
    m_timeout.setInterval(12000);
    connect(&m_timeout, &QTimer::timeout, this, [this] { m_process.kill(); });
    connect(&m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        complete(status == QProcess::NormalExit && code == 0);
    });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) complete(false);
    });
    // Both service names are in use across distribution versions. Signals only
    // update/read state; they never perform a write or launch a polling helper.
    for (const QString &service : {QStringLiteral("net.hadess.PowerProfiles"),
                                  QStringLiteral("org.freedesktop.UPower.PowerProfiles")}) {
        const QString path = service == QStringLiteral("net.hadess.PowerProfiles")
            ? QStringLiteral("/net/hadess/PowerProfiles")
            : QStringLiteral("/org/freedesktop/UPower/PowerProfiles");
        QDBusConnection::systemBus().connect(service, path,
            QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("PropertiesChanged"),
            this, SLOT(systemChanged(QString,QVariantMap,QStringList)));
    }
}

PowerSettings::~PowerSettings()
{
    disconnect(&m_process, nullptr, this, nullptr);
    m_timeout.stop();
    if (m_process.state() != QProcess::NotRunning) {
        m_process.kill();
        m_process.waitForFinished(1000);
    }
}

QVariantMap PowerSettings::state() const
{
    return {{"profiles", m_profiles}, {"activeProfile", m_active}, {"pendingProfile", m_pending},
            {"degraded", m_degraded}, {"error", m_error}, {"busy", m_busy}};
}

void PowerSettings::systemChanged(const QString &interface, const QVariantMap &properties,
                                 const QStringList &invalidated)
{
    if (interface != QStringLiteral("net.hadess.PowerProfiles")
        && interface != QStringLiteral("org.freedesktop.UPower.PowerProfiles")) return;
    if (properties.contains(QStringLiteral("ActiveProfile"))) {
        ++m_revision;
        m_active = properties.value(QStringLiteral("ActiveProfile")).toString();
        emit changed();
    }
    if (!properties.isEmpty() || !invalidated.isEmpty()) refresh();
}

void PowerSettings::refresh()
{
    if (m_busy) { m_refreshQueued = true; return; }
    start({QStringLiteral("list")}, false);
}

void PowerSettings::setProfile(const QString &profile)
{
    if (m_busy || !m_profiles.contains(profile) || profile == m_active) return;
    if (profile != QStringLiteral("power-saver") && profile != QStringLiteral("balanced")
        && profile != QStringLiteral("performance")) return;
    m_pending = profile;
    ++m_revision;
    start({QStringLiteral("set"), profile}, true);
}

void PowerSettings::start(const QStringList &arguments, bool writing)
{
    m_busy = true;
    m_writing = writing;
    m_readRevision = m_revision;
    m_error.clear();
    emit changed();
    m_process.start(QStringLiteral("powerprofilesctl"), arguments);
    m_timeout.start();
}

void PowerSettings::complete(bool ok)
{
    if (!m_busy) return;
    m_timeout.stop();
    const bool writing = m_writing;
    m_busy = false;
    if (!ok) {
        m_error = writing ? QStringLiteral("Could not change power mode. Check system permissions and try again.")
                          : QStringLiteral("Power modes are not available on this system");
        if (!writing) m_profiles.clear();
        m_pending.clear();
        m_refreshQueued = false;
        emit changed();
        return;
    }
    if (writing) {
        // The helper's exit status is not the selected mode. Read back before
        // confirming the selection, including silent policy rejections.
        m_refreshQueued = false;
        refresh();
        return;
    }
    const auto parsed = KosPlatform::parsePowerProfiles(m_process.readAllStandardOutput());
    m_profiles.clear();
    for (const auto &value : parsed.value(QStringLiteral("profiles")).toArray())
        m_profiles.append(value.toString());
    if (m_revision == m_readRevision)
        m_active = parsed.value(QStringLiteral("activeProfile")).toString();
    m_degraded = parsed.value(QStringLiteral("degraded")).toString();
    if (m_profiles.isEmpty()) m_error = QStringLiteral("Power modes are not available on this system");
    else if (!m_pending.isEmpty() && m_active != m_pending)
        m_error = QStringLiteral("The system did not keep the requested power mode.");
    m_pending.clear();
    emit changed();
    if (m_refreshQueued) { m_refreshQueued = false; refresh(); }
}
