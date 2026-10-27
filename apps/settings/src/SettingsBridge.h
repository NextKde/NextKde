#pragma once

#include "SettingsProbeTasks.h"
#include "ShellIpcClient.h"
#include "WallpaperLibrary.h"

#include <QJsonObject>
#include <QObject>
#include <QVariantMap>
#include <functional>

// Stable QML facade. Feature implementations live in SettingsBridge*.cpp;
// IPC and local image resources are owned by the concrete modules below.
class SettingsBridge final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(bool developmentSession READ isDevelopmentSession NOTIFY sessionChanged)
    Q_PROPERTY(QString sessionShellDir READ sessionShellDir NOTIFY sessionChanged)
    Q_PROPERTY(bool sourceTreeEntry READ sourceTreeEntry NOTIFY entryChanged)
    Q_PROPERTY(bool developmentBannerDismissed READ isDevelopmentBannerDismissed WRITE
            setDevelopmentBannerDismissed NOTIFY bannerDismissedChanged)

public:
    Q_INVOKABLE void launchSystemSettings();
    explicit SettingsBridge(QObject* parent = nullptr);
    ~SettingsBridge() override;
    QString lastError() const;
    bool isDevelopmentSession() const;
    QString sessionShellDir() const;
    bool sourceTreeEntry() const;
    void setSourceTreeEntry(bool value);
    bool isDevelopmentBannerDismissed() const;
    void setDevelopmentBannerDismissed(bool dismissed);
    Q_INVOKABLE void dockSnapshot();
    Q_INVOKABLE void wallpaperSnapshot();
    Q_INVOKABLE QStringList wallpaperCatalog() const;
    Q_INVOKABLE QString wallpaperThumbnail(
        const QString& urlOrPath, int width, int height, int radius, bool generate = true);
    Q_INVOKABLE QStringList galleryImages() const;
    Q_INVOKABLE QString importGalleryImage(const QString& urlOrPath);
    Q_INVOKABLE int importGalleryFolder(const QString& urlOrPath);
    Q_INVOKABLE bool deleteGalleryImage(const QString& urlOrPath);
    Q_INVOKABLE void revealWallpaperImage(const QString& urlOrPath);
    Q_INVOKABLE void chooseWallpaperImage(const QString& urlOrPath);
    Q_INVOKABLE void previewWallpaperImage(const QString& urlOrPath, const QStringList& images);
    Q_INVOKABLE QString wallpaperColorImage(const QString& start, const QString& end, int angle);
    Q_INVOKABLE void chooseWallpaperColor(const QString& hex);
    Q_INVOKABLE void chooseWallpaperGradient(const QString& start, const QString& end, int angle);
    Q_INVOKABLE QString wallpaperCustomColors();
    Q_INVOKABLE void saveWallpaperCustomColors(const QString& json);
    Q_INVOKABLE void pickWallpaperColor();
    Q_INVOKABLE void previewWallpaperSession(const QString& path, const QVariantMap& session);
    Q_INVOKABLE void updateWallpaperPreviewThumbnails(const QVariantMap& thumbnails);
    Q_INVOKABLE void updateWallpaperTransitionOptions(const QVariantMap& options);
    Q_INVOKABLE void updateWallpaperFitMode(const QString& mode);
    Q_INVOKABLE void updateWallpaperTakeoverEnabled(bool enabled);
    Q_INVOKABLE void updateWallpaperTransition(const QString& style);
    Q_INVOKABLE void updateWallpaperSlideshow(
        bool enabled, int minutes, const QStringList& images, const QString& folder);
    Q_INVOKABLE void updateWallpaperSpatialEnabled(bool enabled);
    Q_INVOKABLE QVariantList themePackCatalog() const;
    Q_INVOKABLE void chooseWallpaperTheme(const QString& id);
    Q_INVOKABLE void updateWallpaperThemeEconomical(bool enabled);
    Q_INVOKABLE void updateWallpaperThemeMotion(bool animated, double speed, int count);
    Q_INVOKABLE void prepareWallpaperSpatial();
    Q_INVOKABLE void initializeSpatialService();
    Q_INVOKABLE void disableSpatialService();
    Q_INVOKABLE void cancelWallpaperSpatial();
    Q_INVOKABLE void inspectSpatialService();
    Q_INVOKABLE void clearSpatialCache(const QString& kind);
    Q_INVOKABLE void inspectWallpaperModels();
    Q_INVOKABLE void updateDockLayout(double height);
    Q_INVOKABLE void updateDockPosition(const QString& position);
    Q_INVOKABLE void updateDockBuiltinVisibility(const QString& id, bool visible);
    Q_INVOKABLE void notificationSnapshot();
    Q_INVOKABLE void setNotificationPreference(const QString& key, bool value);
    Q_INVOKABLE void setNotificationBlocked(const QString& key, bool blocked);
    Q_INVOKABLE void updateDockNotificationBadgeVisibility(bool visible);
    Q_INVOKABLE void updateDockRevealIndicatorVisibility(bool visible);
    Q_INVOKABLE void updateDockContentStyle(const QString& style);
    Q_INVOKABLE void updateDockStyle(const QString& style);
    Q_INVOKABLE void updateDockHoverScale(double scale);
    Q_INVOKABLE void updateDockIconMode(const QString& mode);
    Q_INVOKABLE void updateDockIconOpacity(double opacity);
    Q_INVOKABLE void updateDockIconTintColor(const QString& color);
    Q_INVOKABLE void updateDockVisibilityMode(const QString& mode);
    Q_INVOKABLE void updateDockWindowGrouping(const QString& mode);
    Q_INVOKABLE void appearanceSnapshot();
    Q_INVOKABLE void updateBlurStrength(double strength);
    Q_INVOKABLE void updateLiquidStrength(double strength);
    Q_INVOKABLE void updateGlobalBlurStrength(double strength);
    Q_INVOKABLE void updateGlobalLiquidStrength(double strength);
    Q_INVOKABLE void updateGlassStyle(const QString& style);
    Q_INVOKABLE void updateWidgetStyle(const QString& style);
    Q_INVOKABLE void updateGlassPresetParameter(const QString& name, double value);
    Q_INVOKABLE void resetGlassPreset(const QString& style);
    Q_INVOKABLE void fgSchedRunningApps();
    Q_INVOKABLE void fgSchedSnapshot();
    Q_INVOKABLE void fgSchedSetFreeze(bool on);
    Q_INVOKABLE void fgSchedSetReclaim(const QString& mode);
    Q_INVOKABLE void stageConfigSnapshot();
    Q_INVOKABLE void stageConfigSet(const QString& key, const QString& value);
    Q_INVOKABLE void stageSidebarSet(bool on);
    Q_INVOKABLE void fgSchedMemStatus();
    Q_INVOKABLE void fgSchedAddFull(const QString& klass);
    Q_INVOKABLE void fgSchedRemoveFull(const QString& klass);
    Q_INVOKABLE void glassDebugSnapshot();
    Q_INVOKABLE void updateGlassDebugValue(const QString& key, const QVariant& value);
    Q_INVOKABLE void updateGlobalIconMode(const QString& mode);
    Q_INVOKABLE void updateGlobalIconOpacity(double opacity);
    Q_INVOKABLE void updateGlobalIconTintColor(const QString& color);
    Q_INVOKABLE void updateShellStyle(const QString& style);
    Q_INVOKABLE void updateMaterialColorScheme(const QString& scheme);
    Q_INVOKABLE void updateBarIntegratedWithDock(bool enabled);
    Q_INVOKABLE void updateGlassFollowsAppearanceMode(bool enabled);
    Q_INVOKABLE void updateSpatialWallpaperEnabled(bool enabled);
    Q_INVOKABLE void updateBarVisibilityMode(const QString& mode);
    Q_INVOKABLE void updateBarLayoutMode(const QString& mode);
    Q_INVOKABLE void updateBarMacStyle(bool enabled);
    Q_INVOKABLE void updateBarMacTint(double tint);
    Q_INVOKABLE void updateDockWindowAnimationStyle(const QString& style);
    Q_INVOKABLE void resetAppearanceStrengths();
    Q_INVOKABLE void launcherSnapshot();
    Q_INVOKABLE void shortcutsSnapshot();
    Q_INVOKABLE void updateShortcut(const QString& id, const QString& combo);
    Q_INVOKABLE void resetShortcut(const QString& id);
    Q_INVOKABLE void updateLauncherDisplayMode(const QString& mode);
    Q_INVOKABLE void updateLauncherProfileIconSize(const QString& mode, const QString& size);
    Q_INVOKABLE void updateLauncherProfileDensity(const QString& mode, const QString& density);
    Q_INVOKABLE void updateLauncherProfileFontWeight(const QString& mode, const QString& weight);
    Q_INVOKABLE void resetLauncherLayoutProfile(const QString& mode);
    Q_INVOKABLE void applySystemAppearance(bool dark);
    Q_INVOKABLE void integrationSnapshot();
    Q_INVOKABLE void i18nSnapshot();
    Q_INVOKABLE void updateLanguage(const QString& language);

signals:
    void wallpaperColorPicked(const QString& color);
    void wallpaperColorPickFailed(const QString& message);
    void lastErrorChanged();
    void sessionChanged();
    void entryChanged();
    void bannerDismissedChanged();
    void notificationSnapshotChanged(const QVariantMap& snapshot);
    void dockSnapshotChanged(const QVariantMap& snapshot);
    void dockBuiltinVisibilityChanged(const QVariantMap& snapshot);
    void wallpaperSnapshotChanged(const QVariantMap& snapshot);
    void wallpaperModelsChecked(bool depthReady, bool foregroundReady);
    void dockNotificationBadgeVisibilityChanged(const QVariantMap& snapshot);
    void dockRevealIndicatorVisibilityChanged(const QVariantMap& snapshot);
    void appearanceSnapshotChanged(const QVariantMap& snapshot);
    void launcherSnapshotChanged(const QVariantMap& snapshot);
    void shortcutsSnapshotChanged(const QVariantMap& snapshot);
    void glassDebugSnapshotChanged(const QVariantList& controls, const QString& presetStyle);
    void integrationSnapshotChanged(const QVariantMap& snapshot);
    void systemAppearanceApplied(bool accepted);
    // 后台缩略图生成完毕;页面收到后重新求值瓦片缩略图绑定,下次直接命中缓存。
    void wallpaperThumbnailChanged();
    void galleryImportProgress(int imported);
    void galleryImportFinished(int imported);
    void fgSchedSnapshotChanged(const QVariantMap& snapshot);
    void fgSchedRunningAppsChanged(const QVariantList& apps);
    void fgSchedMemStatusChanged(const QVariantMap& status);
    void stageConfigChanged(const QVariantMap& snapshot);
    void i18nSnapshotChanged(const QVariantMap& snapshot);

private:
    enum class RequestKind {
        Dock,
        Notifications,
        DockBuiltinVisibility,
        Wallpaper,
        DockNotificationBadgeVisibility,
        DockRevealIndicatorVisibility,
        Appearance,
        Launcher,
        Shortcuts,
        Integration,
        GlassDebug,
        ApplySystemAppearance,
        FgSchedApps,
        StageConfig,
        StageSidebar,
        I18nSnapshot,
        OpenApp,
    };

    struct DockRequest {
        QStringList arguments;
        QString fallbackError;
        RequestKind kind;
    };

    static QString fgSchedConfigPath();
    static QString fgSchedKnownAppsPath();
    static bool writeFgSchedConfig(const std::function<void(QJsonObject&)>& mutate);
    void callStage(const QStringList& arguments);
    QVariantMap stageConfigFromReply(const QString& payload);
    QVariantMap notificationSnapshotFromReply(const QString& payload);
    QVariantMap snapshotFromReply(const QString& payload);
    QVariantMap wallpaperSnapshotFromReply(const QString& payload);
    QVariantMap i18nSnapshotFromReply(const QString& payload);
    QVariantMap appearanceSnapshotFromReply(const QString& payload);
    QVariantMap launcherSnapshotFromReply(const QString& payload);
    QVariantMap integrationSnapshotFromReply(const QString& payload);
    QVariantMap shortcutsSnapshotFromReply(const QString& payload);
    QVariantList glassDebugSpecs() const;
    QString glassPresetStyle() const;
    QVariantMap glassDebugSpec(const QString& key) const;
    void startIntegrationProbe(const QVariantMap& replyMap);
    void callDock(const QStringList& arguments);
    void pumpDockRequests();
    QVariantMap latestDockState(const QString& payload);
    void finishDockRequest();
    void callWallpaper(const QStringList& arguments);
    void pumpWallpaperRequests();
    void callAppearance(const QStringList& arguments);
    void callLauncher(const QStringList& arguments);
    void callShortcuts(const QStringList& arguments);
    void callI18n(const QStringList& arguments);
    void setSessionShell(const QString& shellPath);
    void callShell(const QString& target, const QStringList& arguments,
        const QString& fallbackError, RequestKind kind);
    void handleReply(RequestKind kind, const QString& payload);
    void failKind(RequestKind kind);
    void setLastError(const QString& error);

    void sendShellRequest(const QString& target, const QStringList& arguments,
        const QString& fallbackError, RequestKind kind);

    ShellIpcClient m_shellClient;
    WallpaperLibrary m_wallpaperLibrary;
    bool m_dockBusy = false;
    QList<DockRequest> m_dockQueue;
    bool m_wallpaperBusy = false;
    QList<QStringList> m_wallpaperQueue;
    QString m_lastError;
    // The Shell directory this window is talking to: seeded from KOS_SHELL_DIR,
    // replaced by whichever candidate answers. Empty until one of the two has
    // happened, which is also the state that reads as "not a development
    // session" rather than guessing.
    QString m_sessionShellDir;
    // Set once, from the entry point main() chose, before the engine loads it.
    bool m_sourceTreeEntry = false;
    // Set from the banner's close control. Survives a QML reload on purpose --
    // see isDevelopmentBannerDismissed().
    bool m_bannerDismissed = false;
    // Last appearance snapshot the shell sent. Kept for glassDebugSpecs(), which
    // reads the active preset out of it, and refreshed on every glass debug
    // snapshot so the style it names is the one being edited right now.
    QJsonObject m_appearanceSnapshot;
    // The integration probe is a worker thread: while one is running the 5s
    // page poll must not pile up another.
    bool m_integrationPending = false;
    bool m_modelInspectionPending = false;

    // Last-good stage config snapshot. Void IPCs routed through this request
    // kind (stage-sidebar enable/disable) and failed set() replies produce no
    // payload — echoing them back would blank the page's sliders down to
    // schema defaults while the shell-side state is untouched.
    QVariantMap m_lastStageConfig;
    // Declared last so probes stop before any state captured by their UI
    // completions is destroyed. Workers themselves never capture the bridge.
    SettingsProbeTasks m_probeTasks;
};
