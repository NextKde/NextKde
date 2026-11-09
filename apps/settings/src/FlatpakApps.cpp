#include "FlatpakApps.h"
#include "FlatpakCompatibility.h"
#include "FlatpakTrustPolicy.h"
#include "FlatpakRelease.h"
#include <QTemporaryDir>
#include "IndependentAppRegistry.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QRegularExpression>
#include <QDateTime>
#include <QUuid>
#include <QSet>
#include <QLockFile>
#include <QStorageInfo>
#include <sys/stat.h>
#include <limits>
#include <algorithm>
#include <mutex>
#include <unistd.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <csignal>
#include <cstdio>
#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>

#include <QtConcurrentRun>
#include <QVariantList>

// GLib's signals member must not expand to Qt's signals keyword macro.
#pragma push_macro("signals")
#undef signals
#include <flatpak.h>
#include <ostree.h>
#pragma pop_macro("signals")

namespace {
constexpr quint64 sizeLimit = 2ULL * 1024ULL * 1024ULL * 1024ULL;

bool approvedOrigin(FlatpakInstallation* installation, FlatpakRemote* remote,
    GCancellable* cancellable, bool runtime);

QString refString(FlatpakRef* ref)
{
    auto* formatted = flatpak_ref_format_ref_cached(ref);
    return formatted ? QString::fromUtf8(formatted) : QString();
}

// Match Flatpak identity + architecture + branch, never native host libraries.
// Follow user-before-system lookup, and retain scope/commit for the deployment
// recheck. A compatible installed runtime does not require a user remote.
QVariantMap installedDependency(FlatpakInstallation* user, const QString& refText,
    GCancellable* cancellation, const QString& role, const QString& appId)
{
    const auto parts = refText.split('/');
    if (parts.size() != 4 || parts[0] != "runtime") return {};
    QVariantMap result;
    const auto inspect = [&](FlatpakInstallation* scope) {
        auto* ref = flatpak_installation_get_installed_ref(scope, FLATPAK_REF_KIND_RUNTIME,
            parts[1].toUtf8().constData(), parts[2].toUtf8().constData(), parts[3].toUtf8().constData(), cancellation, nullptr);
        if (!ref) return false;
        const auto origin = QString::fromUtf8(flatpak_installed_ref_get_origin(ref));
        auto* remote = flatpak_installation_get_remote_by_name(scope, origin.toUtf8().constData(), cancellation, nullptr);
        const bool approved = remote && approvedOrigin(scope, remote, cancellation, true);
        if (approved) {
            auto* root = flatpak_installation_get_path(scope);
            auto* path = g_file_get_path(root);
            auto* url = flatpak_remote_get_url(remote);
            const auto commit = QString::fromUtf8(flatpak_ref_get_commit(FLATPAK_REF(ref)));
            result = {{"role", role}, {"ref", refText}, {"commit", commit}, {"installedCommit", commit},
                {"remote", origin}, {"origin", origin}, {"sourceUrl", QString::fromUtf8(url)},
                {"installationPath", QString::fromUtf8(path)}, {"action", "reuse"},
                {"downloadBytes", 0}, {"installedBytes", QVariant::fromValue<qulonglong>(flatpak_installed_ref_get_installed_size(ref))},
                {"sizeKnown", true}, {"sizeSource", "installed-flatpak-ref"}, {"appId", appId}};
            g_free(path); g_free(url); g_object_unref(root);
        } else {
            result = {{"code", "RUNTIME_PLAN_UNAVAILABLE"},
                {"message", QString("Installed runtime %1 has an unapproved origin; it was not replaced.").arg(refText)}};
        }
        if (remote) g_object_unref(remote);
        g_object_unref(ref);
        return true;
    };
    if (inspect(user)) return result;
    GError* error = nullptr;
    auto* systems = flatpak_get_system_installations(cancellation, &error);
    if (!systems) {
        g_clear_error(&error);
        return {{"code", "RUNTIME_PLAN_UNAVAILABLE"}, {"message", "System runtime inventory could not be read."}};
    }
    for (guint i = 0; i < systems->len; ++i)
        if (inspect(FLATPAK_INSTALLATION(g_ptr_array_index(systems, i)))) break;
    g_ptr_array_unref(systems);
    return result;
}

QVariantMap dependencyPlan(FlatpakInstallation* installation, const QString& refText,
    GCancellable* cancellation, const QString& role, const QString& appId, QVariantMap* failure)
{
    const auto parts = refText.split('/');
    if (parts.size() != 4 || parts[0] != "runtime") return {};
    GError* error = nullptr;
    const auto existing = installedDependency(installation, refText, cancellation, role, appId);
    if (existing.contains("code")) { if (failure) *failure = existing; return {}; }
    if (!existing.isEmpty()) return existing;
    GPtrArray* remotes = flatpak_installation_list_remotes(installation, cancellation, &error);
    if (!remotes) { g_clear_error(&error); return {}; }
    int approvedSources = 0;
    int approvedMatches = 0;
    QVariantMap remoteCandidate;
    for (guint i = 0; i < remotes->len; ++i) {
        auto* remote = FLATPAK_REMOTE(g_ptr_array_index(remotes, i));
        if (!approvedOrigin(installation, remote, cancellation, true)) continue;
        ++approvedSources;
        const auto name = QString::fromUtf8(flatpak_remote_get_name(remote));
        auto* remoteUrl = flatpak_remote_get_url(remote);
        const auto sourceUrl = remoteUrl ? QString::fromUtf8(remoteUrl) : QString();
        g_free(remoteUrl);
        auto* remoteRef = flatpak_installation_fetch_remote_ref_sync(installation, name.toUtf8().constData(),
            FLATPAK_REF_KIND_RUNTIME, parts[1].toUtf8().constData(), parts[2].toUtf8().constData(),
            parts[3].toUtf8().constData(), cancellation, &error);
        if (!remoteRef) { g_clear_error(&error); continue; }
        const auto ref = refString(FLATPAK_REF(remoteRef));
        const auto commit = QString::fromUtf8(flatpak_ref_get_commit(FLATPAK_REF(remoteRef)));
        const auto download = flatpak_remote_ref_get_download_size(remoteRef);
        const auto size = flatpak_remote_ref_get_installed_size(remoteRef);
        if (ref == refText && commit.size() == 64 && download <= sizeLimit && size <= sizeLimit) {
            ++approvedMatches;
            remoteCandidate = {{"remote", name}, {"sourceUrl", sourceUrl}, {"commit", commit},
                {"downloadBytes", QVariant::fromValue<qulonglong>(download)},
                {"installedBytes", QVariant::fromValue<qulonglong>(size)}};
        }
        g_object_unref(remoteRef);
    }
    g_ptr_array_unref(remotes);
    g_clear_error(&error);
    if (approvedMatches != 1) {
        if (failure) *failure = {{"code", approvedSources == 0 ? "RUNTIME_SOURCE_MISSING" : "RUNTIME_PLAN_UNAVAILABLE"},
            {"message", QString("Required runtime: %1. Approved user sources: %2; matching runtime candidates: %3.")
                .arg(refText).arg(approvedSources).arg(approvedMatches)}};
        return {};
    }
    const auto remote = remoteCandidate.value("remote").toString();
    const auto commit = remoteCandidate.value("commit").toString();
    return {{"role", role}, {"ref", refText}, {"commit", commit}, {"remote", remote},
        {"sourceUrl", remoteCandidate.value("sourceUrl")}, {"action", "install"},
        {"installedCommit", ""}, {"origin", ""},
        {"downloadBytes", remoteCandidate.value("downloadBytes")},
        {"installedBytes", remoteCandidate.value("installedBytes")},
        {"sizeKnown", true}, {"sizeSource", "flatpak-remote-ref"}, {"appId", appId}};
}

// Reserve conservatively before transferring the bundle, then recheck before
// deployment. Shared OSTree objects may reduce actual usage; never count reused
// runtimes again or assume that the cache and installation share a filesystem.
QVariantMap checkInstallSpace(const QVariantMap& plan, const QString& cachePath, bool beforeDownload)
{
    const auto unknown = []() -> QVariantMap {
        return {{"code", "SPACE_CHECK_FAILED"}, {"message", "Cannot determine installation space requirements or available storage."}};
    };
    quint64 cacheBytes = 0, installBytes = 0;
    bool applicationSeen = false;
    const auto add = [](quint64& total, const QVariant& value) {
        bool ok = false;
        const auto bytes = value.toULongLong(&ok);
        if (!ok || bytes > sizeLimit || total > quint64(std::numeric_limits<qint64>::max()) - bytes) return false;
        total += bytes;
        return true;
    };
    const auto operations = plan.value("operationSet").toList();
    if (operations.isEmpty()) return unknown();
    for (const auto& item : operations) {
        const auto operation = item.toMap();
        if (operation.value("action").toString() == "reuse") continue;
        if (!add(installBytes, operation.value("installedBytes"))) return unknown();
        if (operation.value("role").toString() == "application") {
            applicationSeen = true;
            if (beforeDownload && !add(cacheBytes, operation.value("downloadBytes"))) return unknown();
        } else if (!add(installBytes, operation.value("downloadBytes"))) return unknown();
    }
    if (!applicationSeen) return unknown();
    auto* user = flatpak_installation_new_user(nullptr, nullptr);
    if (!user) return unknown();
    auto* directory = flatpak_installation_get_path(user);
    auto* rawPath = g_file_get_path(directory);
    const auto installPath = QString::fromUtf8(rawPath);
    g_free(rawPath); g_object_unref(directory); g_object_unref(user);
    struct Requirement { quint64 bytes = 0; qint64 available = -1; QString location, path; };
    QMap<quint64, Requirement> disks;
    const auto reserve = [&](const QString& path, quint64 bytes, const QString& location) {
        if (!QDir::isAbsolutePath(path)) return false;
        QString probe = path;
        while (!QFileInfo::exists(probe)) {
            const auto parent = QFileInfo(probe).dir().absolutePath();
            if (parent == probe) return false;
            probe = parent;
        }
        QStorageInfo storage(probe);
        storage.refresh();
        struct stat info {};
        if (!storage.isValid() || !storage.isReady() || storage.isReadOnly()
            || storage.bytesAvailable() < 0 || ::stat(QFile::encodeName(probe).constData(), &info) != 0) return false;
        auto& disk = disks[quint64(info.st_dev)];
        if (disk.available < 0) {
            // Per-filesystem headroom for metadata, temporary files and writes
            // between checks. This is internal, not a displayed size promise.
            disk.bytes = 256ULL * 1024 * 1024;
            disk.available = storage.bytesAvailable();
            disk.location = location; disk.path = path;
        } else {
            disk.available = std::min(disk.available, storage.bytesAvailable());
            disk.location = "combined";
        }
        if (disk.bytes > quint64(std::numeric_limits<qint64>::max()) - bytes) return false;
        disk.bytes += bytes;
        return true;
    };
    if ((beforeDownload && !reserve(cachePath, cacheBytes, "download"))
        || !reserve(installPath, installBytes, "installation")) return unknown();
    for (const auto& disk : disks) {
        if (disk.bytes <= quint64(disk.available)) continue;
        const auto missing = disk.bytes - quint64(disk.available);
        return {{"code", "DISK_FULL"},
            {"message", QString("Insufficient space at %1: required %2, available %3, missing %4 bytes.")
                .arg(disk.path).arg(disk.bytes).arg(disk.available).arg(missing)},
            {"diskSpace", QVariantMap{{"requiredBytes", QVariant::fromValue<qulonglong>(disk.bytes)},
                {"availableBytes", disk.available}, {"missingBytes", QVariant::fromValue<qulonglong>(missing)},
                {"location", disk.location}, {"beforeDownload", beforeDownload}}}};
    }
    return {};
}

volatile std::sig_atomic_t helperInterrupted = 0;
void interruptHelper(int) { helperInterrupted = 1; }

bool approvedOrigin(FlatpakInstallation* installation, FlatpakRemote* remote, GCancellable* cancellable, bool runtime = false)
{
    if (!flatpak_remote_get_gpg_verify(remote) || flatpak_remote_get_disabled(remote)) return false;
    auto* url = flatpak_remote_get_url(remote);
    QStringList fingerprints;
    for (const auto& entry : FlatpakTrustPolicy::remotes)
        if ((runtime ? entry.runtimes : entry.applications)
            && QString::fromUtf8(entry.url).startsWith("https://") && QString::fromUtf8(url) == entry.url
            && QRegularExpression("^[0-9A-F]{40}([0-9A-F]{24})?$").match(QString::fromLatin1(entry.primaryFingerprint)).hasMatch())
            fingerprints.append(QString::fromLatin1(entry.primaryFingerprint));
    g_free(url);
    if (fingerprints.isEmpty()) return false;
    auto* root = flatpak_installation_get_path(installation);
    auto* path = g_file_get_child(root, "repo");
    g_object_unref(root);
    auto* repo = ostree_repo_new(path);
    g_object_unref(path);
    GError* error = nullptr;
    GPtrArray* keys = nullptr;
    gboolean summary = FALSE;
    bool approved = ostree_repo_open(repo, cancellable, &error)
        && ostree_repo_remote_get_gpg_verify_summary(repo, flatpak_remote_get_name(remote), &summary, &error)
        && summary && ostree_repo_remote_get_gpg_keys(repo, flatpak_remote_get_name(remote), nullptr,
            &keys, cancellable, &error);
    if (approved) {
        approved = keys->len > 0;
        for (guint i = 0; i < keys->len; ++i) {
            auto* key = static_cast<GVariant*>(g_ptr_array_index(keys, i));
            auto* subkeys = g_variant_get_child_value(key, 0);
            if (g_variant_n_children(subkeys) == 0) approved = false;
            else {
                auto* primary = g_variant_get_child_value(subkeys, 0);
                const char* fingerprint = nullptr;
                gboolean revoked = FALSE, expired = FALSE, invalid = FALSE;
                g_variant_lookup(primary, "fingerprint", "&s", &fingerprint);
                g_variant_lookup(primary, "revoked", "b", &revoked);
                g_variant_lookup(primary, "expired", "b", &expired);
                g_variant_lookup(primary, "invalid", "b", &invalid);
                approved &= fingerprint && fingerprints.contains(QString::fromLatin1(fingerprint))
                    && !revoked && !expired && !invalid;
                g_variant_unref(primary);
            }
            g_variant_unref(subkeys);
        }
    }
    if (keys) g_ptr_array_unref(keys);
    g_clear_error(&error);
    g_object_unref(repo);
    return approved;
}

// Native and Flatpak installations may coexist. Never inspect native commands,
// desktop entries or source ownership to decide Flatpak availability. Only the
// selected Flatpak ref/scope and transaction state govern install/update/remove.
// Legacy native cleanup is optional and is never an installation prerequisite.
QString errorCode(const GError* error)
{
    if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) return "CANCELLED";
    if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_TIMED_OUT)) return "NETWORK_TIMEOUT";
    if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_NO_SPACE)
        || g_error_matches(error, FLATPAK_ERROR, FLATPAK_ERROR_OUT_OF_SPACE)) return "DISK_FULL";
    if (g_error_matches(error, FLATPAK_ERROR, FLATPAK_ERROR_UNTRUSTED)) return "FLATPAK_UNTRUSTED";
    if (g_error_matches(error, FLATPAK_ERROR, FLATPAK_ERROR_RUNTIME_NOT_FOUND)) return "FLATPAK_RUNTIME_MISSING";
    return "FLATPAK_FAILED";
}

bool approvedBundleInstallation(FlatpakInstallation* installation, FlatpakInstalledRef* installed, GCancellable* cancellation)
{
    const auto appId = QString::fromUtf8(flatpak_ref_get_name(FLATPAK_REF(installed)));
    const auto keys = FlatpakRelease::publicKeys(appId);
    if (QString::fromUtf8(flatpak_ref_get_branch(FLATPAK_REF(installed))) != "stable"
        || QString::fromUtf8(flatpak_ref_get_arch(FLATPAK_REF(installed))) != QString::fromUtf8(flatpak_get_default_arch())) return false;
    auto* remote = flatpak_installation_get_remote_by_name(installation, flatpak_installed_ref_get_origin(installed), cancellation, nullptr);
    if (!remote) return false;
    auto* url = flatpak_remote_get_url(remote);
    const bool local = (!url || !*url) && (keys.isEmpty() || flatpak_remote_get_gpg_verify(remote));
    g_free(url); g_object_unref(remote);
    if (!local) return false;
    if (keys.isEmpty()) {
        const auto record = AppCatalog::receipt(appId);
        const auto entry = AppCatalog::find(appId);
        return record.value("sourceId") == entry.value("sourceId")
            && record.value("repository") == entry.value("repository")
            && record.value("commit").toString() == QString::fromUtf8(flatpak_ref_get_commit(FLATPAK_REF(installed)))
            && record.value("arch").toString() == QString::fromUtf8(flatpak_ref_get_arch(FLATPAK_REF(installed)))
            && record.value("origin").toString() == QString::fromUtf8(flatpak_installed_ref_get_origin(installed))
            && record.value("sha256").toString().size() == 64;
    }
    const auto cache = qEnvironmentVariable("XDG_CACHE_HOME", QDir::homePath() + "/.cache") + "/kos-settings/flatpak";
    if (!QDir::isAbsolutePath(cache) || !QDir().mkpath(cache)) return false;
    QTemporaryDir temporary(cache + "/installed-XXXXXX");
    if (!temporary.isValid()) return false;
    QFile key(temporary.filePath("publisher.gpg"));
    if (!key.open(QIODevice::WriteOnly | QIODevice::NewOnly, QFileDevice::ReadOwner | QFileDevice::WriteOwner)
        || key.write(keys) != keys.size()) return false;
    key.close();
    auto* root = flatpak_installation_get_path(installation);
    auto* path = g_file_get_child(root, "repo");
    auto* repo = ostree_repo_new(path);
    auto* keydir = g_file_new_for_path(temporary.path().toUtf8().constData());
    auto* keyring = g_file_new_for_path(key.fileName().toUtf8().constData());
    GError* error = nullptr;
    auto* result = ostree_repo_open(repo, cancellation, &error)
        ? ostree_repo_verify_commit_ext(repo, flatpak_ref_get_commit(FLATPAK_REF(installed)), keydir, keyring, cancellation, &error) : nullptr;
    bool approved = false;
    if (result) {
        for (guint i = 0; i < ostree_gpg_verify_result_count_all(result); ++i) {
            OstreeGpgSignatureAttr attributes[]{OSTREE_GPG_SIGNATURE_ATTR_VALID, OSTREE_GPG_SIGNATURE_ATTR_SIG_EXPIRED,
                OSTREE_GPG_SIGNATURE_ATTR_KEY_EXPIRED, OSTREE_GPG_SIGNATURE_ATTR_KEY_REVOKED,
                OSTREE_GPG_SIGNATURE_ATTR_FINGERPRINT_PRIMARY};
            auto* values = ostree_gpg_verify_result_get(result, i, attributes, 5);
            gboolean valid, expired, keyExpired, revoked;
            const char* primary = nullptr;
            g_variant_get(values, "(bbbb&s)", &valid, &expired, &keyExpired, &revoked, &primary);
            approved |= valid && !expired && !keyExpired && !revoked
                && FlatpakRelease::fingerprints(appId).contains(QString::fromLatin1(primary));
            g_variant_unref(values);
        }
        g_object_unref(result);
    }
    g_clear_error(&error);
    g_object_unref(keyring); g_object_unref(keydir); g_object_unref(repo); g_object_unref(path); g_object_unref(root);
    return approved;
}

struct DeploymentGuard {
    FlatpakInstallation* installation;
    GCancellable* cancellation;
    QString appId, ref, origin, commit;
    QVariantMap selected;
    QVariantMap authorizedPlan;
    bool installing;
    QString refusal;

    bool localUnchanged()
    {
        GError* error = nullptr;
        auto* installed = flatpak_installation_get_installed_ref(installation, FLATPAK_REF_KIND_APP,
            appId.toUtf8().constData(), selected.value("arch").toString().toUtf8().constData(),
            selected.value("branch").toString().toUtf8().constData(), cancellation, &error);
        bool valid = false;
        if (installing) valid = !installed && g_error_matches(error, FLATPAK_ERROR, FLATPAK_ERROR_NOT_INSTALLED);
        else valid = installed && !error
            && QString::fromUtf8(flatpak_ref_get_commit(FLATPAK_REF(installed))) == selected.value("commit").toString()
            && QString::fromUtf8(flatpak_installed_ref_get_origin(installed)) == origin
            && approvedBundleInstallation(installation, installed, cancellation);
        if (installed) g_object_unref(installed);
        g_clear_error(&error);
        // Refuse another branch/architecture or a concurrent system installation for this ID.
        auto* systems = flatpak_get_system_installations(cancellation, &error);
        if (!systems) { g_clear_error(&error); return false; }
        for (guint i = 0; valid && i <= systems->len; ++i) {
            auto* scope = i == systems->len ? installation
                : static_cast<FlatpakInstallation*>(g_ptr_array_index(systems, i));
            auto* refs = flatpak_installation_list_installed_refs_by_kind(scope, FLATPAK_REF_KIND_APP, cancellation, &error);
            if (!refs) { valid = false; g_clear_error(&error); break; }
            for (guint j = 0; j < refs->len; ++j) {
                auto* ref = FLATPAK_REF(g_ptr_array_index(refs, j));
                const auto id = QString::fromUtf8(flatpak_ref_get_name(ref));
                if (id != appId) continue;
                if (installing || scope != installation
                    || QString::fromUtf8(flatpak_ref_get_arch(ref)) != selected.value("arch").toString()
                    || QString::fromUtf8(flatpak_ref_get_branch(ref)) != selected.value("branch").toString()) valid = false;
            }
            g_ptr_array_unref(refs);
        }
        g_ptr_array_unref(systems);
        return valid;
    }

    bool approved(const QString& name, bool runtime)
    {
        GError* error = nullptr;
        auto* remote = flatpak_installation_get_remote_by_name(installation, name.toUtf8().constData(), cancellation, &error);
        bool valid = remote && approvedOrigin(installation, remote, cancellation, runtime);
        if (remote) {
            if (!runtime) {
                auto* url = flatpak_remote_get_url(remote);
                valid &= QString::fromUtf8(url) == selected.value("source").toMap().value("url").toString();
                g_free(url);
            }
            g_object_unref(remote);
        }
        g_clear_error(&error);
        return valid;
    }

    bool ready(FlatpakTransaction* transaction)
    {
        if (!localUnchanged() || !FlatpakRelease::configured(appId)
            || authorizedPlan.value("catalogEntryDigest").toString() != AppCatalog::entryDigest(AppCatalog::find(appId))) {
            refusal = "The installation or publisher trust changed. Refresh before retrying.";
            return false;
        }
        auto* operations = flatpak_transaction_get_operations(transaction);
        bool valid = true, targetSeen = false;
        QVariantList expectedOperations = authorizedPlan.value("operationSet").toList();
        QSet<QString> seen;
        QString requiredRuntime;
        if (expectedOperations.isEmpty()) valid = false;
        for (auto* node = operations; valid && node; node = node->next) {
            auto* operation = static_cast<FlatpakTransactionOperation*>(node->data);
            const auto name = QString::fromUtf8(flatpak_transaction_operation_get_ref(operation));
            const auto remote = QString::fromUtf8(flatpak_transaction_operation_get_remote(operation));
            const auto type = flatpak_transaction_operation_get_operation_type(operation);
            const auto expectedIt = std::find_if(expectedOperations.cbegin(), expectedOperations.cend(),
                [&](const QVariant& value) { return value.toMap().value("ref").toString() == name; });
            if (expectedIt == expectedOperations.cend() || seen.contains(name)) { valid = false; break; }
            const auto expected = expectedIt->toMap();
            const auto expectedCommit = expected.value("commit").toString();
            const auto expectedRemote = expected.value("remote").toString();
            const auto expectedAction = expected.value("action").toString();
            const bool isTarget = name == ref;
            const bool isReuse = expectedAction == "reuse";
            const auto expectedType = isTarget ? FLATPAK_TRANSACTION_OPERATION_INSTALL_BUNDLE
                : expectedAction == "update" ? FLATPAK_TRANSACTION_OPERATION_UPDATE : FLATPAK_TRANSACTION_OPERATION_INSTALL;
            if (isReuse) valid = false;
            if (isTarget) {
                targetSeen = true;
                auto* source = flatpak_installation_get_remote_by_name(installation, remote.toUtf8().constData(), cancellation, nullptr);
                auto* url = source ? flatpak_remote_get_url(source) : nullptr;
                valid &= type == expectedType && source && (!url || !*url) && (FlatpakRelease::publicKeys(appId).isEmpty() || flatpak_remote_get_gpg_verify(source))
                    && (installing || remote == origin) && expectedCommit == commit
                    && QString::fromUtf8(flatpak_transaction_operation_get_commit(operation)) == commit;
                g_free(url);
                if (source) g_object_unref(source);
                auto* metadata = flatpak_transaction_operation_get_metadata(operation);
                auto* runtime = metadata ? g_key_file_get_string(metadata, "Application", "runtime", nullptr) : nullptr;
                requiredRuntime = QString::fromUtf8(runtime);
                g_free(runtime);
                if (requiredRuntime.isEmpty()) valid = false;
            } else {
                valid &= name.startsWith("runtime/") && type == expectedType && expectedCommit
                    == QString::fromUtf8(flatpak_transaction_operation_get_commit(operation)) && approved(remote, true)
                    && (expectedRemote.isEmpty() || expectedRemote == remote);
            }
            seen.insert(name);
            if (!valid) break;
        }
        if (valid && targetSeen) {
            for (const auto& item : expectedOperations) {
                const auto expected = item.toMap();
                const auto name = expected.value("ref").toString();
                if (expected.value("role").toString() == "application") continue;
                if (expected.value("action").toString() == "reuse") {
                    const auto reused = installedDependency(installation, name, cancellation,
                        expected.value("role").toString(), appId);
                    valid = !reused.isEmpty() && !reused.contains("code")
                        && reused.value("commit") == expected.value("commit")
                        && reused.value("origin") == expected.value("origin")
                        && reused.value("installationPath") == expected.value("installationPath");
                    if (!valid) break;
                } else if (!seen.contains(name)) valid = false;
            }
            valid &= seen.size() == std::count_if(expectedOperations.cbegin(), expectedOperations.cend(),
                [](const QVariant& value) { return value.toMap().value("action").toString() != "reuse"; });
        }
        g_list_free_full(operations, g_object_unref);
        if (!valid || !targetSeen) refusal = "The transaction includes an unapproved app, runtime, origin or operation.";
        return valid && targetSeen;
    }
};
}

struct FlatpakApps::Cancellation {
    GCancellable* value = g_cancellable_new();
    std::mutex mutex;
    QString status;
    int progress = -1;
    bool cancelling = false;
    ~Cancellation() { g_object_unref(value); }

    static void attach(FlatpakTransaction* transaction, const std::shared_ptr<Cancellation>& state)
    {
        using Shared = std::shared_ptr<Cancellation>;
        g_signal_connect_data(transaction, "new-operation", G_CALLBACK(+[](FlatpakTransaction*,
            FlatpakTransactionOperation*, FlatpakTransactionProgress* progress, gpointer data) {
            const auto state = *static_cast<Shared*>(data);
            flatpak_transaction_progress_set_update_frequency(progress, 250);
            const auto changed = +[](FlatpakTransactionProgress* progress, gpointer data) {
                const auto state = *static_cast<Shared*>(data);
                auto* status = flatpak_transaction_progress_get_status(progress);
                std::lock_guard lock(state->mutex);
                state->status = QString::fromUtf8(status);
                state->progress = flatpak_transaction_progress_get_is_estimating(progress)
                    ? -1 : flatpak_transaction_progress_get_progress(progress);
                g_free(status);
            };
            auto* shared = new Shared(state);
            g_signal_connect_data(progress, "changed", G_CALLBACK(changed), shared,
                +[](gpointer data, GClosure*) { delete static_cast<Shared*>(data); }, GConnectFlags(0));
            changed(progress, shared);
        }), new Shared(state), +[](gpointer data, GClosure*) { delete static_cast<Shared*>(data); }, GConnectFlags(0));
    }
};

QVariantMap FlatpakApps::executeRemoval(const QVariantMap& request, const std::shared_ptr<Cancellation>& cancellation)
{
    const auto appId = request.value("appId").toString();
    const auto app = IndependentAppRegistry::find(appId);
    if (!app || request.value("action").toString() != "uninstall") return {{"code", "RESULT_UNKNOWN"}};
    const auto selectedId = appId;
    const auto selected = request.value("selected").toMap();
    if (selected.value("scope").toString() != "user") return {{"code", "RESULT_UNKNOWN"}};
    const auto refName = QStringLiteral("app/%1/%2/%3").arg(selectedId,
        selected.value("arch").toString(), selected.value("branch").toString()).toUtf8();
    const auto commit = selected.value("commit").toString();
    const auto origin = selected.value("origin").toString();
    QVariantMap result;
    GError* error = nullptr;
    auto* installation = flatpak_installation_new_user(cancellation->value, &error);
    FlatpakInstalledRef* installed = nullptr;
    FlatpakTransaction* transaction = nullptr;
    if (installation) {
        installed = flatpak_installation_get_installed_ref(installation, FLATPAK_REF_KIND_APP,
            selectedId.toUtf8().constData(), selected.value("arch").toString().toUtf8().constData(),
            selected.value("branch").toString().toUtf8().constData(), cancellation->value, &error);
    }
    if (installed && (commit != QString::fromUtf8(flatpak_ref_get_commit(FLATPAK_REF(installed)))
        || origin != QString::fromUtf8(flatpak_installed_ref_get_origin(installed)))) {
        result["code"] = "RESULT_UNKNOWN";
        result["message"] = "The installation changed. Refresh before uninstalling.";
    } else if (installed) {
        transaction = flatpak_transaction_new_for_installation(installation, cancellation->value, &error);
        if (transaction) {
            Cancellation::attach(transaction, cancellation);
            struct Removal { QByteArray ref; QString selectedId, commit, origin; };
            Removal removal{refName, selectedId, commit, origin};
            const auto ready = +[](FlatpakTransaction* transaction, gpointer data) -> gboolean {
                const auto& removal = *static_cast<Removal*>(data);
                auto* operations = flatpak_transaction_get_operations(transaction);
                bool allowed = g_list_length(operations) == 1;
                for (auto* it = operations; it; it = it->next) {
                    auto* operation = FLATPAK_TRANSACTION_OPERATION(it->data);
                    allowed &= flatpak_transaction_operation_get_operation_type(operation) == FLATPAK_TRANSACTION_OPERATION_UNINSTALL
                        && QByteArray(flatpak_transaction_operation_get_ref(operation)) == removal.ref;
                }
                g_list_free_full(operations, g_object_unref);
                auto* installation = flatpak_transaction_get_installation(transaction);
                auto* refs = flatpak_installation_list_installed_refs_by_kind(installation, FLATPAK_REF_KIND_APP, nullptr, nullptr);
                int count = 0;
                if (!refs) return FALSE;
                for (guint i = 0; i < refs->len; ++i) {
                    auto* installed = FLATPAK_INSTALLED_REF(g_ptr_array_index(refs, i));
                    if (QString::fromUtf8(flatpak_ref_get_name(FLATPAK_REF(installed))) != removal.selectedId) continue;
                    ++count;
                    allowed &= removal.commit == QString::fromUtf8(flatpak_ref_get_commit(FLATPAK_REF(installed)))
                        && removal.origin == QString::fromUtf8(flatpak_installed_ref_get_origin(installed));
                }
                g_ptr_array_unref(refs);
                return allowed && count == 1;
            };
            g_signal_connect(transaction, "ready-pre-auth", G_CALLBACK(ready), &removal);
            g_signal_connect(transaction, "ready", G_CALLBACK(ready), &removal);
            flatpak_transaction_set_no_interaction(transaction, TRUE);
            flatpak_transaction_set_no_pull(transaction, TRUE);
            flatpak_transaction_set_disable_dependencies(transaction, TRUE);
            flatpak_transaction_set_disable_related(transaction, TRUE);
            flatpak_transaction_set_include_unused_uninstall_ops(transaction, FALSE);
            if (!flatpak_transaction_add_uninstall(transaction, refName.constData(), &error)
                || !flatpak_transaction_run(transaction, cancellation->value, &error))
                result["code"] = "FLATPAK_FAILED";
        }
    }
    if (error) {
        result["code"] = errorCode(error);
        result["message"] = QString::fromUtf8(error->message);
        g_clear_error(&error);
    } else if (!installed || (!transaction && result.isEmpty())) {
        result["code"] = "RESULT_UNKNOWN";
    }
    // Drop ownership only after a successful removal and a fresh inventory.
    // Keep the receipt on any ambiguous result so withdrawn apps remain manageable.
    if (result.isEmpty() && transaction) {
        auto* refs = flatpak_installation_list_installed_refs_by_kind(installation,
            FLATPAK_REF_KIND_APP, cancellation->value, &error);
        bool absent = refs != nullptr;
        if (refs) {
            for (guint i = 0; i < refs->len; ++i)
                absent &= appId != QString::fromUtf8(flatpak_ref_get_name(FLATPAK_REF(g_ptr_array_index(refs, i))));
            g_ptr_array_unref(refs);
        }
        if (!absent || !AppCatalog::forgetInstallation(appId)) {
            result["code"] = "RESULT_UNKNOWN";
            if (error) result["message"] = QString::fromUtf8(error->message);
        }
        g_clear_error(&error);
    }
    if (transaction) g_object_unref(transaction);
    if (installed) g_object_unref(installed);
    if (installation) g_object_unref(installation);
    return result;
}

QVariantMap FlatpakApps::executeDeployment(const QVariantMap& request, const std::shared_ptr<Cancellation>& cancellation)
{
    const auto appId = request.value("appId").toString();
    const auto discovery = request.value("discovery").toMap();
    const auto selected = request.value("selected").toMap();
    const auto authorizedPlan = request.value("authorizedPlan").toMap();
    const bool installing = request.value("action").toString() == "install";
    const auto path = request.value("path").toString();
    if (authorizedPlan.value("appId").toString() != appId
        || authorizedPlan.value("operation").toString() != request.value("action").toString()
        || authorizedPlan.value("selected") != selected
        || authorizedPlan.value("catalogEntryDigest") != discovery.value("catalogEntryDigest")
        || authorizedPlan.value("bundleDigest") != discovery.value("sha256")
        || authorizedPlan.value("metadataSha256") != discovery.value("metadataSha256")
        || authorizedPlan.value("bundleCommit") != discovery.value("commit"))
        return {{"code", "PLAN_CHANGED"}, {"message", "The authorized installation plan no longer matches the selected bundle."}};
    auto result = checkInstallSpace(authorizedPlan, QFileInfo(path).absolutePath(), false);
    if (!result.isEmpty()) return result;
    result = FlatpakRelease::validateDownloaded(appId, discovery, path,
        [cancellation] { return bool(g_cancellable_is_cancelled(cancellation->value)); });
    if (!result.isEmpty()) return result;
    const auto catalogEntry = AppCatalog::find(appId);
    if (AppCatalog::entryDigest(catalogEntry) != discovery.value("catalogEntryDigest").toString())
        return {{"code", "CATALOG_CHANGED"}};
    const auto target = discovery.value("commit").toString();
    bool valid = false;
    const int order = installing ? 1 : FlatpakRelease::compareVersions(discovery.value("version").toString(), selected.value("version").toString(), &valid);
    if (selected.value("scope").toString() != "user" || selected.value("branch").toString() != "stable"
        || selected.value("arch").toString() != QString::fromUtf8(flatpak_get_default_arch())
        || discovery.value("arch") != selected.value("arch")
        || (!installing && (!valid || order <= 0))) return {{"code", "VERSION_CONFLICT"}};
    GError* error = nullptr;
    auto* file = g_file_new_for_path(path.toUtf8().constData());
    auto* bundle = flatpak_bundle_ref_new(file, &error);
    if (bundle) {
        auto* origin = flatpak_bundle_ref_get_origin(bundle);
        auto* runtimeRepo = flatpak_bundle_ref_get_runtime_repo_url(bundle);
        const bool valid = flatpak_ref_get_kind(FLATPAK_REF(bundle)) == FLATPAK_REF_KIND_APP
            && QString::fromUtf8(flatpak_ref_get_name(FLATPAK_REF(bundle))) == appId
            && QString::fromUtf8(flatpak_ref_get_arch(FLATPAK_REF(bundle))) == selected.value("arch").toString()
            && QString::fromUtf8(flatpak_ref_get_branch(FLATPAK_REF(bundle))) == "stable"
            && QString::fromUtf8(flatpak_ref_get_commit(FLATPAK_REF(bundle))) == target
            && (!origin || !*origin) && (!runtimeRepo || !*runtimeRepo);
        g_free(origin); g_free(runtimeRepo);
        if (!valid) result = {{"code", "FLATPAK_UNTRUSTED"}, {"message", "Bundle identity, commit or embedded source does not match the approved standalone release contract."}};
    }
    auto* installation = bundle && result.isEmpty() ? flatpak_installation_new_user(cancellation->value, &error) : nullptr;
    FlatpakTransaction* transaction = nullptr;
    const auto ref = QStringLiteral("app/%1/%2/stable").arg(appId, selected.value("arch").toString());
    DeploymentGuard guard{installation, cancellation->value, appId, ref,
        selected.value("origin").toString(), target, selected, authorizedPlan, installing, {}};
    if (installation && guard.localUnchanged()) {
        transaction = flatpak_transaction_new_for_installation(installation, cancellation->value, &error);
        if (transaction) {
            Cancellation::attach(transaction, cancellation);
            flatpak_transaction_set_no_interaction(transaction, TRUE);
            flatpak_transaction_set_include_unused_uninstall_ops(transaction, FALSE);
            flatpak_transaction_add_default_dependency_sources(transaction);
            flatpak_transaction_set_disable_dependencies(transaction, TRUE);
            flatpak_transaction_set_disable_related(transaction, TRUE);
            bool dependenciesAdded = true;
            for (const auto& item : authorizedPlan.value("operationSet").toList()) {
                const auto dependency = item.toMap();
                if (dependency.value("role").toString() == "application" || dependency.value("action").toString() == "reuse") continue;
                if (!flatpak_transaction_add_install(transaction, dependency.value("remote").toString().toUtf8().constData(),
                    dependency.value("ref").toString().toUtf8().constData(), nullptr, &error)) {
                    dependenciesAdded = false;
                    break;
                }
            }
            const auto ready = +[](FlatpakTransaction* transaction, gpointer data) -> gboolean {
                return static_cast<DeploymentGuard*>(data)->ready(transaction);
            };
            g_signal_connect(transaction, "ready-pre-auth", G_CALLBACK(ready), &guard);
            g_signal_connect(transaction, "ready", G_CALLBACK(ready), &guard);
            g_signal_connect(transaction, "add-new-remote", G_CALLBACK(+[](FlatpakTransaction*, int,
                const char*, const char*, const char*, gpointer) -> gboolean { return FALSE; }), nullptr);
            g_signal_connect(transaction, "choose-remote-for-ref", G_CALLBACK(+[](FlatpakTransaction*,
                const char*, const char*, const char* const* remotes, gpointer data) -> int {
                auto* guard = static_cast<DeploymentGuard*>(data);
                int selected = -1;
                for (int i = 0; remotes && remotes[i]; ++i) {
                    if (!guard->approved(QString::fromUtf8(remotes[i]), true)) continue;
                    if (selected >= 0) return -1;
                    selected = i;
                }
                return selected;
            }), &guard);
            const auto bytes = FlatpakRelease::publicKeys(appId);
            auto* keys = bytes.isEmpty() ? nullptr : g_bytes_new(bytes.constData(), bytes.size());
            const bool added = dependenciesAdded && flatpak_transaction_add_install_bundle(transaction, file, keys, &error);
            if (keys) g_bytes_unref(keys);
            { std::lock_guard lock(cancellation->mutex); cancellation->status = "Resolving and deploying Flatpak bundle"; cancellation->progress = -1; }
            if (!added || !flatpak_transaction_run(transaction, cancellation->value, &error)) result["code"] = "FLATPAK_FAILED";
        }
    } else if (result.isEmpty() && !error) result["code"] = "RESULT_UNKNOWN";
    if (error) {
        result["code"] = errorCode(error);
        result["message"] = QString::fromUtf8(error->message);
        g_clear_error(&error);
    } else if (!transaction && result.isEmpty()) result["code"] = "RESULT_UNKNOWN";
    if (!guard.refusal.isEmpty()) {
        result["code"] = "FLATPAK_UNTRUSTED";
        result["message"] = guard.refusal;
    }
    if (result.isEmpty() && installation) {
        auto* deployed = flatpak_installation_get_installed_ref(installation, FLATPAK_REF_KIND_APP,
            appId.toUtf8().constData(), selected.value("arch").toString().toUtf8().constData(), "stable", nullptr, nullptr);
        if (!deployed || QString::fromUtf8(flatpak_ref_get_commit(FLATPAK_REF(deployed))) != target) {
            result["code"] = "RESULT_UNKNOWN";
        } else {
            const auto entry = catalogEntry;
            if (!AppCatalog::recordInstallation(appId, {{"entry", entry}, {"sourceId", entry.value("sourceId")},
                {"repository", entry.value("repository")}, {"commit", target}, {"sha256", discovery.value("sha256")},
                {"arch", selected.value("arch")}, {"origin", QString::fromUtf8(flatpak_installed_ref_get_origin(deployed))}}))
                result["code"] = "RECEIPT_WRITE_FAILED";
        }
        if (deployed) g_object_unref(deployed);
    }
    if (transaction) g_object_unref(transaction);
    if (installation) g_object_unref(installation);
    if (bundle) g_object_unref(bundle);
    g_object_unref(file);
    return result;
}

int FlatpakTransactionProcess::helperMain()
{
    const auto parent = ::getppid();
    if (parent <= 1 || ::prctl(PR_SET_PDEATHSIG, SIGKILL) != 0 || ::getppid() != parent) return 2;
    const rlimit noCore{0, 0};
    setrlimit(RLIMIT_CORE, &noCore);
    std::signal(SIGTERM, interruptHelper);
    std::signal(SIGINT, interruptHelper);
    QFile input;
    if (!input.open(stdin, QIODevice::ReadOnly)) return 2;
    const auto bytes = input.read(65537);
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(bytes, &error);
    if (bytes.size() > 65536 || error.error != QJsonParseError::NoError || !document.isObject()) return 2;
    const auto request = document.object().toVariantMap();
    const auto action = request.value("action").toString();
    QDir().mkpath(AppCatalog::stateDirectory());
    QLockFile mutationLock(AppCatalog::stateDirectory() + "/flatpak-mutation.lock");
    if (!mutationLock.tryLock(0)) {
        const auto bytes = QJsonDocument(QJsonObject{{"type", "result"}, {"result", QJsonObject{{"code", "BUSY"}}}}).toJson(QJsonDocument::Compact);
        std::puts(bytes.constData()); return 0;
    }
    const auto app = IndependentAppRegistry::find(request.value("appId").toString());
    if (!app || !QStringList{"install", "update", "uninstall"}.contains(action)) return 2;
    const auto cancellation = std::make_shared<FlatpakApps::Cancellation>();
    QTimer timer;
    timer.setInterval(100);
    QString lastStatus;
    int lastProgress = -2;
    const auto send = [](const QJsonObject& object) {
        std::puts(QJsonDocument(object).toJson(QJsonDocument::Compact).constData());
        std::fflush(stdout);
    };
    QObject::connect(&timer, &QTimer::timeout, [&] {
        if (helperInterrupted) g_cancellable_cancel(cancellation->value);
        std::lock_guard lock(cancellation->mutex);
        if (lastStatus == cancellation->status && lastProgress == cancellation->progress) return;
        lastStatus = cancellation->status.left(4096);
        lastProgress = cancellation->progress;
        send({{"type", "progress"}, {"status", lastStatus}, {"progress", lastProgress}});
    });
    QFutureWatcher<QVariantMap> worker;
    QObject::connect(&worker, &QFutureWatcher<QVariantMap>::finished, [&] {
        send({{"type", "result"}, {"result", QJsonObject::fromVariantMap(worker.result())}});
        QCoreApplication::exit(0);
    });
    timer.start();
    worker.setFuture(QtConcurrent::run([request, cancellation, action] {
        return action == "install" || action == "update"
            ? FlatpakApps::executeDeployment(request, cancellation) : FlatpakApps::executeRemoval(request, cancellation);
    }));
    return QCoreApplication::exec();
}

FlatpakApps::FlatpakApps(QObject* parent) : QObject(parent)
{
    m_deadline.setSingleShot(true);
    m_deadline.setInterval(10000);
    connect(&m_deadline, &QTimer::timeout, this, [this] {
        if (m_cancellation) g_cancellable_cancel(m_cancellation->value);
    });
    connect(&m_watcher, &QFutureWatcher<Inventory>::finished, this, [this] {
        m_deadline.stop();
        const auto result = m_watcher.result();
        // Failed enumeration must not pretend that every app was uninstalled.
        if (result.error.isEmpty()) m_inventory = result;
        else m_inventory.error = result.error;
        m_cancellation.reset();
        for (auto it = m_updates.begin(); it != m_updates.end();) {
            const auto entries = m_inventory.apps.value(it.key()).toList();
            const auto update = it.value().toMap();
            const bool unchanged = update.value("installation").toMap().isEmpty()
                ? entries.isEmpty()
                : entries.size() == 1 && update.value("installation").toMap() == entries.first().toMap();
            if (!m_inventory.error.isEmpty() || !unchanged) it = m_updates.erase(it);
            else ++it;
        }
        if (m_verifying) {
            auto code = m_transactionCode;
            auto message = m_transactionMessage;
            if (!result.error.isEmpty()) {
                code = "RESULT_UNKNOWN";
                message = result.error;
                if (m_action == "check-update") m_updates.remove(m_activeId);
            } else {
                const auto installations = result.apps.value(m_activeId).toList();
                if (m_action == "check-update" && code.isEmpty()) {
                    const bool unchanged = m_checkedInstallation.isEmpty()
                        ? installations.isEmpty()
                        : installations.size() == 1 && installations.first().toMap() == m_checkedInstallation;
                    if (!unchanged) {
                        code = "RESULT_UNKNOWN";
                        m_updates.remove(m_activeId);
                    }
                } else if (m_action == "update" || m_action == "install") {
                    bool matches = false;
                    for (const auto& entry : installations) {
                        const auto installed = entry.toMap();
                        matches |= installed.value("scope").toString() == "user"
                            && installed.value("bundleManaged").toBool()
                            && (m_action == "install" || installed.value("origin") == m_checkedInstallation.value("origin"))
                            && installed.value("arch") == m_checkedInstallation.value("arch")
                            && installed.value("branch") == m_checkedInstallation.value("branch")
                            && installed.value("commit").toString() == m_targetCommit;
                    }
                    if (!matches && code.isEmpty()) code = "RESULT_UNKNOWN";
                } else if (m_action == "uninstall") {
                    bool stillInstalled = false;
                    for (const auto& entry : installations)
                        stillInstalled |= entry.toMap().value("scope").toString() == "user";
                    if (stillInstalled && code.isEmpty()) code = "RESULT_UNKNOWN";
                }
            }
            const auto appId = m_activeId;
            m_progressTimer.stop();
            m_log.write((QDateTime::currentDateTimeUtc().toString(Qt::ISODate) + " " + code + ": " + message + '\n').toUtf8());
            m_log.close();
            m_progress["cancelling"] = false;
            m_progress["status"] = "";
            const bool mutated = isAppMutation(m_action);
            m_activeId.clear(); m_action.clear(); m_verifying = false;
            emit operationFinished(appId, code, message);
            if (mutated) emit mutationFinished(appId, code);
        }
        emit changed();
    });
    m_transactionDeadline.setSingleShot(true);
    m_transactionDeadline.setInterval(30000);
    connect(&m_transactionDeadline, &QTimer::timeout, this, [this] {
        m_timedOut = true;
        cancel();
    });
    connect(&m_transaction, &QFutureWatcher<QVariantMap>::finished, this, [this] {
        m_transactionDeadline.stop();
        const auto result = m_transaction.result();
        m_transactionCode = m_timedOut ? QStringLiteral("FLATPAK_TIMEOUT") : result.value("code").toString();
        m_transactionMessage = result.value("message").toString();
        m_progress["diskSpace"] = result.value("diskSpace").toMap();
        // Cancelling source preparation must not start another discovery/plan
        // pass, even if the local source was saved just before cancellation.
        if (m_action == "setup-runtime-source" && m_transactionCode.isEmpty()
            && m_transactionCancellation && g_cancellable_is_cancelled(m_transactionCancellation->value))
            m_transactionCode = "CANCELLED";
        m_transactionCancellation.reset();
        if (m_action == "check-update" && m_transactionCode.isEmpty()) {
            auto update = result;
            update["installation"] = m_checkedInstallation;
            m_updates[m_activeId] = update;
        }
        m_verifying = true;
        refresh(); // Keep busy until the actual local installation is re-read.
    });
    m_progressTimer.setInterval(250);
    connect(&m_progressTimer, &QTimer::timeout, this, &FlatpakApps::reportProgress);
    m_refreshTimer.setInterval(5000);
    connect(&m_refreshTimer, &QTimer::timeout, this, &FlatpakApps::refresh);
    m_refreshTimer.start();
    QTimer::singleShot(0, this, &FlatpakApps::refresh);
}

FlatpakApps::~FlatpakApps()
{
    if (m_cancellation) g_cancellable_cancel(m_cancellation->value);
    if (m_transactionCancellation) {
        g_cancellable_cancel(m_transactionCancellation->value);
    }
    // Workers capture only shared cancellation state, never this object.
}

bool FlatpakApps::beginOperation(const QString& appId, const QString& action, int timeout)
{
    const auto root = qEnvironmentVariable("XDG_STATE_HOME", QDir::homePath() + "/.local/state") + "/kos-settings/app-store";
    if (!QDir::isAbsolutePath(root) || !QDir().mkpath(root)) return false;
    m_logPath = root + '/' + QUuid::createUuid().toString(QUuid::WithoutBraces) + "-flatpak.log";
    m_log.setFileName(m_logPath);
    if (!m_log.open(QIODevice::WriteOnly | QIODevice::NewOnly,
        QFileDevice::ReadOwner | QFileDevice::WriteOwner)) return false;
    m_log.write((action + " " + appId + '\n').toUtf8());
    m_activeId = appId; m_action = action; m_logAppId = appId;
    m_progress = {{"progress", -1}, {"elapsedSeconds", 0}, {"cancelling", false}, {"status", ""}};
    m_lastStatus.clear();
    m_elapsed.start();
    m_verifying = false; m_timedOut = false;
    m_transactionCancellation = std::make_shared<Cancellation>();
    m_transactionDeadline.start(timeout);
    m_progressTimer.start();
    return true;
}

void FlatpakApps::reportProgress()
{
    if (!busy()) return;
    if (m_transactionCancellation) {
        std::lock_guard lock(m_transactionCancellation->mutex);
        m_progress["progress"] = m_transactionCancellation->progress;
        m_progress["status"] = m_transactionCancellation->status;
        m_progress["cancelling"] = m_transactionCancellation->cancelling;
    }
    m_progress["elapsedSeconds"] = m_elapsed.elapsed() / 1000;
    const auto status = m_progress.value("status").toString();
    if (status != m_lastStatus && m_log.size() < 1024 * 1024) {
        m_lastStatus = status;
        m_log.write((status.left(4096) + '\n').toUtf8());
        m_log.flush();
    }
    emit changed();
}

QVariantMap FlatpakApps::state(const QString& appId) const
{
    const auto installations = m_inventory.apps.value(appId).toList();
    auto update = m_updates.value(appId).toMap();
    const bool candidate = installations.isEmpty() && update.contains("version")
        && update.value("installation").toMap().isEmpty();
    const bool installed = installations.size() == 1
        && update.value("installation").toMap() == installations.first().toMap();
    if (!m_inventory.error.isEmpty() || (!candidate && !installed)) update.clear();
    const bool known = m_inventory.error.isEmpty() && !querying();
    const bool canDiscover = known && FlatpakRelease::configured(appId)
        && (installations.isEmpty()
            || (installations.size() == 1 && installations.first().toMap().value("bundleManaged").toBool()));
    return {{"installations", installations}, {"update", update},
            {"canDiscover", canDiscover}, {"publisherConfigured", FlatpakRelease::configured(appId)},
            {"canInstall", !querying() && canDiscover && candidate && update.value("available").toBool()},
            {"known", known},
            {"error", m_inventory.error}, {"querying", querying()},
            {"diskSpace", m_logAppId == appId ? m_progress.value("diskSpace").toMap() : QVariantMap{}},
            {"progressState", m_logAppId == appId ? m_progress : QVariantMap{}},
            {"logPath", m_logAppId == appId ? m_logPath : QString()},
            {"stage", m_activeId == appId ? m_action : QString()},
            {"busy", m_activeId == appId}};
}

bool FlatpakApps::uninstall(const QString& appId)
{
    if (!IndependentAppRegistry::find(appId) || busy() || querying() || !m_inventory.error.isEmpty()
        || m_inventory.apps.isEmpty()) return false;
    const auto installations = m_inventory.apps.value(appId).toList();
    if (installations.size() != 1) return false;
    const auto selected = installations.first().toMap();
    if (selected.value("scope").toString() != "user") return false;
    if (!beginOperation(appId, "uninstall", 30000)) return false;
    m_updates.remove(appId);
    const auto cancellation = m_transactionCancellation;
    m_transaction.setFuture(QtConcurrent::run([cancellation, appId, selected] {
        return FlatpakTransactionProcess::run({{"action", "uninstall"},
            {"appId", appId}, {"selected", selected}},
            [cancellation] { return bool(g_cancellable_is_cancelled(cancellation->value)); },
            [cancellation](const QString& status, int progress) {
                std::lock_guard lock(cancellation->mutex); cancellation->status = status; cancellation->progress = progress;
            });
    }));
    emit changed();
    return true;
}

// An explicit Install/Update request may prepare the pinned component source
// automatically if a missing dependency needs it. Inventory and update checks
// never add sources. Existing sources are not overwritten; no app is deployed.
bool FlatpakApps::setupRuntimeSource(const QString& appId)
{
    if (!IndependentAppRegistry::find(appId) || busy() || querying()) return false;
    if (!beginOperation(appId, "setup-runtime-source", 30000)) return false;
    const auto cancellation = m_transactionCancellation;
    m_transaction.setFuture(QtConcurrent::run([cancellation]() -> QVariantMap {
        QDir().mkpath(AppCatalog::stateDirectory());
        QLockFile mutationLock(AppCatalog::stateDirectory() + "/flatpak-mutation.lock");
        if (!mutationLock.tryLock(0)) return {{"code", "BUSY"}};
        GError* error = nullptr;
        auto* installation = flatpak_installation_new_user(cancellation->value, &error);
        if (!installation) {
            g_clear_error(&error);
            return {{"code", "RUNTIME_SETUP_FAILED"}};
        }
        auto* remotes = flatpak_installation_list_remotes(installation, cancellation->value, &error);
        if (!remotes) {
            g_clear_error(&error); g_object_unref(installation);
            return {{"code", "RUNTIME_SETUP_FAILED"}};
        }
        bool approved = false, occupied = false;
        constexpr auto name = "kos-runtime-flathub";
        for (guint i = 0; i < remotes->len; ++i) {
            auto* remote = FLATPAK_REMOTE(g_ptr_array_index(remotes, i));
            approved |= approvedOrigin(installation, remote, cancellation->value, true);
            occupied |= QByteArray(flatpak_remote_get_name(remote)) == name;
        }
        g_ptr_array_unref(remotes);
        if (approved) { g_object_unref(installation); return {}; }
        if (occupied) {
            g_object_unref(installation);
            return {{"code", "RUNTIME_SETUP_CONFLICT"}};
        }
        auto* remote = flatpak_remote_new(name);
        flatpak_remote_set_url(remote, FlatpakTrustPolicy::remotes[0].url);
        flatpak_remote_set_title(remote, "Flathub (KOS application components)");
        flatpak_remote_set_gpg_verify(remote, TRUE);
        const auto key = QByteArray::fromBase64(FlatpakTrustPolicy::runtimePublicKey);
        auto* bytes = g_bytes_new(key.constData(), key.size());
        flatpak_remote_set_gpg_key(remote, bytes);
        g_bytes_unref(bytes);
        const bool saved = flatpak_installation_modify_remote(installation, remote, cancellation->value, &error);
        g_object_unref(remote); g_clear_error(&error);
        auto* stored = saved ? flatpak_installation_get_remote_by_name(installation, name, cancellation->value, &error) : nullptr;
        const bool verified = stored && approvedOrigin(installation, stored, cancellation->value, true);
        if (stored) g_object_unref(stored);
        g_clear_error(&error); g_object_unref(installation);
        return verified ? QVariantMap{} : QVariantMap{{"code", "RUNTIME_SETUP_FAILED"}};
    }));
    emit changed();
    return true;
}

bool FlatpakApps::checkUpdates(const QString& appId)
{
    if (!IndependentAppRegistry::find(appId) || busy() || querying() || !m_inventory.error.isEmpty()
        || m_inventory.apps.isEmpty()) return false;
    const auto installations = m_inventory.apps.value(appId).toList();
    if (installations.size() > 1) return false;
    const auto selected = installations.isEmpty() ? QVariantMap{} : installations.first().toMap();
    if (!selected.isEmpty() && !selected.value("bundleManaged").toBool()) return false;
    if (!beginOperation(appId, "check-update", 90000)) return false;
    m_checkedInstallation = selected;
    m_updates.remove(appId);
    const auto cancellation = m_transactionCancellation;
    m_transaction.setFuture(QtConcurrent::run([cancellation, appId, selected] {
        auto result = FlatpakRelease::discover(appId, QString::fromUtf8(flatpak_get_default_arch()),
            [cancellation] { return bool(g_cancellable_is_cancelled(cancellation->value)); },
            [cancellation](const QString& status, int progress) {
                std::lock_guard lock(cancellation->mutex); cancellation->status = status; cancellation->progress = progress;
            });
        if (result.contains("code")) return result;
        if (!selected.isEmpty()) {
            bool valid = false;
            const int order = FlatpakRelease::compareVersions(result.value("version").toString(), selected.value("version").toString(), &valid);
            if (!valid || order < 0 || (order == 0 && result.value("commit") != selected.value("commit")))
                return QVariantMap{{"code", "VERSION_CONFLICT"}, {"message", "The signed release would downgrade or replace an existing version; automatic deployment was refused."}};
        }
        result["available"] = selected.isEmpty() || result.value("commit") != selected.value("commit");
        return result;
    }));
    emit changed();
    return true;
}

QVariantMap FlatpakApps::makePlan(const QString& appId, bool installing, QVariantMap* failure) const
{
    if (failure) *failure = {{"code", "PLAN_UNAVAILABLE"},
        {"message", "The current release, installation or dependency state does not permit an installation plan."}};
    if (!IndependentAppRegistry::find(appId) || busy() || querying() || !m_inventory.error.isEmpty()) return {};
    const auto installations = m_inventory.apps.value(appId).toList();
    const auto discovery = state(appId).value("update").toMap();
    if (!discovery.value("available").toBool() || !discovery.value("schemaVersion").toInt()
        || discovery.value("schemaVersion").toInt() != 2) return {};
    if (installing ? !installations.isEmpty() : installations.size() != 1) return {};
    const auto selected = installing
        ? QVariantMap{{"scope", "user"}, {"arch", discovery.value("arch")}, {"branch", "stable"}}
        : installations.first().toMap();
    if (selected.value("scope").toString() != "user"
        || (!installing && !selected.value("bundleManaged").toBool())) return {};
    const auto snapshotJson = QJsonDocument::fromVariant(installations).toJson(QJsonDocument::Compact);
    const auto snapshot = QString::fromLatin1(QCryptographicHash::hash(snapshotJson, QCryptographicHash::Sha256).toHex());
    QVariantList operations;
    operations.append(QVariantMap{{"role", "application"}, {"ref", discovery.value("ref")},
        {"commit", discovery.value("commit")}, {"action", installing ? "install" : "update"},
        {"remote", ""}, {"sourceUrl", "signed-github-release"},
        {"downloadBytes", discovery.value("size")}, {"installedBytes", discovery.value("installedSize")},
        {"sizeKnown", true}, {"sizeSource", "signed-release-bundle"}});
    const auto runtimeRef = discovery.value("runtime").toMap().value("ref").toString();
    auto* user = flatpak_installation_new_user(nullptr, nullptr);
    if (!user) return {};
    const auto runtime = dependencyPlan(user, runtimeRef, nullptr, "runtime", appId, failure);
    if (runtime.isEmpty()) { g_object_unref(user); return {}; }
    operations.append(runtime);
    const auto extensions = discovery.value("requiredExtensions").toList();
    for (const auto& item : extensions) {
        const auto extension = dependencyPlan(user, item.toMap().value("ref").toString(), nullptr, "extension", appId, failure);
        if (extension.isEmpty()) { g_object_unref(user); return {}; }
        operations.append(extension);
    }
    g_object_unref(user);
    QVariantList canonical;
    for (const auto& operation : operations) canonical.append(QVariantMap(operation.toMap()));
    const auto operationJson = QJsonDocument::fromVariant(canonical).toJson(QJsonDocument::Compact);
    const auto operationDigest = QString::fromLatin1(QCryptographicHash::hash(operationJson, QCryptographicHash::Sha256).toHex());
    const auto installedSize = discovery.value("installedSize");
    return {{"operation", installing ? "install" : "update"}, {"appId", appId},
        {"catalogEntryDigest", discovery.value("catalogEntryDigest")},
        {"version", discovery.value("version")}, {"revision", discovery.value("revision")},
        {"arch", discovery.value("arch")}, {"branch", discovery.value("branch")},
        {"bundleRef", discovery.value("ref")}, {"bundleCommit", discovery.value("commit")},
        {"bundleDigest", discovery.value("sha256")}, {"metadataSha256", discovery.value("metadataSha256")},
        {"releaseSource", discovery.value("url")}, {"sourceTrust", FlatpakRelease::fingerprints(appId)},
        {"inventorySnapshot", snapshot}, {"selected", selected}, {"runtime", runtime},
        {"requiredExtensions", extensions}, {"operationSet", canonical}, {"operationSetDigest", operationDigest},
        {"downloadBytes", discovery.value("size")}, {"installedBytes", installedSize},
        {"installedSizeKnown", installedSize.isValid()}, {"sizeSource", "signed-release-and-flatpak-remote-ref"},
        {"expiresAt", QDateTime::currentDateTimeUtc().addSecs(15 * 60).toString(Qt::ISODateWithMs)},
        {"discovery", discovery}};
}

bool FlatpakApps::confirmPlan(const QString& appId, const QVariantMap& plan)
{
    if (plan.isEmpty() || plan.value("appId").toString() != appId || busy() || querying()) return false;
    const auto expiry = QDateTime::fromString(plan.value("expiresAt").toString(), Qt::ISODateWithMs);
    if (!expiry.isValid() || expiry <= QDateTime::currentDateTimeUtc()) return false;
    const auto fresh = makePlan(appId, plan.value("operation").toString() == "install");
    if (fresh.isEmpty() || fresh.value("catalogEntryDigest") != plan.value("catalogEntryDigest")
        || fresh.value("bundleDigest") != plan.value("bundleDigest")
        || fresh.value("metadataSha256") != plan.value("metadataSha256")
        || fresh.value("inventorySnapshot") != plan.value("inventorySnapshot")
        || fresh.value("operationSetDigest") != plan.value("operationSetDigest")
        || fresh.value("operationSet") != plan.value("operationSet")) return false;
    return deploy(appId, plan.value("operation").toString() == "install", plan);
}

bool FlatpakApps::update(const QString& appId)
{
    return deploy(appId, false);
}

bool FlatpakApps::install(const QString& appId)
{
    return deploy(appId, true);
}

bool FlatpakApps::deploy(const QString& appId, bool installing, const QVariantMap& authorizedPlan)
{
    if (authorizedPlan.isEmpty() || authorizedPlan.value("appId").toString() != appId
        || authorizedPlan.value("operation").toString() != (installing ? "install" : "update")) return false;
    if (!IndependentAppRegistry::find(appId) || busy() || querying() || !m_inventory.error.isEmpty()) return false;
    const auto installations = m_inventory.apps.value(appId).toList();
    const auto discovery = state(appId).value("update").toMap();
    if (!discovery.value("available").toBool()) return false;
    if (installing ? !installations.isEmpty() : installations.size() != 1) return false;
    if (!QRegularExpression("^[0-9a-f]{64}$").match(discovery.value("commit").toString()).hasMatch()) return false;
    const auto selected = installing
        ? QVariantMap{{"scope", "user"}, {"arch", discovery.value("arch")}, {"branch", "stable"}}
        : installations.first().toMap();
    if (authorizedPlan.value("bundleDigest") != discovery.value("sha256")
        || authorizedPlan.value("metadataSha256") != discovery.value("metadataSha256")
        || authorizedPlan.value("selected") != selected
        || authorizedPlan.value("bundleCommit") != discovery.value("commit")) return false;
    if (!FlatpakRelease::configured(appId) || selected.value("scope").toString() != "user"
        || (!installing && !selected.value("bundleManaged").toBool())) return false;
    if (!beginOperation(appId, installing ? "install" : "update", 60 * 60 * 1000)) return false;
    m_checkedInstallation = selected;
    m_targetCommit = discovery.value("commit").toString();
    m_updates.remove(appId);
    const auto cancellation = m_transactionCancellation;
    m_transaction.setFuture(QtConcurrent::run([cancellation, appId, selected, installing, discovery, authorizedPlan] {
        auto compatibility = FlatpakCompatibility::checkBundleCleanup();
        if (!compatibility.isEmpty()) return compatibility;
        if (g_cancellable_is_cancelled(cancellation->value)) return QVariantMap{{"code", "CANCELLED"}};
        QVariantMap result;
        const auto cache = qEnvironmentVariable("XDG_CACHE_HOME", QDir::homePath() + "/.cache") + "/kos-settings/flatpak";
        if (!QDir::isAbsolutePath(cache)) return QVariantMap{{"code", "PERMISSION_DENIED"}};
        { std::lock_guard lock(cancellation->mutex); cancellation->status = "Checking available disk space"; }
        result = checkInstallSpace(authorizedPlan, cache, true);
        if (g_cancellable_is_cancelled(cancellation->value)) return QVariantMap{{"code", "CANCELLED"}};
        if (!result.isEmpty()) return result;
        if (!QDir().mkpath(cache)) return QVariantMap{{"code", "PERMISSION_DENIED"}};
        QTemporaryDir temporary(cache + "/download-XXXXXX");
        if (!temporary.isValid()) return QVariantMap{{"code", "PERMISSION_DENIED"}};
        result = FlatpakRelease::download(appId, discovery, temporary.path(),
            [cancellation] { return bool(g_cancellable_is_cancelled(cancellation->value)); },
            [cancellation](const QString& status, int progress) {
                std::lock_guard lock(cancellation->mutex); cancellation->status = status; cancellation->progress = progress;
            });
        if (result.contains("code")) return result;
        const auto path = result.value("path").toString();
        result.clear();
        return FlatpakTransactionProcess::run({{"action", installing ? "install" : "update"},
            {"appId", appId}, {"selected", selected}, {"discovery", discovery},
            {"authorizedPlan", authorizedPlan}, {"path", path}},
            [cancellation] { return bool(g_cancellable_is_cancelled(cancellation->value)); },
            [cancellation](const QString& status, int progress) {
                std::lock_guard lock(cancellation->mutex); cancellation->status = status; cancellation->progress = progress;
            });
    }));
    emit changed();
    return true;
}

void FlatpakApps::cancel()
{
    if (m_transactionCancellation) {
        { std::lock_guard lock(m_transactionCancellation->mutex); m_transactionCancellation->cancelling = true; }
        g_cancellable_cancel(m_transactionCancellation->value);
        reportProgress();
    }
}

void FlatpakApps::refresh()
{
    if (m_watcher.isRunning() || (busy() && !m_verifying)) return;
    m_cancellation = std::make_shared<Cancellation>();
    const auto cancellation = m_cancellation;
    m_deadline.start();
    m_watcher.setFuture(QtConcurrent::run([cancellation] {
        Inventory result;
        QStringList ids;
        for (const auto& app : IndependentAppRegistry::apps()) {
            ids.append(app.appId);
        }
        for (const auto& id : ids) result.apps[id] = QVariantList{};
        GError* error = nullptr;
        auto* user = flatpak_installation_new_user(cancellation->value, &error);
        if (!user) {
            result.error = error ? QString::fromUtf8(error->message) : QStringLiteral("Cannot open user Flatpak installation");
            g_clear_error(&error);
            return result;
        }
        auto* installations = flatpak_get_system_installations(cancellation->value, &error);
        if (!installations) {
            result.error = error ? QString::fromUtf8(error->message) : QStringLiteral("Cannot enumerate system Flatpak installations");
            g_clear_error(&error);
            g_object_unref(user);
            return result;
        }
        g_ptr_array_add(installations, user);
        for (guint i = 0; i < installations->len; ++i) {
            auto* installation = static_cast<FlatpakInstallation*>(g_ptr_array_index(installations, i));
            auto* refs = flatpak_installation_list_installed_refs_by_kind(installation,
                FLATPAK_REF_KIND_APP, cancellation->value, &error);
            if (!refs) {
                result.error = error ? QString::fromUtf8(error->message) : QStringLiteral("Cannot enumerate installed Flatpak applications");
                g_clear_error(&error);
                break;
            }
            const bool isUser = flatpak_installation_get_is_user(installation);
            const auto installationId = QString::fromUtf8(flatpak_installation_get_id(installation));
            auto* installationRoot = flatpak_installation_get_path(installation);
            auto* rawInstallationPath = g_file_get_path(installationRoot);
            const auto installationPath = QFileInfo(QString::fromUtf8(rawInstallationPath)).canonicalFilePath();
            g_free(rawInstallationPath); g_object_unref(installationRoot);
            if (installationPath.isEmpty()) { result.error = "Flatpak installation has no local path"; g_ptr_array_unref(refs); break; }
            QVariantMap origins;
            GError* remoteError = nullptr;
            auto* remotes = flatpak_installation_list_remotes(installation, cancellation->value, &remoteError);
            if (remotes) {
                for (guint j = 0; j < remotes->len; ++j) {
                    auto* remote = static_cast<FlatpakRemote*>(g_ptr_array_index(remotes, j));
                    auto* url = flatpak_remote_get_url(remote);
                    origins[QString::fromUtf8(flatpak_remote_get_name(remote))] = QVariantMap{
                        {"known", true}, {"url", QString::fromUtf8(url)},
                        {"gpgVerify", bool(flatpak_remote_get_gpg_verify(remote))},
                        {"disabled", bool(flatpak_remote_get_disabled(remote))},
                        {"approved", approvedOrigin(installation, remote, cancellation->value)}};
                    g_free(url);
                }
                g_ptr_array_unref(remotes);
            }
            const auto remoteMessage = remoteError ? QString::fromUtf8(remoteError->message) : QString();
            g_clear_error(&remoteError);
            for (guint j = 0; j < refs->len; ++j) {
                auto* installed = static_cast<FlatpakInstalledRef*>(g_ptr_array_index(refs, j));
                auto* ref = FLATPAK_REF(installed);
                const auto id = QString::fromUtf8(flatpak_ref_get_name(ref));
                if (!ids.contains(id)) continue;
                auto entries = result.apps.value(id).toList();
                const auto origin = QString::fromUtf8(flatpak_installed_ref_get_origin(installed));
                auto source = origins.value(origin).toMap();
                source["known"] = origins.contains(origin);
                source["error"] = remoteMessage;
                // Missing policy or key inspection failure remains unapproved.
                if (!source.contains("approved")) source["approved"] = false;
                entries.append(QVariantMap{{"scope", isUser ? "user" : "system"},
                    {"installationId", installationId}, {"installation", installationPath},
                    {"installationPath", installationPath}, {"id", id},
                    {"deployDirectory", QFileInfo(QString::fromUtf8(flatpak_installed_ref_get_deploy_dir(installed))).canonicalFilePath()},
                    {"current", bool(flatpak_installed_ref_get_is_current(installed))},
                    {"branch", QString::fromUtf8(flatpak_ref_get_branch(ref))},
                    {"arch", QString::fromUtf8(flatpak_ref_get_arch(ref))},
                    {"commit", QString::fromUtf8(flatpak_ref_get_commit(ref))},
                    {"version", QString::fromUtf8(flatpak_installed_ref_get_appdata_version(installed))},
                    {"origin", origin}, {"source", source},
                    {"bundleManaged", isUser && approvedBundleInstallation(installation, installed, cancellation->value)}});
                if (isUser && AppCatalog::receipt(id).isEmpty()) {
                    const auto entry = AppCatalog::find(id);
                    // Remember only the listing identity for pre-existing installs.
                    // No SHA-256 proof is invented: unsigned external installs are
                    // still ineligible for updates, but remain visible if delisted.
                    if (entry.value("active").toBool())
                        AppCatalog::recordInstallation(id, {{"entry", entry}, {"sourceId", entry.value("sourceId")},
                            {"repository", entry.value("repository")}, {"observed", true},
                            {"commit", QString::fromUtf8(flatpak_ref_get_commit(ref))},
                            {"arch", QString::fromUtf8(flatpak_ref_get_arch(ref))}, {"origin", origin}});
                }
                result.apps[id] = entries;
            }
            g_ptr_array_unref(refs);
        }
        g_ptr_array_unref(installations);
        return result;
    }));
}
