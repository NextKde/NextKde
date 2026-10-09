#include "update_service.h"
#include "update_public_key.h"
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QLibrary>
#include <QProcess>
#include <atomic>
#include <winsparkle.h>

namespace listenfree {
struct UpdateService::Private {
    Configuration config;
    UpdateService *owner;
    QLibrary library;
    bool initialized = false;
    // The C API supports one updater per process. Callbacks run on WinSparkle's
    // threads; cleanup joins them before this context is released.
    static std::atomic<Private *> active;
#define API(name) decltype(&win_sparkle_##name) name = nullptr
    API(init); API(cleanup); API(set_appcast_url); API(set_app_details);
    API(set_eddsa_public_key); API(set_registry_path); API(set_lang);
    API(set_automatic_check_for_updates); API(check_update_with_ui);
    API(set_shutdown_request_callback); API(set_user_run_installer_callback);
    API(set_did_find_update_callback); API(set_did_not_find_update_callback);
    API(set_error_callback); API(set_update_dismissed_callback);
#undef API
    Private(Configuration c, UpdateService *o)
        : config(std::move(c)), owner(o), library(config.libraryPath) {}
    static void notify(void (UpdateService::*signal)()) {
        if (auto *p = active.load())
            QMetaObject::invokeMethod(p->owner, signal, Qt::QueuedConnection);
    }
    static int __cdecl install(const wchar_t *path) {
        auto *p = active.load();
        if (!p || !path) return WINSPARKLE_RETURN_ERROR;
        const auto installer = QString::fromWCharArray(path);
        if (!QFileInfo(installer).isFile()) return WINSPARKLE_RETURN_ERROR;
        const auto args = installerArguments(p->config.appDirectory, p->config.portable);
        // The callback is reached only after WinSparkle verifies the signature.
        const bool launched = p->config.launchInstaller
            ? p->config.launchInstaller(installer, args)
            : QProcess::startDetached(installer, args, p->config.appDirectory);
        return launched ? 1 : WINSPARKLE_RETURN_ERROR;
    }
    bool initialize(QString *error) {
        auto fail = [error](const QString &message) { if (error) *error = message; return false; };
        if (initialized) return true;
        if (!library.load())
            return fail(tr("更新组件无法加载，请重新安装完整版本。\n%1").arg(library.errorString()));
#define RESOLVE(name) name = reinterpret_cast<decltype(name)>(library.resolve("win_sparkle_" #name)); \
        if (!name) return fail(tr("更新组件版本不兼容，请重新安装完整版本。"))
        RESOLVE(init); RESOLVE(cleanup); RESOLVE(set_appcast_url); RESOLVE(set_app_details);
        RESOLVE(set_eddsa_public_key); RESOLVE(set_registry_path); RESOLVE(set_lang);
        RESOLVE(set_automatic_check_for_updates); RESOLVE(check_update_with_ui);
        RESOLVE(set_shutdown_request_callback); RESOLVE(set_user_run_installer_callback);
        RESOLVE(set_did_find_update_callback); RESOLVE(set_did_not_find_update_callback);
        RESOLVE(set_error_callback); RESOLVE(set_update_dismissed_callback);
#undef RESOLVE
        if (active.load() && active.load() != this)
            return fail(tr("另一个更新窗口正在运行。"));
        if (set_eddsa_public_key(config.publicKey.toUtf8().constData()) != 1)
            return fail(tr("更新签名公钥无效，已停止检查。"));
        set_app_details(L"ListenFree", L"ListenFree", config.version.toStdWString().c_str());
        set_registry_path(config.registryPath.toUtf8().constData());
        set_appcast_url(config.feedUrl.toUtf8().constData());
        set_lang("zh_CN");
        set_automatic_check_for_updates(0);
        active.store(this);
        set_user_run_installer_callback(&install);
        set_shutdown_request_callback([] { notify(&UpdateService::shutdownRequested); });
        set_did_find_update_callback([] { notify(&UpdateService::updateFound); });
        set_did_not_find_update_callback([] { notify(&UpdateService::noUpdateFound); });
        set_error_callback([] { notify(&UpdateService::updateError); });
        set_update_dismissed_callback([] { notify(&UpdateService::dismissed); });
        init();
        initialized = true;
        return true;
    }
    ~Private() {
        if (initialized) {
            cleanup();
            active.store(nullptr);
        }
    }
};
std::atomic<UpdateService::Private *> UpdateService::Private::active{nullptr};

UpdateService::Configuration UpdateService::productionConfiguration() {
    Configuration c;
    c.appDirectory = QCoreApplication::applicationDirPath();
    c.libraryPath = c.appDirectory + "/WinSparkle.dll";
    c.version = QCoreApplication::applicationVersion();
    c.feedUrl = "https://github.com/Tabris-Ayanami/ListenFree-desktop/releases/latest/download/appcast.xml";
    c.publicKey = QString::fromLatin1(kUpdatePublicKey);
    c.portable = QFileInfo::exists(c.appDirectory + "/portable.mode")
        || QCoreApplication::arguments().contains("--portable");
    c.registryPath = "Software\\ListenFree\\Updates";
    return c;
}
UpdateService::UpdateService(Configuration configuration, QObject *parent)
    : QObject(parent), d(std::make_unique<Private>(std::move(configuration), this)) {}
UpdateService::~UpdateService() = default;
bool UpdateService::loaded() const { return d->initialized; }
bool UpdateService::initialize(QString *error) { return d->initialize(error); }
bool UpdateService::check(QString *error) {
    if (!d->initialize(error)) return false;
    d->check_update_with_ui();
    return true;
}
QStringList UpdateService::installerArguments(const QString &directory, bool portable) {
    QStringList args{"/SP-", "/NORESTART", "/UPDATE=1", "/DIR=" + QDir::toNativeSeparators(directory)};
    if (portable) args << "/PORTABLE=1" << "/NOICONS";
    return args;
}
} // namespace listenfree
