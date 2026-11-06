#include "FlatpakApps.h"
#include "FlatpakCompatibility.h"
#include "FlatpakTrustPolicy.h"
#include "FlatpakRelease.h"
#include <QTemporaryDir>
#include "IndependentAppRegistry.h"

#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>
#include <QSettings>
#include <QRegularExpression>
#include <QDateTime>
#include <QUuid>
#include <mutex>
#include <sys/stat.h>
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
volatile std::sig_atomic_t helperInterrupted = 0;
void interruptHelper(int) { helperInterrupted = 1; }

bool writersRunning(const QString& appId)
{
    const auto* app = IndependentAppRegistry::find(appId);
    if (!app) return true;
    QStringList names{QString::fromLatin1(app->executable)};
    if (QString::fromLatin1(app->key) == "calendar") names << "kos-pim-service" << "kos-todo";
    if (QString::fromLatin1(app->key) == "weather") names << "kos-weather-backend";
    const auto processes = QDir("/proc").entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const auto& pid : processes) {
        bool valid;
        pid.toLongLong(&valid);
        if (!valid) continue;
        struct stat info{};
        const auto root = ("/proc/" + pid).toUtf8();
        if (::stat(root.constData(), &info) < 0 || info.st_uid != ::getuid()) continue;
        QFile command(QString::fromUtf8(root) + "/cmdline");
        if (!command.open(QIODevice::ReadOnly)) return true;
        const auto words = command.read(65536).split('\0');
        if (!words.isEmpty() && names.contains(QFileInfo(QString::fromUtf8(words.first())).fileName())) return true;
        QFile comm(QString::fromUtf8(root) + "/comm");
        if (comm.open(QIODevice::ReadOnly)) {
            const auto name = QString::fromUtf8(comm.read(256)).trimmed();
            for (const auto& expected : names) if (name == expected.left(15)) return true;
        }
    }
    return false;
}

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

bool hasLegacyInstallation(const QString& appId)
{
    const auto* app = IndependentAppRegistry::find(appId);
    if (!app) return true;
    if (!QStandardPaths::findExecutable(QString::fromLatin1(app->executable)).isEmpty()) return true;
    const auto data = QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation);
    for (const auto& root : data) {
        const auto desktop = root + "/applications/" + appId + ".desktop";
        if (QFileInfo::exists(desktop) || QFileInfo(desktop).isSymLink()) {
            QSettings metadata(desktop, QSettings::IniFormat);
            if (metadata.value("Desktop Entry/X-Flatpak").toString() != appId) return true;
        }
        if (QFileInfo::exists(root + "/applications/" + app->desktop)
            || QFileInfo(root + "/applications/" + app->desktop).isSymLink()
            || QFileInfo::exists(root + "/nextkde-apps/" + app->key + "/ownership.json")
            || QFileInfo(root + "/nextkde-apps/" + app->key + "/ownership.json").isSymLink()
            || QFileInfo::exists(root + "/nextkde-apps/" + app->key + "/current")
            || QFileInfo(root + "/nextkde-apps/" + app->key + "/current").isSymLink()) return true;
    }
    return false;
}

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
    if (keys.isEmpty() || QString::fromUtf8(flatpak_ref_get_branch(FLATPAK_REF(installed))) != "stable"
        || QString::fromUtf8(flatpak_ref_get_arch(FLATPAK_REF(installed))) != QString::fromUtf8(flatpak_get_default_arch())) return false;
    auto* remote = flatpak_installation_get_remote_by_name(installation, flatpak_installed_ref_get_origin(installed), cancellation, nullptr);
    if (!remote) return false;
    auto* url = flatpak_remote_get_url(remote);
    const bool local = (!url || !*url) && flatpak_remote_get_gpg_verify(remote);
    g_free(url); g_object_unref(remote);
    if (!local) return false;
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
    bool installing;
    QString refusal;

    bool localUnchanged()
    {
        GError* error = nullptr;
        auto* installed = flatpak_installation_get_installed_ref(installation, FLATPAK_REF_KIND_APP,
            appId.toUtf8().constData(), selected.value("arch").toString().toUtf8().constData(),
            selected.value("branch").toString().toUtf8().constData(), cancellation, &error);
        bool valid = false;
        if (installing) valid = !installed && g_error_matches(error, FLATPAK_ERROR, FLATPAK_ERROR_NOT_INSTALLED)
            && !hasLegacyInstallation(appId);
        else valid = installed && !error
            && QString::fromUtf8(flatpak_ref_get_commit(FLATPAK_REF(installed))) == selected.value("commit").toString()
            && QString::fromUtf8(flatpak_installed_ref_get_origin(installed)) == origin
            && approvedBundleInstallation(installation, installed, cancellation);
        if (installed) g_object_unref(installed);
        g_clear_error(&error);
        // Refuse retired identities, another branch/architecture or a concurrent system installation.
        const auto* app = IndependentAppRegistry::find(appId);
        const auto retiredId = app ? QString::fromLatin1(app->retiredId) : QString();
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
                if (!retiredId.isEmpty() && id == retiredId) { valid = false; break; }
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
        if (!localUnchanged() || !FlatpakRelease::configured(appId)) {
            refusal = "The installation or publisher trust changed. Refresh before retrying.";
            return false;
        }
        auto* operations = flatpak_transaction_get_operations(transaction);
        bool valid = true, targetSeen = false;
        QStringList runtimes;
        QString requiredRuntime;
        for (auto* node = operations; node; node = node->next) {
            auto* operation = static_cast<FlatpakTransactionOperation*>(node->data);
            const auto name = QString::fromUtf8(flatpak_transaction_operation_get_ref(operation));
            const auto remote = QString::fromUtf8(flatpak_transaction_operation_get_remote(operation));
            const auto type = flatpak_transaction_operation_get_operation_type(operation);
            if (name == ref) {
                targetSeen = true;
                auto* source = flatpak_installation_get_remote_by_name(installation, remote.toUtf8().constData(), cancellation, nullptr);
                auto* url = source ? flatpak_remote_get_url(source) : nullptr;
                valid &= type == FLATPAK_TRANSACTION_OPERATION_INSTALL_BUNDLE && source
                    && (!url || !*url) && flatpak_remote_get_gpg_verify(source)
                    && (installing || remote == origin)
                    && QString::fromUtf8(flatpak_transaction_operation_get_commit(operation)) == commit;
                g_free(url);
                if (source) g_object_unref(source);
                auto* metadata = flatpak_transaction_operation_get_metadata(operation);
                auto* runtime = metadata ? g_key_file_get_string(metadata, "Application", "runtime", nullptr) : nullptr;
                requiredRuntime = QString::fromUtf8(runtime);
                g_free(runtime);
                if (requiredRuntime.isEmpty()) valid = false;
            } else if (name.startsWith("runtime/")) {
                valid &= (type == FLATPAK_TRANSACTION_OPERATION_INSTALL || type == FLATPAK_TRANSACTION_OPERATION_UPDATE)
                    && approved(remote, true);
                runtimes.append(name.mid(8));
            } else valid = false;
            if (!valid) break;
        }
        // A reused runtime is not in the transaction plan: verify its installed origin too.
        if (valid && targetSeen && !runtimes.contains(requiredRuntime)) {
            const auto parts = requiredRuntime.split('/');
            valid = parts.size() == 3;
            if (valid) {
                auto* runtime = flatpak_installation_get_installed_ref(installation, FLATPAK_REF_KIND_RUNTIME,
                    parts[0].toUtf8().constData(), parts[1].toUtf8().constData(), parts[2].toUtf8().constData(), cancellation, nullptr);
                valid = runtime && approved(QString::fromUtf8(flatpak_installed_ref_get_origin(runtime)), true);
                if (runtime) g_object_unref(runtime);
            }
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
    const auto* app = IndependentAppRegistry::find(appId);
    const bool retired = request.value("action").toString() == "remove-retired";
    if (!app || (retired && (!*app->retiredId || writersRunning(appId)))) return {{"code", "RESULT_UNKNOWN"}};
    const auto selectedId = retired ? QString::fromLatin1(app->retiredId) : appId;
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
            struct Removal { QByteArray ref; QString appId, selectedId, commit, origin; bool retired; };
            Removal removal{refName, appId, selectedId, commit, origin, retired};
            const auto ready = +[](FlatpakTransaction* transaction, gpointer data) -> gboolean {
                const auto& removal = *static_cast<Removal*>(data);
                if (removal.retired && writersRunning(removal.appId)) return FALSE;
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
                if (removal.retired) {
                    auto* systems = flatpak_get_system_installations(nullptr, nullptr);
                    if (!systems) return FALSE;
                    for (guint i = 0; i < systems->len; ++i) {
                        auto* system = FLATPAK_INSTALLATION(g_ptr_array_index(systems, i));
                        auto* systemRefs = flatpak_installation_list_installed_refs_by_kind(system, FLATPAK_REF_KIND_APP, nullptr, nullptr);
                        if (!systemRefs) { allowed = false; continue; }
                        for (guint j = 0; j < systemRefs->len; ++j)
                            if (QString::fromUtf8(flatpak_ref_get_name(FLATPAK_REF(g_ptr_array_index(systemRefs, j)))) == removal.selectedId)
                                allowed = false;
                        g_ptr_array_unref(systemRefs);
                    }
                    g_ptr_array_unref(systems);
                }
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
    const bool installing = request.value("action").toString() == "install";
    const auto path = request.value("path").toString();
    auto result = FlatpakRelease::validateDownloaded(appId, discovery, path,
        [cancellation] { return bool(g_cancellable_is_cancelled(cancellation->value)); });
    if (!result.isEmpty()) return result;
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
        selected.value("origin").toString(), target, selected, installing, {}};
    if (installation && guard.localUnchanged()) {
        transaction = flatpak_transaction_new_for_installation(installation, cancellation->value, &error);
        if (transaction) {
            Cancellation::attach(transaction, cancellation);
            flatpak_transaction_set_no_interaction(transaction, TRUE);
            flatpak_transaction_set_include_unused_uninstall_ops(transaction, FALSE);
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
            auto* keys = g_bytes_new(bytes.constData(), bytes.size());
            const bool added = !bytes.isEmpty() && flatpak_transaction_add_install_bundle(transaction, file, keys, &error);
            g_bytes_unref(keys);
            { std::lock_guard lock(cancellation->mutex); cancellation->status = "Resolving and deploying signed Flatpak bundle"; cancellation->progress = -1; }
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
    const auto* app = IndependentAppRegistry::find(request.value("appId").toString());
    if (!app || !QStringList{"install", "update", "uninstall", "remove-retired"}.contains(action)) return 2;
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
                ? entries.isEmpty() && !hasLegacyInstallation(it.key())
                : entries.size() == 1 && update.value("installation").toMap() == entries.first().toMap();
            const auto* app = IndependentAppRegistry::find(it.key());
            const bool retired = app && !m_inventory.apps.value(QString::fromLatin1(app->retiredId)).toList().isEmpty();
            if (!m_inventory.error.isEmpty() || !unchanged || retired) it = m_updates.erase(it);
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
                const auto* active = IndependentAppRegistry::find(m_activeId);
                const auto installations = result.apps.value(m_action == "remove-retired" && active
                    ? QString::fromLatin1(active->retiredId) : m_activeId).toList();
                if (m_action == "check-update" && code.isEmpty()) {
                    const bool unchanged = m_checkedInstallation.isEmpty()
                        ? installations.isEmpty() && !hasLegacyInstallation(m_activeId)
                        : installations.size() == 1 && installations.first().toMap() == m_checkedInstallation;
                    const auto* app = IndependentAppRegistry::find(m_activeId);
                    const bool retired = app && !result.apps.value(QString::fromLatin1(app->retiredId)).toList().isEmpty();
                    if (!unchanged || retired) {
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
                } else if (m_action == "uninstall" || m_action == "remove-retired") {
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
    const auto* app = IndependentAppRegistry::find(appId);
    const auto retired = app ? m_inventory.apps.value(QString::fromLatin1(app->retiredId)).toList() : QVariantList{};
    auto update = m_updates.value(appId).toMap();
    if (!retired.isEmpty()) update.clear();
    const bool candidate = installations.isEmpty() && update.contains("version")
        && update.value("installation").toMap().isEmpty() && !hasLegacyInstallation(appId);
    const bool installed = installations.size() == 1
        && update.value("installation").toMap() == installations.first().toMap();
    if (!m_inventory.error.isEmpty() || (!candidate && !installed)) update.clear();
    const bool known = m_inventory.error.isEmpty() && !m_inventory.apps.isEmpty();
    const bool canDiscover = known && retired.isEmpty() && FlatpakRelease::configured(appId)
        && (installations.isEmpty() ? !hasLegacyInstallation(appId)
            : installations.size() == 1 && installations.first().toMap().value("bundleManaged").toBool());
    return {{"installations", installations}, {"update", update},
            {"canDiscover", canDiscover}, {"publisherConfigured", FlatpakRelease::configured(appId)},
            {"canInstall", !querying() && canDiscover && candidate && update.value("available").toBool()},
            {"legacyConflict", hasLegacyInstallation(appId) || !retired.isEmpty()},
            {"retiredInstallations", retired}, {"retiredAppId", app ? app->retiredId : ""}, {"known", known},
            {"error", m_inventory.error}, {"querying", querying()},
            {"progressState", m_logAppId == appId ? m_progress : QVariantMap{}},
            {"logPath", m_logAppId == appId ? m_logPath : QString()},
            {"stage", m_activeId == appId ? m_action : QString()},
            {"busy", m_activeId == appId}};
}

bool FlatpakApps::uninstall(const QString& appId) { return remove(appId, false); }
bool FlatpakApps::removeRetired(const QString& appId) { return remove(appId, true); }

bool FlatpakApps::remove(const QString& appId, bool retired)
{
    const auto* app = IndependentAppRegistry::find(appId);
    if (!app || (retired && !*app->retiredId) || busy() || querying() || !m_inventory.error.isEmpty()
        || m_inventory.apps.isEmpty()) return false;
    const auto selectedId = retired ? QString::fromLatin1(app->retiredId) : appId;
    if (retired && writersRunning(appId)) return false;
    const auto installations = m_inventory.apps.value(selectedId).toList();
    if (installations.size() != 1) return false;
    const auto selected = installations.first().toMap();
    if (selected.value("scope").toString() != "user") return false;
    if (!beginOperation(appId, retired ? "remove-retired" : "uninstall", 30000)) return false;
    m_updates.remove(appId);
    const auto cancellation = m_transactionCancellation;
    m_transaction.setFuture(QtConcurrent::run([cancellation, appId, retired, selected] {
        return FlatpakTransactionProcess::run({{"action", retired ? "remove-retired" : "uninstall"},
            {"appId", appId}, {"selected", selected}},
            [cancellation] { return bool(g_cancellable_is_cancelled(cancellation->value)); },
            [cancellation](const QString& status, int progress) {
                std::lock_guard lock(cancellation->mutex); cancellation->status = status; cancellation->progress = progress;
            });
    }));
    emit changed();
    return true;
}

bool FlatpakApps::checkUpdates(const QString& appId)
{
    if (!IndependentAppRegistry::find(appId) || busy() || querying() || !m_inventory.error.isEmpty()
        || m_inventory.apps.isEmpty()) return false;
    const auto installations = m_inventory.apps.value(appId).toList();
    if (!state(appId).value("retiredInstallations").toList().isEmpty()) return false;
    if (installations.isEmpty() ? hasLegacyInstallation(appId) : installations.size() != 1) return false;
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

bool FlatpakApps::update(const QString& appId)
{
    return deploy(appId, false);
}

bool FlatpakApps::install(const QString& appId)
{
    return deploy(appId, true);
}

bool FlatpakApps::deploy(const QString& appId, bool installing)
{
    if (!IndependentAppRegistry::find(appId) || busy() || querying() || !m_inventory.error.isEmpty()) return false;
    const auto installations = m_inventory.apps.value(appId).toList();
    if (!state(appId).value("retiredInstallations").toList().isEmpty()) return false;
    const auto discovery = state(appId).value("update").toMap();
    if (!discovery.value("available").toBool()) return false;
    if (installing ? !installations.isEmpty() || hasLegacyInstallation(appId) : installations.size() != 1) return false;
    if (!QRegularExpression("^[0-9a-f]{64}$").match(discovery.value("commit").toString()).hasMatch()) return false;
    const auto selected = installing
        ? QVariantMap{{"scope", "user"}, {"arch", discovery.value("arch")}, {"branch", "stable"}}
        : installations.first().toMap();
    if (!FlatpakRelease::configured(appId) || selected.value("scope").toString() != "user"
        || (!installing && !selected.value("bundleManaged").toBool())) return false;
    if (!beginOperation(appId, installing ? "install" : "update", 60 * 60 * 1000)) return false;
    m_checkedInstallation = selected;
    m_targetCommit = discovery.value("commit").toString();
    m_updates.remove(appId);
    const auto cancellation = m_transactionCancellation;
    m_transaction.setFuture(QtConcurrent::run([cancellation, appId, selected, installing, discovery] {
        auto compatibility = FlatpakCompatibility::checkBundleCleanup();
        if (!compatibility.isEmpty()) return compatibility;
        if (g_cancellable_is_cancelled(cancellation->value)) return QVariantMap{{"code", "CANCELLED"}};
        QVariantMap result;
        const auto cache = qEnvironmentVariable("XDG_CACHE_HOME", QDir::homePath() + "/.cache") + "/kos-settings/flatpak";
        if (!QDir::isAbsolutePath(cache) || !QDir().mkpath(cache)) return QVariantMap{{"code", "PERMISSION_DENIED"}};
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
            {"appId", appId}, {"selected", selected}, {"discovery", discovery}, {"path", path}},
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
        for (const auto& app : IndependentAppRegistry::apps) {
            ids.append(QString::fromLatin1(app.appId));
            if (*app.retiredId) ids.append(QString::fromLatin1(app.retiredId));
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
                    {"installationId", installationId},
                    {"branch", QString::fromUtf8(flatpak_ref_get_branch(ref))},
                    {"arch", QString::fromUtf8(flatpak_ref_get_arch(ref))},
                    {"commit", QString::fromUtf8(flatpak_ref_get_commit(ref))},
                    {"version", QString::fromUtf8(flatpak_installed_ref_get_appdata_version(installed))},
                    {"origin", origin}, {"source", source},
                    {"bundleManaged", isUser && approvedBundleInstallation(installation, installed, cancellation->value)}});
                result.apps[id] = entries;
            }
            g_ptr_array_unref(refs);
        }
        g_ptr_array_unref(installations);
        return result;
    }));
}
