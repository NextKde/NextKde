#pragma once

#include <QJsonObject>
#include <QString>
#include <functional>

namespace KosPlatform {

// Opt-in default associations only; application/service lifecycle belongs elsewhere.
class FormaIntegration
{
public:
    using ServiceResolver = std::function<bool(const QString &)>;

    FormaIntegration();
    FormaIntegration(QString configRoot, QString stateRoot, ServiceResolver resolver = {});

    QJsonObject snapshot() const;
    QJsonObject setEnabled(bool enabled);
    QString preferredDesktopId(const QString &role) const;
    static QString finderDesktopId();

private:
    QString m_configRoot;
    QString m_stateRoot;
    ServiceResolver m_resolver;
    QString m_lastError;
};

} // namespace KosPlatform
