#pragma once

#include <QByteArray>
#include <QVariantMap>
#include <QVariantList>
#include <QString>
#include <QUrl>
#include <functional>

// Format-independent directory and trust layer. Only the Flatpak adapter knows
// about installation plans, runtime dependencies and OSTree commits.
namespace AppCatalog {
using Cancelled = std::function<bool()>;
QString validateUpdate(const QVariantMap& candidate, const QVariantMap& previous, const QString& sourceId);
QVariantList apps();
QVariantMap find(const QString& id);
QVariantList sources();
QString refresh(const Cancelled& cancelled = [] { return false; });
QString addSource(const QString& id, const QString& repository,
                  const QString& fingerprint, const QString& publicKeyFile);
QString removeSource(const QString& id);
bool verify(const QByteArray& bytes, const QByteArray& signature,
            const QByteArray& keys, const QString& fingerprint);
bool githubRepository(const QString& repository);
bool githubUrl(const QUrl& url, const QString& repository, bool redirected);
QByteArray fetch(const QUrl& url, const QString& repository, qint64 limit,
                 QString* error, const Cancelled& cancelled = [] { return false; });
QVariantMap readState(const QString& name);
bool writeState(const QString& name, const QVariantMap& value);
QVariantMap receipt(const QString& appId);
bool recordInstallation(const QString& appId, const QVariantMap& installation);
QString stateDirectory();
QString entryDigest(const QVariantMap& app);
}
