#include <QGuiApplication>
#include <QDateTime>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDebug>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QStandardPaths>
#include <QSettings>
#include <QThread>
#include <QTimer>
#include <QVariantMap>

namespace {

// The 材质 group of the debug page is the editor for the shell's glass presets,
// not for raw kwinrc values. The shell re-writes every one of those keys from
// the active preset on each appearance sync (theme.sync-glass), so a direct
// kwinrc write here is reverted the moment any blur/liquid/style control moves;
// these rows therefore read and write the preset through the shell, which also
// reconfigures the effect, keeping the live feedback a raw write used to give.
//
// `toKwinrc` converts preset units into kwinrc units. Only Refraction differs:
// it lives as 0..1 in the preset and reaches kwinrc as RefractionStrength 0..20
// through round(globalLiquidStrength * Refraction * 20).
struct PresetDebugKey {
    const char *key;
    const char *parameter;
    double toKwinrc;
};

const PresetDebugKey kPresetDebugKeys[] = {
    {"RefractionStrength", "Refraction", 20.0},
    {"RefractionEdgeSize", "EdgeSize", 1.0},
    {"RefractionNormalPow", "NormalPow", 1.0},
    {"RefractionRGBFringing", "RGBFringing", 1.0},
    {"RefractionOffsetStrength", "OffsetStrength", 1.0},
    {"MaterialSoftness", "Softness", 1.0},
    {"MaterialReflectionStrength", "Reflection", 1.0},
};

const PresetDebugKey *presetDebugKey(const QString &key)
{
    for (const PresetDebugKey &candidate : kPresetDebugKeys) {
        if (key == QLatin1String(candidate.key))
            return &candidate;
    }
    return nullptr;
}

// Rows that belong to neither side of this window: the shell rewrites them from
// a design value on every appearance sync, so a Settings edit would take effect
// and then silently revert. CornerExponent is the one such key today -- the
// shell writes it from AppearanceTokens.shape.cornerExponent, which is a source
// constant, not user configuration. Those rows are reported read-only so the UI
// stops offering a control that cannot hold its value; the write path is refused
// as well, so a stale UI cannot reintroduce the double write.
bool isReadOnlyDebugKey(const QString &key)
{
    return key == QLatin1String("CornerExponent");
}

} // namespace

class SettingsBridge final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(bool developmentSession READ isDevelopmentSession NOTIFY sessionChanged)
    Q_PROPERTY(QString sessionShellDir READ sessionShellDir NOTIFY sessionChanged)
    Q_PROPERTY(bool sourceTreeEntry READ sourceTreeEntry NOTIFY entryChanged)
    Q_PROPERTY(bool developmentBannerDismissed READ isDevelopmentBannerDismissed
                   WRITE setDevelopmentBannerDismissed NOTIFY bannerDismissedChanged)

public:
    explicit SettingsBridge(QObject *parent = nullptr) : QObject(parent) {
        // The Shell's own Settings entry goes through the platform daemon, which
        // exports KOS_SHELL_DIR for the session it belongs to. That is the one
        // launch path that can answer before the window exists, so it is taken
        // as the starting answer and corrected below if a call lands somewhere
        // else.
        const QString configured = qEnvironmentVariable("KOS_SHELL_DIR");
        if (!configured.isEmpty())
            m_sessionShellDir = configured;
    }

    QString lastError() const { return m_lastError; }

    // Whether this window is driving a Shell started from a checkout
    // (`kosctl dev`, `qs -p <checkout>/shell`) rather than the installed `kos`
    // configuration. It decides which QML tree is loaded and whether the window
    // reports itself as a development session, so it is derived from the
    // session itself and never from this binary's own location.
    bool isDevelopmentSession() const {
        return !m_sessionShellDir.isEmpty() && !isInstalledShellDirectory(m_sessionShellDir);
    }

    QString sessionShellDir() const { return m_sessionShellDir; }

    // Whether the pages on screen actually came from a checkout: the fact the
    // banner has to report. Deliberately not `developmentSession`, which only
    // says which Shell answered IPC. A .desktop launch (app grid, KRunner)
    // starts with no KOS_SHELL_DIR and loads the installed copy, then the first
    // successful call discovers the checkout session and flips that one to true
    // -- keying the banner off the session would announce hot reloading on a
    // window that is reloading nothing.
    bool sourceTreeEntry() const { return m_sourceTreeEntry; }

    // Called once from main() with the entry point it picked, before the engine
    // loads it. Constant for the life of the window: the pages cannot change
    // trees mid-run.
    void setSourceTreeEntry(bool value) {
        if (m_sourceTreeEntry == value)
            return;
        m_sourceTreeEntry = value;
        emit entryChanged();
    }

    // Whether the user closed the development banner. Held here rather than in
    // the window because the window is rebuilt on every QML reload, and a reload
    // is not a new session: without this the banner would come back the moment
    // anyone edited the page they were told to edit. The flag lives for the
    // process, so reopening Settings starts from a visible banner again.
    bool isDevelopmentBannerDismissed() const { return m_bannerDismissed; }

    void setDevelopmentBannerDismissed(bool dismissed) {
        if (m_bannerDismissed == dismissed)
            return;
        m_bannerDismissed = dismissed;
        emit bannerDismissedChanged();
    }

    // Every shell call is asynchronous: the request returns at once and the
    // reply is delivered on the UI thread through the matching *Changed
    // signal. Before this, each call spawned `quickshell ipc call` and blocked
    // the GUI thread in waitForStarted/waitForFinished plus a retry sleep, so
    // one failed request froze the window for ~11s and the eagerly
    // instantiated pages froze startup entirely while the shell was down.
    Q_INVOKABLE void dockSnapshot() {
        callDock({QStringLiteral("snapshot")});
    }

    Q_INVOKABLE void updateDockLayout(double height) {
        callDock({QStringLiteral("updateLayout"),
                  QString::number(height, 'f', 2)});
    }

    Q_INVOKABLE void updateDockPosition(const QString &position) {
        callDock({QStringLiteral("updatePosition"), position});
    }

    Q_INVOKABLE void updateDockBuiltinVisibility(const QString &id, bool visible) {
        callDock({QStringLiteral("updateBuiltinVisibility"), id,
                  visible ? QStringLiteral("true") : QStringLiteral("false")});
    }

    Q_INVOKABLE void updateDockContentStyle(const QString &style) {
        callDock({QStringLiteral("updateContentStyle"), style});
    }

    Q_INVOKABLE void updateDockStyle(const QString &style) {
        callDock({QStringLiteral("updateDockStyle"), style});
    }

    Q_INVOKABLE void updateDockIconMode(const QString &mode) {
        callDock({QStringLiteral("updateIconMode"), mode});
    }

    Q_INVOKABLE void updateDockIconOpacity(double opacity) {
        callDock({QStringLiteral("updateIconOpacity"),
                  QString::number(opacity, 'f', 2)});
    }

    Q_INVOKABLE void updateDockIconTintColor(const QString &color) {
        callDock({QStringLiteral("updateIconTintColor"), color});
    }

    Q_INVOKABLE void updateDockVisibilityMode(const QString &mode) {
        callDock({QStringLiteral("updateVisibilityMode"), mode});
    }

    Q_INVOKABLE void updateDockWindowGrouping(const QString &mode) {
        callDock({QStringLiteral("updateWindowGrouping"), mode});
    }

    Q_INVOKABLE void appearanceSnapshot() {
        callAppearance({QStringLiteral("snapshot")});
    }

    Q_INVOKABLE void updateBlurStrength(double strength) {
        callAppearance({
            QStringLiteral("updateGlobalBlurStrength"),
            QString::number(strength, 'f', 3)});
    }

    Q_INVOKABLE void updateLiquidStrength(double strength) {
        callAppearance({
            QStringLiteral("updateGlobalLiquidStrength"),
            QString::number(strength, 'f', 3)});
    }

    Q_INVOKABLE void updateGlobalBlurStrength(double strength) {
        callAppearance({
            QStringLiteral("updateGlobalBlurStrength"),
            QString::number(strength, 'f', 3)});
    }

    Q_INVOKABLE void updateGlobalLiquidStrength(double strength) {
        callAppearance({
            QStringLiteral("updateGlobalLiquidStrength"),
            QString::number(strength, 'f', 3)});
    }

    Q_INVOKABLE void updateGlassStyle(const QString &style) {
        callAppearance({QStringLiteral("updateGlassStyle"), style});
    }

    Q_INVOKABLE void updateGlassPresetParameter(const QString &name, double value) {
        callAppearance({
            QStringLiteral("updateGlassPresetParameter"), name,
            QString::number(value, 'f', 3)});
    }

    Q_INVOKABLE void resetGlassPreset(const QString &style) {
        callAppearance({QStringLiteral("resetGlassPreset"), style});
    }

    // One appearance request feeds both products the debug page needs: the
    // spec table is local (kwinrc + the cached shell snapshot), while the
    // preset style label names which preset that snapshot belongs to, so it
    // is only meaningful once the snapshot reply arrives. Both are delivered
    // together on glassDebugSnapshotChanged.
    Q_INVOKABLE void glassDebugSnapshot() {
        callShell(QStringLiteral("appearance-settings"),
                  {QStringLiteral("snapshot")},
                  QStringLiteral("外观设置请求失败"), RequestKind::GlassDebug);
    }

    // Fire-and-forget: the reply (a full snapshot for preset-backed keys)
    // lands on glassDebugSnapshotChanged, which re-reads the stored values
    // through the shell's own clamping, so the page never needed the return
    // value it used to wait on.
    Q_INVOKABLE void updateGlassDebugValue(const QString &key, const QVariant &value) {
        const QVariantMap match = glassDebugSpec(key);
        if (match.isEmpty()) {
            setLastError(QStringLiteral("未知的 KWin 参数：%1").arg(key));
            emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
            return;
        }
        QVariant stored = value;
        // A design-value row has no writable home: the shell re-derives it on
        // every appearance sync. Refuse the write rather than let the value
        // silently revert, and say why so the failure is not a mystery.
        if (match.value(QStringLiteral("readOnly")).toBool()) {
            setLastError(QStringLiteral("该参数由外观设计值决定，无法在此修改"));
            emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
            return;
        }

        const QString type = match.value(QStringLiteral("type")).toString();        if (type == QStringLiteral("bool")) stored = value.toBool();
        else if (type != QStringLiteral("string")) {
            const double number = qBound(match.value(QStringLiteral("min")).toDouble(),
                value.toDouble(), match.value(QStringLiteral("max")).toDouble());
            stored = type == QStringLiteral("int") ? QVariant(qRound(number)) : QVariant(number);
        }
        // A preset-backed key belongs to the shell: writing kwinrc directly
        // would be undone by the next appearance sync. Hand it the value in
        // preset units and let it persist the preset and reconfigure the
        // effect; the reply is a full snapshot, so a rejected write (bad name,
        // shell down) reports why.
        if (const PresetDebugKey *preset = presetDebugKey(key)) {
            callShell(QStringLiteral("appearance-settings"),
                      {QStringLiteral("updateGlassPresetParameter"),
                       QString::fromLatin1(preset->parameter),
                       QString::number(stored.toDouble() / preset->toKwinrc, 'f', 3)},
                      QStringLiteral("外观设置请求失败"), RequestKind::GlassDebug);
            return;
        }
        QSettings config(QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
            + QStringLiteral("/kwinrc"), QSettings::IniFormat);
        config.beginGroup(QStringLiteral("Effect-blurplus"));
        config.setValue(key, stored); config.endGroup(); config.sync();
        QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
            QStringLiteral("org.kde.kwin.Effects"));
        if (effects.isValid())
            effects.asyncCall(QStringLiteral("reconfigureEffect"), QStringLiteral("glass"));
        if (config.status() != QSettings::NoError) {
            setLastError(QStringLiteral("写入 KWin 配置失败"));
            emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
            return;
        }
        glassDebugSnapshot();
    }

    Q_INVOKABLE void updateGlobalIconMode(const QString &mode) {
        callAppearance({QStringLiteral("updateGlobalIconMode"), mode});
    }

    Q_INVOKABLE void updateGlobalIconOpacity(double opacity) {
        callAppearance({
            QStringLiteral("updateGlobalIconOpacity"),
            QString::number(opacity, 'f', 3)});
    }

    Q_INVOKABLE void updateGlobalIconTintColor(const QString &color) {
        callAppearance({QStringLiteral("updateGlobalIconTintColor"), color});
    }

    Q_INVOKABLE void updateShellStyle(const QString &style) {
        callAppearance({QStringLiteral("updateShellStyle"), style});
    }

    Q_INVOKABLE void updateMaterialColorScheme(const QString &scheme) {
        callAppearance({QStringLiteral("updateMaterialColorScheme"), scheme});
    }

    Q_INVOKABLE void updateBarIntegratedWithDock(bool enabled) {
        callAppearance({
            QStringLiteral("updateBarIntegratedWithDock"),
            enabled ? QStringLiteral("true") : QStringLiteral("false")});
    }

    Q_INVOKABLE void updateGlassFollowsAppearanceMode(bool enabled) {
        callAppearance({
            QStringLiteral("updateGlassFollowsAppearanceMode"),
            enabled ? QStringLiteral("true") : QStringLiteral("false")});
    }

    Q_INVOKABLE void updateBarVisibilityMode(const QString &mode) {
        callAppearance({QStringLiteral("updateBarVisibilityMode"), mode});
    }

    Q_INVOKABLE void updateBarLayoutMode(const QString &mode) {
        callAppearance({QStringLiteral("updateBarLayoutMode"), mode});
    }

    Q_INVOKABLE void updateDockWindowAnimationStyle(const QString &style) {
        callAppearance({QStringLiteral("updateDockWindowAnimationStyle"), style});
    }

    Q_INVOKABLE void resetAppearanceStrengths() {
        callAppearance({QStringLiteral("resetStrengths")});
    }

    Q_INVOKABLE void launcherSnapshot() {
        callLauncher({QStringLiteral("snapshot")});
    }

    Q_INVOKABLE void shortcutsSnapshot() {
        callShortcuts({QStringLiteral("snapshot")});
    }

    Q_INVOKABLE void updateShortcut(const QString &id, const QString &combo) {
        callShortcuts({QStringLiteral("updateShortcut"), id, combo});
    }

    Q_INVOKABLE void resetShortcut(const QString &id) {
        callShortcuts({QStringLiteral("resetShortcut"), id});
    }

    Q_INVOKABLE void updateLauncherDisplayMode(const QString &mode) {
        callLauncher({QStringLiteral("updateDisplayMode"), mode});
    }

    Q_INVOKABLE void updateLauncherProfileIconSize(const QString &mode,
                                                    const QString &size) {
        callLauncher({
            QStringLiteral("updateProfileIconSize"), mode, size});
    }

    Q_INVOKABLE void updateLauncherProfileDensity(const QString &mode,
                                                    const QString &density) {
        callLauncher({
            QStringLiteral("updateProfileDensity"), mode, density});
    }

    Q_INVOKABLE void updateLauncherProfileFontWeight(const QString &mode,
                                                      const QString &weight) {
        callLauncher({
            QStringLiteral("updateProfileFontWeight"), mode, weight});
    }

    Q_INVOKABLE void resetLauncherLayoutProfile(const QString &mode) {
        callLauncher({QStringLiteral("resetProfile"), mode});
    }

    Q_INVOKABLE void applySystemAppearance(bool dark) {
        callShell(QStringLiteral("appearance-settings"),
                  {QStringLiteral("applySystemAppearance"),
                   dark ? QStringLiteral("true") : QStringLiteral("false")},
                  QStringLiteral("外观设置请求失败"),
                  RequestKind::ApplySystemAppearance);
    }

    // Only the request is issued here; the reply handler folds in the D-Bus
    // and /proc probes (off the UI thread) before emitting the snapshot.
    Q_INVOKABLE void integrationSnapshot() {
        if (m_integrationPending)
            return;
        m_integrationPending = true;
        callShell(QStringLiteral("integration-status"), {QStringLiteral("snapshot")},
                  QStringLiteral("接入状态请求失败"), RequestKind::Integration);
    }

signals:
    void lastErrorChanged();
    void sessionChanged();
    void entryChanged();
    void bannerDismissedChanged();
    void dockSnapshotChanged(const QVariantMap &snapshot);
    void appearanceSnapshotChanged(const QVariantMap &snapshot);
    void launcherSnapshotChanged(const QVariantMap &snapshot);
    void shortcutsSnapshotChanged(const QVariantMap &snapshot);
    void glassDebugSnapshotChanged(const QVariantList &controls,
                                   const QString &presetStyle);
    void integrationSnapshotChanged(const QVariantMap &snapshot);
    void systemAppearanceApplied(bool accepted);

private:
    // What the requesting page wants back once the IPC reply lands: every
    // request maps to exactly one signal.
    enum class RequestKind {
        Dock,
        Appearance,
        Launcher,
        Shortcuts,
        Integration,
        GlassDebug,
        ApplySystemAppearance,
    };

    QVariantMap snapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的 Dock 配置"));
            return {};
        }

        const QJsonObject object = document.object();
        if (!object.contains(QStringLiteral("baseHeight"))
                || !object.contains(QStringLiteral("windowGrouping"))) {
            setLastError(QStringLiteral("桌面环境返回的 Dock 配置不完整"));
            return {};
        }

        setLastError({});
        return {
            {QStringLiteral("baseHeight"), object.value(QStringLiteral("baseHeight")).toDouble()},
            {QStringLiteral("position"), object.value(QStringLiteral("position")).toString()},
            // contentStyle/dockStyle are read straight back by the dock page's
            // applyState; without them the two pickers snap back to index 0 on
            // every snapshot refresh.
            {QStringLiteral("contentStyle"), object.value(QStringLiteral("contentStyle")).toString()},
            {QStringLiteral("dockStyle"), object.value(QStringLiteral("dockStyle")).toString()},
            {QStringLiteral("iconMode"), object.value(QStringLiteral("iconMode")).toString()},
            {QStringLiteral("iconOpacity"), object.value(QStringLiteral("iconOpacity")).toDouble()},
            {QStringLiteral("iconTintColor"), object.value(QStringLiteral("iconTintColor")).toString()},
            {QStringLiteral("visibilityMode"), object.value(QStringLiteral("visibilityMode")).toString()},
            {QStringLiteral("windowGrouping"), object.value(QStringLiteral("windowGrouping")).toString()},
            {QStringLiteral("showLauncher"), object.value(QStringLiteral("showLauncher")).toBool(true)},
            {QStringLiteral("showTrash"), object.value(QStringLiteral("showTrash")).toBool(true)},
        };
    }

    QVariantMap appearanceSnapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的外观配置"));
            return {};
        }

        const QJsonObject object = document.object();
        if ((!object.contains(QStringLiteral("globalBlurStrength"))
                    && !object.contains(QStringLiteral("dockBlurStrength"))
                    && !object.contains(QStringLiteral("blurStrength")))
                || (!object.contains(QStringLiteral("globalLiquidStrength"))
                    && !object.contains(QStringLiteral("dockLiquidStrength"))
                    && !object.contains(QStringLiteral("liquidStrength")))
                || !object.contains(QStringLiteral("shellStyle"))
                || !object.contains(QStringLiteral("barIntegratedWithDock"))
                || !object.contains(QStringLiteral("dockWindowAnimationStyle"))) {
            setLastError(QStringLiteral("桌面环境返回的外观配置不完整"));
            return {};
        }

        const double globalBlur = object.contains(QStringLiteral("globalBlurStrength"))
            ? object.value(QStringLiteral("globalBlurStrength")).toDouble()
            : (object.contains(QStringLiteral("dockBlurStrength"))
                ? object.value(QStringLiteral("dockBlurStrength")).toDouble()
                : object.value(QStringLiteral("blurStrength")).toDouble());
        const double globalLiquid = object.contains(QStringLiteral("globalLiquidStrength"))
            ? object.value(QStringLiteral("globalLiquidStrength")).toDouble()
            : (object.contains(QStringLiteral("dockLiquidStrength"))
                ? object.value(QStringLiteral("dockLiquidStrength")).toDouble()
                : object.value(QStringLiteral("liquidStrength")).toDouble());

        const QString barVisibility = object.value(QStringLiteral("barVisibilityMode")).toString(QStringLiteral("always"));

        setLastError({});
        // Also the source glassDebugSpecs() reads the active preset from: this
        // object carries every preset field, while the map below hand-picks the
        // ones the appearance pages consume.
        m_appearanceSnapshot = object;
        return {
            {QStringLiteral("globalBlurStrength"), globalBlur},
            {QStringLiteral("globalLiquidStrength"), globalLiquid},
            {QStringLiteral("glassStyle"),
                object.value(QStringLiteral("glassStyle")).toString(QStringLiteral("liquid"))},
            {QStringLiteral("activePresetRefraction"),
                object.value(QStringLiteral("activePresetRefraction")).toDouble(1.0)},
            {QStringLiteral("activePresetSoftness"),
                object.value(QStringLiteral("activePresetSoftness")).toDouble()},
            {QStringLiteral("activePresetReflection"),
                object.value(QStringLiteral("activePresetReflection")).toDouble()},
            {QStringLiteral("effectiveDockBlur"), globalBlur},
            {QStringLiteral("effectiveDockLiquid"), globalLiquid},
            {QStringLiteral("effectiveBarBlur"), globalBlur},
            {QStringLiteral("effectiveBarLiquid"), globalLiquid},
            {QStringLiteral("effectiveLauncherBlur"), globalBlur},
            {QStringLiteral("effectiveLauncherLiquid"), globalLiquid},
            {QStringLiteral("blurStrength"), globalBlur},
            {QStringLiteral("liquidStrength"), globalLiquid},
            {QStringLiteral("iconMode"), object.value(QStringLiteral("iconMode")).toString(QStringLiteral("color"))},
            {QStringLiteral("iconOpacity"), object.value(QStringLiteral("iconOpacity")).toDouble(0.5)},
            {QStringLiteral("iconTintColor"), object.value(QStringLiteral("iconTintColor")).toString(QStringLiteral("#a855f7"))},
            {QStringLiteral("shellStyle"), object.value(QStringLiteral("shellStyle")).toString()},
            {QStringLiteral("materialColorScheme"),
                object.value(QStringLiteral("materialColorScheme")).toString(QStringLiteral("monet"))},
            {QStringLiteral("materialAccentName"),
                object.value(QStringLiteral("materialAccentName")).toString()},
            // Swatch previews for the colour-source picker, as a JSON string.
            // The QML side parses it; passing the nested structure through
            // QVariantList/QVariantMap instead left the picker empty.
            {QStringLiteral("materialColorSwatches"),
                object.value(QStringLiteral("materialColorSwatches")).toString()},
            {QStringLiteral("barIntegratedWithDock"),
                object.value(QStringLiteral("barIntegratedWithDock")).toBool()},
            {QStringLiteral("glassFollowsAppearanceMode"),
                object.value(QStringLiteral("glassFollowsAppearanceMode")).toBool(true)},
            {QStringLiteral("barVisibilityMode"),
                barVisibility.isEmpty() ? QStringLiteral("always") : barVisibility},
            {QStringLiteral("barLayoutMode"),
                object.value(QStringLiteral("barLayoutMode")).toString(QStringLiteral("transparent"))},
            {QStringLiteral("dockWindowAnimationStyle"),
                object.value(QStringLiteral("dockWindowAnimationStyle")).toString()},
            {QStringLiteral("tokenVersion"), object.value(QStringLiteral("tokenVersion")).toInt()},
        };
    }

    QVariantMap launcherSnapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的启动台配置"));
            return {};
        }

        const QJsonObject object = document.object();
        if (!object.contains(QStringLiteral("displayMode"))) {
            setLastError(QStringLiteral("桌面环境返回的启动台配置不完整"));
            return {};
        }

        setLastError({});
        return {
            {QStringLiteral("displayMode"), object.value(QStringLiteral("displayMode")).toString()},
            {QStringLiteral("layoutProfiles"),
                object.value(QStringLiteral("layoutProfiles")).toObject().toVariantMap()},
        };
    }

    QVariantMap integrationSnapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {{QStringLiteral("shellReady"), false}};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的接入状态"));
            return {{QStringLiteral("shellReady"), false}};
        }
        setLastError({});
        return document.object().toVariantMap();
    }

    QVariantMap shortcutsSnapshotFromReply(const QString &payload) {
        if (payload.isEmpty())
            return {};

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(payload.toUtf8(), &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
            setLastError(QStringLiteral("桌面环境返回了无效的快捷键配置"));
            return {};
        }

        const QJsonObject object = document.object();
        if (!object.contains(QStringLiteral("shortcuts"))) {
            setLastError(QStringLiteral("桌面环境返回的快捷键配置不完整"));
            return {};
        }

        QVariantList shortcuts;
        for (const QJsonValue &value : object.value(QStringLiteral("shortcuts")).toArray()) {
            const QJsonObject item = value.toObject();
            shortcuts.append(QVariantMap{
                {QStringLiteral("id"), item.value(QStringLiteral("id")).toString()},
                {QStringLiteral("description"), item.value(QStringLiteral("description")).toString()},
                {QStringLiteral("defaultCombo"), item.value(QStringLiteral("defaultCombo")).toString()},
                {QStringLiteral("combo"), item.value(QStringLiteral("combo")).toString()},
                {QStringLiteral("custom"), item.value(QStringLiteral("custom")).toBool()},
            });
        }

        // The Shell validates rebinding requests and reports rejections
        // (unknown id, malformed combo, duplicate binding) inline instead of
        // failing the IPC call, so surface it the same way as transport errors.
        const QString error = object.value(QStringLiteral("error")).toString();
        setLastError(error);
        return {
            {QStringLiteral("shortcuts"), shortcuts},
            {QStringLiteral("error"), error},
        };
    }

    // The 材质 rows' spec table, read from kwinrc with preset values overlaid
    // from the last appearance snapshot. Local file + cached state only, so
    // it is safe to build on the UI thread when the IPC reply lands.
    QVariantList glassDebugSpecs() const {
        const QString path = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
            + QStringLiteral("/kwinrc");
        QSettings config(path, QSettings::IniFormat);
        config.beginGroup(QStringLiteral("Effect-blurplus"));
        QVariantList result;
        const auto add = [&](const char *key, const char *label, const char *section,
                             const char *type, double minimum, double maximum,
                             double step, const QVariant &fallback) {
            // Preset-backed rows report the preset's own value, converted into
            // kwinrc units so the ranges below stay meaningful, and are marked so
            // updateGlassDebugValue() knows to write the preset rather than kwinrc.
            bool presetBacked = false;
            const bool readOnly = isReadOnlyDebugKey(QString::fromLatin1(key));
            QVariant value = config.value(QString::fromLatin1(key), fallback);
            if (const PresetDebugKey *preset = presetDebugKey(QString::fromLatin1(key))) {
                const QJsonValue stored = m_appearanceSnapshot.value(
                    QStringLiteral("activePreset") + QString::fromLatin1(preset->parameter));
                if (stored.isDouble()) {
                    presetBacked = true;
                    value = stored.toDouble() * preset->toKwinrc;
                }
            }
            result.append(QVariantMap{{QStringLiteral("key"), QString::fromLatin1(key)},
                {QStringLiteral("label"), QString::fromUtf8(label)},
                {QStringLiteral("section"), QString::fromUtf8(section)},
                {QStringLiteral("type"), QString::fromLatin1(type)},
                {QStringLiteral("min"), minimum}, {QStringLiteral("max"), maximum},
                {QStringLiteral("step"), step},
                {QStringLiteral("presetBacked"), presetBacked},
                {QStringLiteral("readOnly"), readOnly},
                {QStringLiteral("value"), value}});
        };
        add("BlurFinetune", "模糊精调", "模糊", "int", 0, 10, 1, 3);
        add("NoiseStrength", "内容噪点", "模糊", "int", 0, 100, 1, 5);
        add("DecorationNoiseStrength", "窗口装饰噪点", "模糊", "int", 0, 100, 1, 5);
        add("DockNoiseStrength", "Dock 噪点", "模糊", "int", 0, 100, 1, 5);
        add("BlurSaturationCompensation", "模糊饱和度补偿", "模糊", "bool", 0, 1, 1, true);
        add("Brightness", "亮度", "色彩", "real", 0, 2, .01, 1.0);
        add("Saturation", "饱和度", "色彩", "real", 0, 3, .01, 1.0);
        add("Contrast", "对比度", "色彩", "real", 0, 2, .01, 1.0);
        add("OklabSaturation", "使用 OKLab 饱和度", "色彩", "bool", 0, 1, 1, false);
        add("RefractionStrength", "折射强度", "材质", "real", 0, 20, .1, 0.0);
        add("RefractionEdgeSize", "折射边缘范围", "材质", "real", 0, 50, .1, 20.0);
        add("RefractionNormalPow", "折射法线曲线", "材质", "real", .1, 10, .1, 2.0);
        add("RefractionRGBFringing", "RGB 色散", "材质", "real", 0, 20, .1, 1.0);
        add("RefractionOffsetStrength", "主体折射强度", "材质", "real", 0, 20, .1, 0.0);
        add("MaterialSoftness", "柔和度", "材质", "real", 0, 1, .01, 0.0);
        add("MaterialReflectionStrength", "宽反射强度", "材质", "real", 0, 1, .01, 0.0);
        add("ExcludeDecorations", "窗口装饰不应用染色", "适用范围", "bool", 0, 1, 1, false);
        add("MenuCornerRadius", "菜单圆角", "圆角", "real", 0, 100, 1, 0.0);
        add("DockCornerRadius", "Dock 圆角", "圆角", "real", 0, 100, 1, 0.0);
        add("CornerExponent", "圆角连续度", "圆角", "real", 2, 8, .1, 3.0);
        add("UseDeclaredCornerRadius", "优先使用应用声明圆角", "圆角", "bool", 0, 1, 1, false);
        add("IgnoreContentBlurRegion", "忽略内容模糊区域", "圆角", "bool", 0, 1, 1, false);
        add("DynamicCorners", "动态圆角", "圆角", "bool", 0, 1, 1, false);
        add("DynamicCornersExcludeDocks", "动态圆角排除 Dock", "圆角", "bool", 0, 1, 1, false);
        add("DynamicCornersExcludeTooltips", "动态圆角排除 Tooltip", "圆角", "bool", 0, 1, 1, false);
        add("DynamicCornersExcludeMenus", "动态圆角排除菜单", "圆角", "bool", 0, 1, 1, false);
        add("OnlyQuickshell", "仅处理 Quickshell", "窗口匹配", "bool", 0, 1, 1, true);
        add("WindowClasses", "窗口类列表", "窗口匹配", "string", 0, 0, 0, QStringLiteral("quickshell"));
        add("BlurMatching", "匹配列表内窗口", "窗口匹配", "bool", 0, 1, 1, true);
        add("BlurDecorations", "强制模糊窗口装饰", "窗口匹配", "bool", 0, 1, 1, false);
        add("BlurMenus", "强制模糊菜单", "窗口匹配", "bool", 0, 1, 1, false);
        add("BlurDocks", "强制模糊 Dock", "窗口匹配", "bool", 0, 1, 1, false);
        add("SkipEmptyDockBlurRegions", "跳过空 Dock 模糊区域", "窗口匹配", "bool", 0, 1, 1, true);
        config.endGroup();
        return result;
    }

    // Which style's preset the debug page's 材质 rows edit, as of the last
    // appearance snapshot. Shown next to them so a tuned value is not
    // mistaken for a global one.
    QString glassPresetStyle() const {
        return m_appearanceSnapshot.value(QStringLiteral("glassStyle"))
            .toString(QStringLiteral("liquid"));
    }

    // Spec lookup for updateGlassDebugValue(): the spec table itself does not
    // depend on the shell snapshot, so this reuses whatever the last reply
    // cached instead of paying for another round trip per edit.
    QVariantMap glassDebugSpec(const QString &key) const {
        const QVariantList specs = glassDebugSpecs();
        for (const QVariant &item : specs) {
            const QVariantMap spec = item.toMap();
            if (spec.value(QStringLiteral("key")).toString() == key)
                return spec;
        }
        return {};
    }

    // The notification-owner and KWin probes use blocking D-Bus calls and a
    // /proc read, so they run on a worker thread; the finished snapshot is
    // delivered back on the UI thread through a queued invocation, which is
    // the only place QML-visible state is touched.
    void startIntegrationProbe(const QVariantMap &replyMap) {
        // The bridge may be destroyed while the probe is still running, so the
        // worker only captures a QPointer: no member of this is touched off the
        // UI thread, and the queued delivery is skipped once it is gone.
        const QPointer<SettingsBridge> guard(this);
        QThread *thread = QThread::create([guard, replyMap]() {
            QVariantMap result = replyMap;

            const QDBusConnection sessionBus = QDBusConnection::sessionBus();
            auto *busInterface = sessionBus.interface();
            QString notificationProvider = QStringLiteral("none");
            QString notificationOwner;
            uint notificationPid = 0;
            if (busInterface) {
                const QDBusReply<QString> ownerReply = busInterface->serviceOwner(
                    QStringLiteral("org.freedesktop.Notifications"));
                if (ownerReply.isValid() && !ownerReply.value().isEmpty()) {
                    notificationOwner = ownerReply.value();
                    const QDBusReply<uint> pidReply = busInterface->servicePid(notificationOwner);
                    if (pidReply.isValid())
                        notificationPid = pidReply.value();

                    QFile commandLine(QStringLiteral("/proc/%1/cmdline").arg(notificationPid));
                    QString command;
                    if (commandLine.open(QIODevice::ReadOnly)) {
                        QByteArray raw = commandLine.readAll();
                        raw.replace('\0', ' ');
                        command = QString::fromLocal8Bit(raw).trimmed();
                    }
                    if (command.contains(QStringLiteral("plasmashell"))) {
                        notificationProvider = QStringLiteral("plasma");
                    } else if (command.contains(QStringLiteral("/qs"))
                               || command.contains(QStringLiteral("quickshell"))) {
                        notificationProvider = QStringLiteral("kos");
                    } else {
                        notificationProvider = QStringLiteral("other");
                    }
                    result.insert(QStringLiteral("notificationCommand"), command);
                }
            }
            result.insert(QStringLiteral("notificationProvider"), notificationProvider);
            result.insert(QStringLiteral("notificationOwner"), notificationOwner);
            result.insert(QStringLiteral("notificationPid"), notificationPid);

            QDBusInterface effects(QStringLiteral("org.kde.KWin"), QStringLiteral("/Effects"),
                                   QStringLiteral("org.kde.kwin.Effects"), sessionBus);
            const QStringList loadedEffects = effects.isValid()
                ? effects.property("loadedEffects").toStringList() : QStringList{};
            result.insert(QStringLiteral("kwinAvailable"), effects.isValid());
            result.insert(QStringLiteral("glassLoaded"),
                          loadedEffects.contains(QStringLiteral("glass")));
            result.insert(QStringLiteral("dockAnimationLoaded"),
                          loadedEffects.contains(QStringLiteral("kos_dock_window_animation")));
            result.insert(QStringLiteral("contextMenuInputLoaded"),
                          loadedEffects.contains(QStringLiteral("kos_context_menu_input")));
            result.insert(QStringLiteral("updatedAt"),
                          QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss")));

            if (guard) {
                QMetaObject::invokeMethod(guard.data(), [guard, result]() {
                    if (!guard)
                        return;
                    guard->m_integrationPending = false;
                    emit guard->integrationSnapshotChanged(result);
                }, Qt::QueuedConnection);
            }
        });
        connect(thread, &QThread::finished, thread, &QObject::deleteLater);
        thread->start();
    }

    void callDock(const QStringList &arguments) {
        callShell(QStringLiteral("dock-settings"), arguments,
                  QStringLiteral("Dock 设置请求失败"), RequestKind::Dock);
    }

    void callAppearance(const QStringList &arguments) {
        callShell(QStringLiteral("appearance-settings"), arguments,
                  QStringLiteral("外观设置请求失败"), RequestKind::Appearance);
    }

    void callLauncher(const QStringList &arguments) {
        callShell(QStringLiteral("applauncher-settings"), arguments,
                  QStringLiteral("启动台设置请求失败"), RequestKind::Launcher);
    }

    void callShortcuts(const QStringList &arguments) {
        callShell(QStringLiteral("shortcuts-settings"), arguments,
                  QStringLiteral("快捷键设置请求失败"), RequestKind::Shortcuts);
    }

    static QString installedShellDirectory() {
        return QStandardPaths::writableLocation(QStandardPaths::ConfigLocation)
            + QStringLiteral("/quickshell/kos");
    }

    // The session directory equals the installed one only when the Shell was
    // started as `-c kos`. Compared cleaned, because the value arrives from the
    // environment and a trailing slash would otherwise read as a checkout.
    static bool isInstalledShellDirectory(const QString &shellPath) {
        if (shellPath.isEmpty())
            return false;
        return QDir::cleanPath(shellPath) == QDir::cleanPath(installedShellDirectory());
    }

    // Recorded from the candidate that actually answered, so a window opened
    // without KOS_SHELL_DIR (app grid, KRunner) still learns which session it is
    // serving instead of guessing from the fallback order.
    void setSessionShell(const QString &shellPath) {
        if (m_sessionShellDir == shellPath)
            return;
        m_sessionShellDir = shellPath;
        emit sessionChanged();
    }

    // Candidate Shell directories, most specific first. A Settings window is
    // started from two different places and only one of them can pass the
    // environment down: the Shell's own Settings entry goes through the
    // platform daemon, which exports KOS_SHELL_DIR for the session it belongs
    // to, while a .desktop launch (app grid, KRunner, menu) inherits nothing.
    // The list is therefore a preference order, and an ordinary launch (no
    // KOS_SHELL_DIR) has to reach the running session on its first try.
    static QStringList shellDirectories() {
        QStringList directories;
        const QString configured = qEnvironmentVariable("KOS_SHELL_DIR");
        if (!configured.isEmpty())
            directories.append(configured);

        // Then the installed session: an end user only ever runs that one, and
        // it is the session this binary belongs to. Its directory is an
        // absolute path under the config location, so it does not depend on
        // the current working directory or on any inherited environment.
        directories.append(installedShellDirectory());

        // The compile-time source tree is a fallback for `qs -p <dir>`
        // sessions, NOT a first choice: it exists on any machine that built
        // this binary (a Nix store copy, or the checkout itself), so trying it
        // first would aim every ordinary launch at a Shell that is not
        // running. Both spellings of the literal are offered because
        // Quickshell matches instances by the path it was launched with, and
        // only comparably-spelled paths hit: the cleaned form handles the `..`
        // segments (apps/settings/../../shell), the canonical form handles a
        // checkout reached through a symlink (a synced or linked folder).
        const QString declared = QDir::cleanPath(QStringLiteral(SETTINGS_SHELL_DIR));
        const QString canonical = QFileInfo(declared).canonicalFilePath();
        for (const QString &source : {declared, canonical}) {
            if (source.isEmpty() || directories.contains(source))
                continue;
            if (QFileInfo::exists(QDir(source).filePath(QStringLiteral("shell.qml"))))
                directories.append(source);
        }

        directories.removeDuplicates();
        return directories;
    }

    // Quickshell tracks instances by how they identify their config: a Shell
    // launched as `-c kos` is NOT matched by `--path <same dir>`. The installed
    // session runs as `-c kos`, so address it by name; development sessions
    // (`-p <dir>`) take the explicit path.
    static QStringList connectArgsFor(const QString &shellPath) {
        if (shellPath == installedShellDirectory())
            return {QStringLiteral("-c"), QStringLiteral("kos")};
        return {QStringLiteral("--path"), shellPath};
    }

    // Quickshell's `ipc call` exits 0 while printing one of these diagnostics,
    // so a zero exit code on its own cannot be trusted: a wrong instance -- one
    // without the target, or a stale build without the function -- would
    // otherwise answer with an error sentence as if it were the value.
    static bool isIpcDiagnostic(const QString &reply) {
        static const QStringList diagnostics = {
            QStringLiteral("Target not found."),
            QStringLiteral("Function not found."),
            QStringLiteral("Function required to send message."),
        };
        return diagnostics.contains(reply);
    }

    void callShell(const QString &target, const QStringList &arguments,
                   const QString &fallbackError, RequestKind kind) {
        startShellAttempt(target, arguments, fallbackError, kind,
                          shellDirectories(), 0, 0, {});
    }

    // One asynchronous attempt at one candidate. On a diagnostic reply or a
    // transport failure the next attempt/candidate is chained from the
    // process's finished signal, so the UI thread never waits: the preferred
    // candidate gets one retry (the Shell can still be registering IPC
    // targets during the first moments of a development launch); later
    // candidates are fallbacks, where a second attempt buys nothing.
    void startShellAttempt(const QString &target, const QStringList &arguments,
                           const QString &fallbackError, RequestKind kind,
                           const QStringList &shellPaths, int index, int attempt,
                           const QString &failure) {
        const QString shellPath = shellPaths.at(index);
        QStringList command = connectArgsFor(shellPath);
        command << QStringLiteral("ipc") << QStringLiteral("call") << target;
        command.append(arguments);

        auto *process = new QProcess(this);
        // A hung `quickshell ipc call` used to sit inside waitForFinished() on
        // the UI thread; now the timeout is a timer, so the worst case is a
        // killed stale process, not a frozen window.
        auto *watchdog = new QTimer(process);
        watchdog->setSingleShot(true);
        watchdog->setInterval(5000);
        connect(process, &QProcess::started, watchdog, qOverload<>(&QTimer::start));
        connect(watchdog, &QTimer::timeout, process, [process]() {
            process->setProperty("timedOut", true);
            process->kill();
        });
        connect(process, &QProcess::finished, this,
                [this, process, kind, target, arguments, shellPath, fallbackError,
                 shellPaths, index, attempt, failure](int exitCode,
                                                      QProcess::ExitStatus exitStatus) {
            const QString output = QString::fromUtf8(
                process->readAllStandardOutput()).trimmed();
            const bool preferred = index == 0;
            const int maxAttempts = preferred ? 2 : 1;
            // Retry the preferred candidate, fall through to the next one, and
            // only report failure once every candidate has been tried.
            const auto advance = [&](const QString &reason) {
                if (attempt + 1 < maxAttempts) {
                    startShellAttempt(target, arguments, fallbackError, kind,
                                      shellPaths, index, attempt + 1, reason);
                } else if (index + 1 < shellPaths.size()) {
                    startShellAttempt(target, arguments, fallbackError, kind,
                                      shellPaths, index + 1, 0, reason);
                } else {
                    setLastError(QStringLiteral("%1（IPC：%2；Shell：%3）")
                                     .arg(reason, target, shellPath));
                    failKind(kind);
                }
            };
            if (exitStatus == QProcess::NormalExit && exitCode == 0) {
                if (!isIpcDiagnostic(output)) {
                    setSessionShell(QDir::cleanPath(shellPath));
                    handleReply(kind, output);
                } else {
                    // A diagnostic reply means this candidate is not the Shell
                    // serving us, so treat it like a hard failure.
                    advance(fallbackError);
                }
            } else {
                QString reason = QString::fromUtf8(
                    process->readAllStandardError()).trimmed();
                if (process->property("timedOut").toBool())
                    reason = QStringLiteral("桌面环境没有响应（超过 5 秒）");
                else if (reason.isEmpty())
                    reason = fallbackError;
                advance(reason);
            }
            process->deleteLater();
        });
        // FailedToStart never emits finished; crashes do, and are reported
        // there so a dead process is not counted twice.
        connect(process, &QProcess::errorOccurred, this,
                [this, process, kind, target, arguments, shellPath, shellPaths,
                 index, attempt, failure](QProcess::ProcessError error) {
            if (error != QProcess::FailedToStart)
                return;
            const bool preferred = index == 0;
            const int maxAttempts = preferred ? 2 : 1;
            const QString reason = QStringLiteral("无法启动 Quickshell IPC");
            if (attempt + 1 < maxAttempts) {
                startShellAttempt(target, arguments, reason, kind,
                                  shellPaths, index, attempt + 1, reason);
            } else if (index + 1 < shellPaths.size()) {
                startShellAttempt(target, arguments, reason, kind,
                                  shellPaths, index + 1, 0, reason);
            } else {
                setLastError(QStringLiteral("%1（IPC：%2；Shell：%3）")
                                 .arg(reason, target, shellPath));
                failKind(kind);
            }
            process->deleteLater();
        });
        process->start(QStringLiteral("quickshell"), command);
    }

    // Dispatch the reply to the signal the requesting page listens to.
    void handleReply(RequestKind kind, const QString &payload) {
        switch (kind) {
        case RequestKind::Dock:
            emit dockSnapshotChanged(snapshotFromReply(payload));
            break;
        case RequestKind::Appearance:
            emit appearanceSnapshotChanged(appearanceSnapshotFromReply(payload));
            break;
        case RequestKind::Launcher:
            emit launcherSnapshotChanged(launcherSnapshotFromReply(payload));
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
            const QJsonDocument document = QJsonDocument::fromJson(
                payload.toUtf8(), &parseError);
            bool accepted = false;
            if (parseError.error == QJsonParseError::NoError && document.isObject())
                accepted = document.object()
                    .value(QStringLiteral("accepted")).toBool();
            if (!accepted && m_lastError.isEmpty())
                setLastError(QStringLiteral("桌面环境拒绝了主题切换请求"));
            emit systemAppearanceApplied(accepted);
            break;
        }
        }
    }

    // A transport failure produces no payload, but the page still needs its
    // signal so it can leave the pending state and show lastError.
    void failKind(RequestKind kind) {
        switch (kind) {
        case RequestKind::Dock:
            emit dockSnapshotChanged({});
            break;
        case RequestKind::Appearance:
            emit appearanceSnapshotChanged({});
            break;
        case RequestKind::Launcher:
            emit launcherSnapshotChanged({});
            break;
        case RequestKind::Shortcuts:
            emit shortcutsSnapshotChanged({});
            break;
        case RequestKind::Integration:
            startIntegrationProbe(integrationSnapshotFromReply({}));
            break;
        case RequestKind::GlassDebug:
            emit glassDebugSnapshotChanged(glassDebugSpecs(), glassPresetStyle());
            break;
        case RequestKind::ApplySystemAppearance:
            emit systemAppearanceApplied(false);
            break;
        }
    }

    void setLastError(const QString &error) {
        if (m_lastError == error)
            return;
        m_lastError = error;
        emit lastErrorChanged();
    }

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
};

namespace {

// Which QML tree this window runs. A development session must show the checkout
// the Shell in front of the user was started from -- the point of `kosctl dev`
// is to see source edits without reinstalling, and the QML half of Settings is
// the only half that can be iterated on that way (the binary is installed by
// `kosctl install` and is not rebuilt by `dev`). The copy installed beside the
// binary stays the answer for the service session. The compile-time tree is
// last: a binary built in a checkout has no copy next to it, an installed one
// has no checkout to point at.
struct SettingsEntry {
    QString qmlPath;
    // Non-empty only when qmlPath lies in a checkout: the root whose edits are
    // watched while the window is open. Empty means "load once, never reload",
    // which is every case the user is not developing against.
    QString checkoutRoot;
    // Named in the log line, which is the only thing that tells the three trees
    // apart from the outside -- they render identically, so a wrong choice shows
    // up as nothing at all.
    QString source;
};

SettingsEntry chooseSettingsEntry(bool developmentSession, const QString &sessionShellDir)
{
    SettingsEntry entry;
    if (developmentSession && !sessionShellDir.isEmpty()) {
        // `KOS_SHELL_DIR` names the Shell directory, so the checkout is one
        // level up from it and the pages sit in `apps/settings`. Derived from
        // the session rather than from SETTINGS_QML_DIR, so the window runs the
        // same tree as the Shell it is editing even when the two were built from
        // different paths.
        const QString qmlPath = QDir::cleanPath(
            QDir(sessionShellDir).filePath(QStringLiteral("../apps/settings/main.qml")));
        if (QFileInfo::exists(qmlPath)) {
            entry.qmlPath = qmlPath;
            entry.checkoutRoot = QDir::cleanPath(
                QDir(sessionShellDir).filePath(QStringLiteral("..")));
            entry.source = QStringLiteral("session checkout");
            return entry;
        }
    }

    // Cleaned so the logged path is the one a reader can paste into a shell:
    // `~/.local/bin/../share/...` is what the join produces, not what exists.
    const QString installedCopy = QDir::cleanPath(
        QDir(QCoreApplication::applicationDirPath()).filePath(
            QStringLiteral("../share/kos/settings/main.qml")));
    if (QFileInfo::exists(installedCopy)) {
        entry.qmlPath = installedCopy;
        entry.source = QStringLiteral("installed copy");
        return entry;
    }

    entry.qmlPath = QDir::cleanPath(QDir(QStringLiteral(SETTINGS_QML_DIR)).filePath(
        QStringLiteral("main.qml")));
    entry.source = QStringLiteral("build tree");
    return entry;
}

// Rebuilds the window when the checkout it was loaded from changes. Two rules
// keep this from being a way to lose the window: the reload is debounced,
// because one editor save is not one event (a write plus a rename), and the new
// text is compiled before anything is torn down, so a file that does not parse
// reports its errors and leaves the current UI on screen.
class SettingsQmlReloader final : public QObject {
public:
    SettingsQmlReloader(QQmlApplicationEngine *engine, const QUrl &entryPoint,
                        const QString &checkoutRoot, QObject *parent = nullptr)
        : QObject(parent), m_engine(engine), m_entryPoint(entryPoint) {
        // Only a checkout is watched. The installed copy is a destination, not
        // an edit surface: it changes when someone installs, and rebuilding the
        // window under a running user at that moment would be a surprise rather
        // than a feature -- with the shell's own copy the same `kosctl install`
        // is explicitly kept from hot-reloading anything.
        if (checkoutRoot.isEmpty())
            return;

        const QString pages = QFileInfo(entryPoint.toLocalFile()).absolutePath();
        if (!pages.isEmpty())
            m_directories.append(pages);
        // The pages import the shared tree by relative path, so both halves of
        // the window are part of the same edit loop. Only the directory itself
        // is listed here; qmlFiles() walks it.
        const QString shared = QDir(checkoutRoot).filePath(QStringLiteral("shared/qml"));
        if (QFileInfo(shared).isDir())
            m_directories.append(shared);
    }

    void start() {
        if (m_directories.isEmpty())
            return;

        m_debounce.setSingleShot(true);
        m_debounce.setInterval(300);
        connect(&m_debounce, &QTimer::timeout, this, [this] { reload(); });
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this,
                [this](const QString &) { m_debounce.start(); });
        connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this,
                [this](const QString &) {
                    refreshWatches();
                    m_debounce.start();
                });
        refreshWatches();
    }

private:
    // Both suffixes matter: the pages also import plain .mjs helpers (the
    // Material colour implementation), and those are edited the same way.
    static QStringList qmlFiles(const QString &directory) {
        QStringList files;
        QDirIterator iterator(directory,
                              {QStringLiteral("*.qml"), QStringLiteral("*.mjs")},
                              QDir::Files, QDirIterator::Subdirectories);
        while (iterator.hasNext())
            files.append(iterator.next());
        return files;
    }

    // Watches are per path, not per directory, so they have to be re-listed
    // after every change: an editor that saves by writing a new file over the
    // old one drops the watch on the old inode.
    void refreshWatches() {
        QStringList missingFiles;
        QStringList missingDirectories;
        for (const QString &directory : m_directories) {
            if (!QFileInfo(directory).isDir())
                continue;
            if (!m_watcher.directories().contains(directory))
                missingDirectories.append(directory);
            for (const QString &file : qmlFiles(directory)) {
                if (!m_watcher.files().contains(file))
                    missingFiles.append(file);
            }
        }
        if (!missingDirectories.isEmpty())
            m_watcher.addPaths(missingDirectories);
        if (!missingFiles.isEmpty())
            m_watcher.addPaths(missingFiles);
    }

    // Compiled on a throwaway engine on purpose: the live one caches compiled
    // QML by URL, so asking it about the file it already loaded answers from the
    // cache -- it would pass text that no longer compiles, and the reload that
    // followed would tear the window down. A fresh engine reads the file from
    // disk, which is the whole question here.
    bool compiles() {
        QQmlEngine validator;
        validator.setImportPathList(m_engine->importPathList());
        QQmlComponent component(&validator, m_entryPoint);
        if (!component.isError())
            return true;
        qWarning().noquote()
            << "kos-settings: QML changed but does not compile, keeping the window"
               " as it is:"
            << component.errorString().trimmed();
        return false;
    }

    void reload() {
        if (!compiles())
            return;

        const QList<QObject *> roots = m_engine->rootObjects();
        for (QObject *root : roots)
            delete root;
        m_engine->clearComponentCache();
        m_engine->load(m_entryPoint);
        if (m_engine->rootObjects().isEmpty()) {
            // Only reachable for text that compiles and still fails to build its
            // root object. Say so instead of leaving an empty screen behind: the
            // watcher is still live, so the next change that works brings the
            // window back.
            qWarning().noquote()
                << "kos-settings: reload failed, the window is gone until the next"
                   " change that loads";
            return;
        }
        qInfo().noquote() << "kos-settings: reloaded" << m_entryPoint.toLocalFile();
        refreshWatches();
    }

    QQmlApplicationEngine *m_engine = nullptr;
    QUrl m_entryPoint;
    QStringList m_directories;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};

} // namespace

int main(int argc, char *argv[]) {
    QGuiApplication application(argc, argv);
    // Keep this window out of the Shell's KWin rules. This must match the
    // installed desktop entry basename: kos-settings.desktop.
    application.setApplicationName(QStringLiteral("kos-settings"));
    application.setApplicationDisplayName(QStringLiteral(""));
    application.setDesktopFileName(QStringLiteral("kos-settings"));
    application.setOrganizationName(QStringLiteral("Quickshell"));

    SettingsBridge bridge;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("settingsBridge"), &bridge);

    const SettingsEntry entry = chooseSettingsEntry(bridge.isDevelopmentSession(),
                                                    bridge.sessionShellDir());
    // Recorded before the engine loads anything, so the banner and the reloader
    // cannot disagree about which tree the window is running.
    bridge.setSourceTreeEntry(!entry.checkoutRoot.isEmpty());
    if (entry.qmlPath.isEmpty()) {
        qWarning() << "kos-settings: no QML entry point found; looked beside the binary"
                      " and in" << QStringLiteral(SETTINGS_QML_DIR);
        return 1;
    }
    qInfo().noquote() << "kos-settings: loading QML from" << entry.qmlPath
                      << QStringLiteral("(%1%2)").arg(
                             entry.source,
                             entry.checkoutRoot.isEmpty()
                                 ? QString()
                                 : QStringLiteral(", reloads on change"));
    const QUrl entrypoint = QUrl::fromLocalFile(entry.qmlPath);
    engine.load(entrypoint);
    if (engine.rootObjects().isEmpty())
        return 1;

    // Inert unless the QML came from a checkout, which is the only case where
    // there is something to watch.
    SettingsQmlReloader reloader(&engine, entrypoint, entry.checkoutRoot);
    reloader.start();
    // --smoke-test is the build-side check that the settings window loads:
    // run one event loop turn (as ApplicationRunner does for the apps) and
    // exit, so CI can prove main.qml instantiates without a display.
    if (application.arguments().contains(QStringLiteral("--smoke-test")))
        QTimer::singleShot(250, &application, &QCoreApplication::quit);
    return application.exec();
}

#include "main.moc"
