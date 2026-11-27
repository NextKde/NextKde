pragma Singleton
import QtQuick
import qs.desktop.modules.common
import qs.desktop.modules.dock
import qs.desktop.modules.weather
import "../../../Kos/Ui"
import "../../../shared/qml/i18n"

// Host-provided read-only data snapshots (R1), palette/appearance context, and
// reverse action dispatcher (R11) for package-backed desktop widgets.
//
// Widgets run in-process under a user-audited trust model (no runtime sandbox
// or per-capability permission gate). This singleton is exposed to every live
// widget instance through a read-only `host` proxy so any installed package can
// read live snapshots (`host.clock`, `host.media`, `host.weather`,
// `host.system`, `host.activity`, `host.pim`) and call `host.invokeAction(...)`
// without writing a per-package *WidgetDataService.qml or importing private
// Shell singletons.
QtObject {
    id: host

    // ── SDK version & capability probing ───────────────────────────────────

    readonly property int sdkVersion: 1
    readonly property int apiRevision: 1
    readonly property string locale: String(I18n.language || "en")
    readonly property var availableSources: ["clock", "media", "weather", "system", "activity", "pim"]
    readonly property var supportedActions: [
        "media.previous",
        "media.toggle-play-pause",
        "media.next",
        "media.seek",
        "media.raise-player",
        "app.open-weather",
        "app.open-calendar"
    ]

    function hasAction(actionName) {
        return supportedActions.indexOf(String(actionName ?? "")) >= 0
    }

    // ── Shared reactive ticks & revisions ─────────────────────────────────

    property date now: new Date()
    property int mediaArtworkRevision: 0
    property int _mediaPositionRevision: 0

    readonly property url _activeMediaArtworkUrl: {
        const metaRev = MediaService.metadataRevision
        return MediaService.activePlayer?.trackArtUrl ?? ""
    }

    // Shared asynchronous palette extractor for the active MPRIS track cover.
    // transitionDuration is 0 here so snapshots emit settled hex colors once
    // per track change while card shells handle smooth ColorAnimation.
    property ArtworkColorSource _mediaArtworkColors: ArtworkColorSource {
        source: host._activeMediaArtworkUrl
        transitionDuration: 0
        onReadyChanged: host.mediaArtworkRevision++
        onPrimaryChanged: host.mediaArtworkRevision++
        onSecondaryChanged: host.mediaArtworkRevision++
    }

    property Timer _clockTimer: Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: host.now = new Date()
    }

    property Timer _mediaPositionTimer: Timer {
        interval: 1000
        repeat: true
        running: Boolean(MediaService.activePlayer && MediaService.activePlayer.isPlaying)
        onTriggered: {
            if (MediaService.activePlayer && MediaService.activePlayer.positionSupported)
                MediaService.activePlayer.positionChanged()
            host._mediaPositionRevision++
        }
    }

    // ── Appearance context (including Material dynamic palette) ───────────
    // Every widget receives this object via `appearance` (in both live desktop
    // instances and gallery previews). Material widgets select an outer shape
    // via `surfaceShape` (host-owned background color, opacity and blur) and
    // read `appearance.palette` to color foreground elements consistently.

    readonly property var widgetAppearance: {
        const colorRev = AppearanceTokens.colorRevision
        const c = AppearanceTokens.colors
        return {
            isDark: AppearanceTokens.isDarkTheme,
            foreground: AppearanceTokens.surface.widgetForeground,
            transparent: AppearanceConfigService.widgetStyle === "glass"
                && !AppearanceTokens.surface.paintInQml,
            style: AppearanceTokens.isMaterial ? "material" : "macos",
            locale: host.locale,
            palette: {
                primary: String(c.primary),
                onPrimary: String(c.primaryForeground),
                primaryContainer: String(c.primaryContainer),
                onPrimaryContainer: String(c.primaryContainerForeground),
                secondary: String(c.secondary),
                onSecondary: String(c.secondaryForeground),
                secondaryContainer: String(c.secondaryContainer),
                onSecondaryContainer: String(c.secondaryContainerForeground),
                tertiary: String(c.tertiary),
                tertiaryContainer: String(c.tertiaryContainer),
                onTertiaryContainer: String(c.tertiaryContainerForeground),
                background: String(c.background),
                surface: String(c.surface),
                surfaceContainerLow: String(c.surfaceContainerLow),
                surfaceContainer: String(c.surfaceContainer),
                surfaceContainerHigh: String(c.surfaceContainerHigh),
                surfaceContainerHighest: String(c.surfaceContainerHighest),
                layer0: String(c.layer0),
                layer1: String(c.layer1),
                layer2: String(c.layer2),
                layer3: String(c.layer3),
                layer4: String(c.layer4),
                onSurface: String(c.surfaceForeground),
                onSurfaceVariant: String(c.surfaceVariantForeground),
                outline: String(c.outline),
                outlineVariant: String(c.outlineVariant),
                error: String(c.error),
                scrim: String(c.scrim)
            }
        }
    }

    // ── R1: Reactive read-only data snapshots ─────────────────────────────
    // Every snapshot is a plain serializable object with an explicit `status`
    // ("ready" | "idle" | "loading" | "unavailable").

    readonly property var clock: clockSnapshot()
    readonly property var media: mediaNowPlayingSnapshot()
    readonly property var weather: weatherCurrentSnapshot()
    readonly property var system: systemMetricsSnapshot()
    readonly property var activity: activityUsageSnapshot()
    readonly property var pim: pimSnapshot()

    function clockSnapshot() {
        const d = host.now
        return {
            status: "ready",
            timestampMs: d.getTime(),
            isoDate: Qt.formatDate(d, "yyyy-MM-dd"),
            time24h: Qt.formatTime(d, "HH:mm"),
            time12h: Qt.formatTime(d, "h:mm AP"),
            hours: d.getHours(),
            minutes: d.getMinutes(),
            seconds: d.getSeconds(),
            weekday: d.getDay()
        }
    }

    function mediaNowPlayingSnapshot() {
        const metaRev = MediaService.metadataRevision
        const artRev = host.mediaArtworkRevision
        const posRev = host._mediaPositionRevision
        const player = MediaService.activePlayer
        if (!player) {
            return {
                status: "idle",
                hasPlayer: false,
                playing: false,
                loading: false,
                title: "",
                artist: "",
                album: "",
                artworkUrl: "",
                artworkColors: { ready: false, primary: "", secondary: "" },
                positionSeconds: 0,
                lengthSeconds: 0,
                canPrevious: false,
                canTogglePlayPause: false,
                canNext: false,
                canSeek: false,
                canRaise: false,
                lyric: ""
            }
        }
        const lengthSeconds = (player.lengthSupported && player.length > 0)
            ? Math.floor(player.length) : 0
        const positionSeconds = Math.max(0, Math.floor(player.position ?? 0))
        const artUrl = String(player.trackArtUrl ?? "")
        const colorsReady = artUrl.length > 0 && Boolean(host._mediaArtworkColors.ready)
        return {
            status: "ready",
            hasPlayer: true,
            playing: Boolean(player.isPlaying),
            loading: Boolean(MediaService.loading),
            title: String(player.trackTitle ?? ""),
            artist: String(player.trackArtist ?? ""),
            album: String(player.trackAlbum ?? ""),
            artworkUrl: artUrl,
            artworkColors: {
                ready: colorsReady,
                primary: colorsReady ? String(host._mediaArtworkColors.primary) : "",
                secondary: colorsReady ? String(host._mediaArtworkColors.secondary) : ""
            },
            positionSeconds: positionSeconds,
            lengthSeconds: lengthSeconds,
            canPrevious: Boolean(player.canGoPrevious),
            canTogglePlayPause: Boolean(player.canTogglePlaying),
            canNext: Boolean(player.canGoNext),
            canSeek: Boolean(player.canSeek && player.positionSupported),
            canRaise: Boolean(player.canRaise || player.desktopEntry),
            lyric: String(MediaService.currentLyric ?? "")
        }
    }

    function weatherCurrentSnapshot() {
        const status = WeatherService.ready ? "ready"
            : (WeatherService.status === "loading" ? "loading" : "unavailable")
        const forecast = Array.isArray(WeatherService.forecastDays)
            ? WeatherService.forecastDays.slice(0, 7).map((day, idx) => ({
                date: String(day?.date ?? ""),
                label: String(WeatherService.forecastLabel
                    ? WeatherService.forecastLabel(day?.date, idx) : ""),
                code: Number(day?.code ?? -1),
                symbol: String(WeatherService.conditionSymbol
                    ? WeatherService.conditionSymbol(day?.code ?? -1, true) : ""),
                high: day?.high ?? null,
                low: day?.low ?? null
            }))
            : []
        return {
            status: status,
            available: Boolean(WeatherService.available),
            loading: Boolean(WeatherService.loading),
            locationId: String(WeatherService.location?.id ?? ""),
            locationName: String(WeatherService.location?.name ?? ""),
            temperature: WeatherService.current?.temperature ?? null,
            temperatureText: String(WeatherService.temperature ?? ""),
            weatherCode: Number(WeatherService.weatherCode ?? -1),
            isDay: WeatherService.isDay !== false,
            conditionSymbol: String(WeatherService.conditionSymbol
                ? WeatherService.conditionSymbol(WeatherService.weatherCode, WeatherService.isDay) : ""),
            conditionText: String(WeatherService.conditionText
                ? WeatherService.conditionText(WeatherService.weatherCode) : ""),
            humidity: String(WeatherService.humidity ?? ""),
            windSpeed: String(WeatherService.windSpeed ?? ""),
            units: String(WeatherService.units ?? "metric"),
            apparentTemperature: String(WeatherService.apparentTemperature ?? ""),
            sunriseTime: String(WeatherService.sunriseTime ?? ""),
            sunsetTime: String(WeatherService.sunsetTime ?? ""),
            errorMessage: String(WeatherService.errorMessage ?? ""),
            sourceMessage: String(WeatherService.sourceMessage ?? ""),
            daily: Array.isArray(WeatherService.daily) ? WeatherService.daily.slice(0, 7) : [],
            forecastDays: forecast
        }
    }

    function systemMetricsSnapshot() {
        return {
            status: MetricsService.ready ? "ready" : "unavailable",
            cpuUsage: Number(MetricsService.cpuUsage ?? 0),
            cpuFrequencyMhz: Number(MetricsService.cpuFrequencyMhz ?? 0),
            memoryUsedBytes: Number(MetricsService.memoryUsedBytes ?? 0),
            memoryTotalBytes: Number(MetricsService.memoryTotalBytes ?? 0),
            diskUsedBytes: Number(MetricsService.diskUsedBytes ?? 0),
            diskTotalBytes: Number(MetricsService.diskTotalBytes ?? 0),
            temperatureMilliC: Number(MetricsService.currentMilliC ?? -1),
            temperatureMaxMilliC: Number(MetricsService.maximum5MinuteMilliC ?? -1),
            cpuHistory: Array.isArray(MetricsService.cpuHistoryValues)
                ? MetricsService.cpuHistoryValues.slice() : [],
            memoryHistory: Array.isArray(MetricsService.memoryHistoryValues)
                ? MetricsService.memoryHistoryValues.slice() : [],
            frequencyHistory: Array.isArray(MetricsService.frequencyHistoryValues)
                ? MetricsService.frequencyHistoryValues.slice() : []
        }
    }

    function activityUsageSnapshot() {
        const todayKey = ActivityUsageService.dayKey(host.now.getTime())
        const apps = ActivityUsageService.todayApps().slice(0, 12).map(item => ({
            id: String(item?.id ?? ""),
            name: String(item?.name ?? item?.id ?? ""),
            icon: String(item?.icon ?? ""),
            seconds: Number(item?.seconds ?? 0)
        }))
        return {
            status: ActivityUsageService.ready ? "ready" : "unavailable",
            todayKey: todayKey,
            todayUptimeSeconds: Number(ActivityUsageService.uptimeByDay?.[todayKey] ?? 0),
            recentUptimeDays: ActivityUsageService.recentUptimeDays(60),
            todayApps: apps
        }
    }

    function pimSnapshot() {
        const rev = PimWidgetService.revision
        const state = String(PimWidgetService.state || "unavailable")
        const status = PimWidgetService.ready ? "ready"
            : (state === "loading" ? "loading" : "unavailable")
        return {
            status: status,
            available: Boolean(PimWidgetService.available),
            ready: Boolean(PimWidgetService.ready),
            cached: Boolean(PimWidgetService.cached),
            today: String(PimWidgetService.today ?? ""),
            errorMessage: String(PimWidgetService.errorMessage ?? ""),
            todayEvents: PimWidgetService.eventsForToday(20),
            pendingTodos: PimWidgetService.pendingTodos(50)
        }
    }

    // ── R11: Reverse action channel (Widget -> Host) ──────────────────────
    // Synchronous structured result:
    //   { ok: bool, code: string, message: string }
    // Codes:
    //   "ok"                — dispatched to host service
    //   "unknown-action"    — action name not in the host enum
    //   "unavailable"       — target player/service/app is currently absent
    //   "invalid-argument"  — payload failed host validation
    function invokeAction(actionName, payload) {
        const name = String(actionName ?? "")
        switch (name) {
        case "media.previous":
            if (!MediaService.activePlayer || !MediaService.activePlayer.canGoPrevious)
                return { ok: false, code: "unavailable", message: "No controllable player for previous track" }
            MediaService.previous()
            return { ok: true, code: "ok", message: "" }

        case "media.toggle-play-pause":
            if (!MediaService.activePlayer || !MediaService.activePlayer.canTogglePlaying)
                return { ok: false, code: "unavailable", message: "No controllable player for play/pause" }
            MediaService.togglePlayPause()
            return { ok: true, code: "ok", message: "" }

        case "media.next":
            if (!MediaService.activePlayer || !MediaService.activePlayer.canGoNext)
                return { ok: false, code: "unavailable", message: "No controllable player for next track" }
            MediaService.next()
            return { ok: true, code: "ok", message: "" }

        case "media.seek": {
            const player = MediaService.activePlayer
            if (!player || !player.canSeek || !player.positionSupported
                    || !player.lengthSupported || !(player.length > 0))
                return { ok: false, code: "unavailable", message: "Active player does not support seeking" }
            const pos = Number(payload?.positionSeconds)
            if (!Number.isFinite(pos) || pos < 0)
                return { ok: false, code: "invalid-argument", message: "positionSeconds must be a non-negative number" }
            player.position = Math.max(0, Math.min(player.length, pos))
            player.positionChanged()
            host._mediaPositionRevision++
            return { ok: true, code: "ok", message: "" }
        }

        case "media.raise-player":
            return _raiseActiveMediaPlayer()

        case "app.open-weather": {
            const opts = _sanitizeOpenWeatherPayload(payload)
            if (opts === null)
                return { ok: false, code: "invalid-argument", message: "Invalid weather open payload" }
            IndependentAppWidgetService.open("weather", opts)
            return { ok: true, code: "ok", message: "" }
        }

        case "app.open-calendar": {
            const opts = _sanitizeOpenCalendarPayload(payload)
            if (opts === null)
                return { ok: false, code: "invalid-argument", message: "Invalid calendar open payload" }
            IndependentAppWidgetService.open("calendar", opts)
            return { ok: true, code: "ok", message: "" }
        }
        }
        return { ok: false, code: "unknown-action", message: "Unsupported host action: " + name }
    }

    function _raiseActiveMediaPlayer() {
        const player = MediaService.activePlayer
        if (!player) {
            if (AppActionService.launchById("listenfree", []))
                return { ok: true, code: "ok", message: "" }
            return { ok: false, code: "unavailable", message: "No active media player" }
        }
        if (player.canRaise) {
            player.raise()
            return { ok: true, code: "ok", message: "" }
        }
        const windows = player.desktopEntry
            ? WindowService.windowsForApp(player.desktopEntry) : []
        if (windows.length > 0) {
            WindowService.activateWindow(windows[0].windowId)
            return { ok: true, code: "ok", message: "" }
        }
        if (player.desktopEntry && AppActionService.launchById(player.desktopEntry, [])) {
            return { ok: true, code: "ok", message: "" }
        }
        return { ok: false, code: "unavailable", message: "Active player window cannot be raised" }
    }

    function _sanitizeOpenWeatherPayload(payload) {
        if (payload === undefined || payload === null) return ({})
        if (typeof payload !== "object" || Array.isArray(payload)) return null
        const out = ({})
        if (payload.location !== undefined) {
            if (typeof payload.location !== "string" || payload.location.length > 128) return null
            out.location = payload.location
        }
        return out
    }

    function _sanitizeOpenCalendarPayload(payload) {
        if (payload === undefined || payload === null) return ({})
        if (typeof payload !== "object" || Array.isArray(payload)) return null
        const out = ({})
        if (payload.view !== undefined) {
            if (["day", "week", "month", "year", "todo", "today", "reminders"].indexOf(payload.view) < 0)
                return null
            out.view = payload.view
        }
        if (payload.item !== undefined) {
            if (typeof payload.item !== "string" || payload.item.length > 128) return null
            out.item = payload.item
        }
        return out
    }
}
