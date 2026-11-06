#include "FlatpakCompatibility.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QTemporaryDir>
#include <cstdio>
#include <sys/resource.h>

#pragma push_macro("signals")
#undef signals
#include <flatpak.h>
#pragma pop_macro("signals")

namespace FlatpakCompatibility {
int probeBundleCleanup()
{
    // Old libflatpak frees explicit bundle GBytes with g_object_unref(). Probe
    // without running a transaction: even rejected installs hit this cleanup.
    const rlimit noCore{0, 0};
    setrlimit(RLIMIT_CORE, &noCore);
    QTemporaryDir temporary;
    if (!temporary.isValid()) return 2;
    auto* root = g_file_new_for_path(temporary.path().toUtf8().constData());
    GError* error = nullptr;
    auto* installation = flatpak_installation_new_for_path(root, TRUE, nullptr, &error);
    auto* transaction = installation
        ? flatpak_transaction_new_for_installation(installation, nullptr, &error) : nullptr;
    auto* file = g_file_new_for_path(temporary.filePath("not-an-install.flatpak").toUtf8().constData());
    auto* key = g_bytes_new_static("cleanup-probe", 13);
    const bool added = transaction && flatpak_transaction_add_install_bundle(transaction, file, key, &error);
    g_bytes_unref(key);
    if (transaction) g_object_unref(transaction);
    g_object_unref(file);
    if (installation) g_object_unref(installation);
    g_object_unref(root);
    if (error) { g_error_free(error); return 2; }
    if (!added) return 2;
    std::puts("KOS_FLATPAK_BUNDLE_CLEANUP_OK");
    return 0;
}

QVariantMap checkBundleCleanup()
{
    // The helper must be the companion binary, not an arbitrary PATH entry.
    QTemporaryDir temporary;
    if (!temporary.isValid())
        return {{"code", "PERMISSION_DENIED"}, {"message", "Cannot create an isolated Flatpak compatibility probe."}};
    auto environment = QProcessEnvironment::systemEnvironment();
    for (const auto* name : {"HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME",
                            "XDG_STATE_HOME", "TMPDIR", "FLATPAK_USER_DIR", "FLATPAK_SYSTEM_DIR", "FLATPAK_CONFIG_DIR"}) {
        const auto path = temporary.filePath(QString::fromLatin1(name));
        if (!QDir().mkpath(path)) return {{"code", "PERMISSION_DENIED"}};
        environment.insert(QString::fromLatin1(name), path);
    }
    QProcess process;
    process.setProcessEnvironment(environment);
    const auto worker = QCoreApplication::applicationDirPath() + "/kos-flatpak-worker";
    if (!QFileInfo(worker).isExecutable())
        return {{"code", "FLATPAK_INCOMPATIBLE"},
            {"message", "The optional Flatpak worker is unavailable; no bundle was downloaded or deployed."}};
    process.setProgram(worker);
    process.setArguments({"--probe-flatpak-bundle-cleanup"});
    process.start();
    const bool started = process.waitForStarted(1000);
    const bool finished = started && process.waitForFinished(5000);
    if (!finished && process.state() != QProcess::NotRunning) {
        process.kill();
        process.waitForFinished(1000);
    }
    if (finished && process.exitStatus() == QProcess::NormalExit && process.exitCode() == 0
        && process.readAllStandardOutput().trimmed() == "KOS_FLATPAK_BUNDLE_CLEANUP_OK") return {};
    return {{"code", "FLATPAK_INCOMPATIBLE"},
        {"message", "The installed Flatpak library cannot safely release a signed-bundle transaction, or its isolated compatibility check could not complete. Update Flatpak/libflatpak to a package containing upstream fix 95b70b71e366c78d16abadaa7e33f6d6bcdc01f4. No bundle was downloaded or deployed."}};
}
}
