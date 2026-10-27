#include "SettingsBridge.h"

#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QThread>
#include <QTimer>

SettingsBridge::SettingsBridge(QObject* parent)
    : QObject(parent)
    , m_shellClient(this)
    , m_wallpaperLibrary(this)
    , m_probeTasks(this)
{
    // The Shell's own Settings entry goes through the platform daemon, which
    // exports KOS_SHELL_DIR for the session it belongs to. That is the one
    // launch path that can answer before the window exists, so it is taken
    // as the starting answer and corrected below if a call lands somewhere
    // else.
    const QString configured = qEnvironmentVariable("KOS_SHELL_DIR");
    if (!configured.isEmpty())
        m_sessionShellDir = configured;
    connect(
        &m_wallpaperLibrary, &WallpaperLibrary::errorOccurred, this, &SettingsBridge::setLastError);
    connect(&m_wallpaperLibrary, &WallpaperLibrary::thumbnailReady, this,
        &SettingsBridge::wallpaperThumbnailChanged);
}

SettingsBridge::~SettingsBridge() = default;

QString SettingsBridge::lastError() const { return m_lastError; }

bool SettingsBridge::isDevelopmentSession() const
{
    return !m_sessionShellDir.isEmpty()
        && !ShellIpcClient::isInstalledShellDirectory(m_sessionShellDir);
}

QString SettingsBridge::sessionShellDir() const { return m_sessionShellDir; }

bool SettingsBridge::sourceTreeEntry() const { return m_sourceTreeEntry; }

void SettingsBridge::setSourceTreeEntry(bool value)
{
    if (m_sourceTreeEntry == value)
        return;
    m_sourceTreeEntry = value;
    emit entryChanged();
}

bool SettingsBridge::isDevelopmentBannerDismissed() const { return m_bannerDismissed; }

void SettingsBridge::setDevelopmentBannerDismissed(bool dismissed)
{
    if (m_bannerDismissed == dismissed)
        return;
    m_bannerDismissed = dismissed;
    emit bannerDismissedChanged();
}

void SettingsBridge::setSessionShell(const QString& shellPath)
{
    if (m_sessionShellDir == shellPath)
        return;
    m_sessionShellDir = shellPath;
    emit sessionChanged();
}

void SettingsBridge::callShell(const QString& target, const QStringList& arguments,
    const QString& fallbackError, RequestKind kind)
{
    if (target == QStringLiteral("dock-settings")) {
        m_dockQueue.append({ arguments, fallbackError, kind });
        pumpDockRequests();
        return;
    }
    sendShellRequest(target, arguments, fallbackError, kind);
}

void SettingsBridge::handleReply(RequestKind kind, const QString& payload)
{
    switch (kind) {
    case RequestKind::Notifications:
        emit notificationSnapshotChanged(notificationSnapshotFromReply(payload));
        break;
    case RequestKind::Dock:
        emit dockSnapshotChanged(latestDockState(payload));
        finishDockRequest();
        break;
    case RequestKind::DockBuiltinVisibility:
        emit dockBuiltinVisibilityChanged(latestDockState(payload));
        finishDockRequest();
        break;
    case RequestKind::Wallpaper: {
        const QVariantMap state = wallpaperSnapshotFromReply(payload);
        m_wallpaperBusy = false;
        m_wallpaperLibrary.migrateGalleryFromLibrary(
            state.value(QStringLiteral("library")).toString());
        // Intermediate replies must not overwrite a newer selection in the UI.
        if (m_wallpaperQueue.isEmpty())
            emit wallpaperSnapshotChanged(state);
        pumpWallpaperRequests();
        break;
    }
    case RequestKind::DockNotificationBadgeVisibility:
        emit dockNotificationBadgeVisibilityChanged(latestDockState(payload));
        finishDockRequest();
        break;
    case RequestKind::DockRevealIndicatorVisibility:
        emit dockRevealIndicatorVisibilityChanged(latestDockState(payload));
        finishDockRequest();
        break;
    case RequestKind::Appearance:
        emit appearanceSnapshotChanged(appearanceSnapshotFromReply(payload));
        break;
    case RequestKind::Launcher:
        emit launcherSnapshotChanged(launcherSnapshotFromReply(payload));
        break;
    case RequestKind::Island:
        emit islandSnapshotChanged(islandSnapshotFromReply(payload));
        break;
    case RequestKind::Shortcuts:
        emit shortcutsSnapshotChanged(shortcutsSnapshotFromReply(payload));
        break;
    case RequestKind::Integration:
        startIntegrationProbe(integrationSnapshotFromReply(payload));
        break;
    case RequestKind::GlassDebug:
        appearanceSnapshotFromReply(payload);
        emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
        break;
    case RequestKind::ApplySystemAppearance: {
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        bool accepted = false;
        if (parseError.error == QJsonParseError::NoError && document.isObject())
            accepted = document.object().value(QStringLiteral("accepted")).toBool();
        if (!accepted && m_lastError.isEmpty())
            setLastError(
                QStringLiteral("The desktop environment rejected the theme switch request"));
        emit systemAppearanceApplied(accepted);
        break;
    }
    case RequestKind::FgSchedApps: {
        QVariantList apps;
        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error == QJsonParseError::NoError && document.isArray()) {
            const auto arr = document.array();
            for (const auto& v : arr) {
                const auto o = v.toObject();
                apps.append(QVariantMap {
                    { QStringLiteral("name"), o.value(QStringLiteral("name")).toString() },
                    { QStringLiteral("appId"), o.value(QStringLiteral("appId")).toString() },
                });
            }
        }
        emit fgSchedRunningAppsChanged(apps);
        break;
    }
    case RequestKind::StageConfig:
        emit stageConfigChanged(stageConfigFromReply(payload));
        break;
    case RequestKind::StageSidebar:
        // 侧栏开关是 void 动词（stage-sidebar enable/disable）：立即
        // 回读 + 延迟补读。⚠️ shell 落盘是 enqueueBashChain 异步链，
        // void 应答返回时 printf 很可能还没执行——只读一次会拿到旧
        // 值（开关延迟到下个 5s tick 才翻转＝"点了没反应"的残余），
        // 1.2s 后补读一次覆盖落盘完成时刻。此前完全没有回读时，快
        // 照停在页面加载时刻，点击发的都是"已是态"的 no-op
        fgSchedSnapshot();
        QTimer::singleShot(1200, this, [this] { fgSchedSnapshot(); });
        break;
    case RequestKind::I18nSnapshot:
        emit i18nSnapshotChanged(i18nSnapshotFromReply(payload));
        break;
    }
}

void SettingsBridge::failKind(RequestKind kind)
{
    switch (kind) {
    case RequestKind::Notifications:
        emit notificationSnapshotChanged({ });
        break;
    case RequestKind::Dock:
        emit dockSnapshotChanged({ });
        finishDockRequest();
        break;
    case RequestKind::DockBuiltinVisibility:
        emit dockBuiltinVisibilityChanged({ });
        finishDockRequest();
        break;
    case RequestKind::Wallpaper:
        m_wallpaperBusy = false;
        emit wallpaperSnapshotChanged({ });
        pumpWallpaperRequests();
        break;
    case RequestKind::DockNotificationBadgeVisibility:
        emit dockNotificationBadgeVisibilityChanged({ });
        finishDockRequest();
        break;
    case RequestKind::DockRevealIndicatorVisibility:
        emit dockRevealIndicatorVisibilityChanged({ });
        finishDockRequest();
        break;
    case RequestKind::Appearance:
        emit appearanceSnapshotChanged({ });
        break;
    case RequestKind::Launcher:
        emit launcherSnapshotChanged({ });
        break;
    case RequestKind::Island:
        emit islandSnapshotChanged({ });
        break;
    case RequestKind::Shortcuts:
        emit shortcutsSnapshotChanged({ });
        break;
    case RequestKind::Integration:
        startIntegrationProbe(integrationSnapshotFromReply({ }));
        break;
    case RequestKind::GlassDebug:
        emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
        break;
    case RequestKind::ApplySystemAppearance:
        emit systemAppearanceApplied(false);
        break;
    case RequestKind::FgSchedApps:
        emit fgSchedRunningAppsChanged({ });
        break;
    case RequestKind::StageConfig:
        // 传输失败同样回 last-good：QML 只需要信号离开 pending 态
        emit stageConfigChanged(stageConfigFromReply({ }));
        break;
    case RequestKind::StageSidebar:
        // 失败也回读：快照读的是磁盘真值（调用可能已落地），给出
        // 真实态好过停在陈旧态
        fgSchedSnapshot();
        break;
    case RequestKind::I18nSnapshot:
        emit i18nSnapshotChanged({ });
        break;
    }
}

void SettingsBridge::setLastError(const QString& error)
{
    if (m_lastError == error)
        return;
    m_lastError = error;
    emit lastErrorChanged();
}

void SettingsBridge::sendShellRequest(const QString& target, const QStringList& arguments,
    const QString& fallbackError, RequestKind kind)
{
    m_shellClient.request(
        target, arguments, fallbackError, [this, kind](const ShellIpcClient::Result& result) {
            if (!result.error.isEmpty()) {
                setLastError(result.error);
                failKind(kind);
                return;
            }
            setSessionShell(result.shellDirectory);
            handleReply(kind, result.payload);
        });
}
