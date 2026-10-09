pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: cache
    property string route: "library/songs"
    property var pages: []
    property var visited: ({})
    property var recentRoutes: []
    property var pageStates: ({})
    property var artworkStates: ({})
    property var artworkOrder: []
    // Conservative backing estimate includes CPU pixels, texture and mipmaps.
    // This budget covers history owners; live pages have their own resources.
    property int artworkBudgetBytes: 24 * 1024 * 1024
    readonly property int retainedArtworkBytes: retainedBytes
    readonly property int retainedArtworkCount: retainedArtwork.count
    property int retainedBytes: 0
    property string displayedRoute: ""
    property Item transitionSourceItem: null
    property var settingsStore: typeof backendSettingsController !== "undefined" ? backendSettingsController : null
    readonly property bool remember: {
        if (!settingsStore) return true
        const revision = settingsStore.revision
        return settingsStore.value("list.rememberScrollPosition", true)
    }
    onRememberChanged: { if (!remember) { pageStates = ({}); artworkStates = ({}) }; retain() }
    onTransitionSourceItemChanged: retain()
    function isInside(page, source) {
        if (!page || !source) return false
        for (let item = source; item; item = item.parent) if (item === page) return true
        return false
    }
    function artworkFor(page) {
        const requests = [], seen = ({})
        function visit(item) {
            if (item.objectName === "coverSourceImage" && item.cache
                    && (item.status === Image.Loading || (item.status === Image.Ready
                        && (item.implicitWidth > 1 || item.implicitHeight > 1)))) {
                const source = String(item.source), size = item.sourceSize
                const key = source + "|" + size.width + "x" + size.height
                const pixels = Math.max(Math.max(1, size.width) * Math.max(1, size.height),
                    Math.ceil(item.implicitWidth) * Math.ceil(item.implicitHeight))
                if (!seen[key]) { seen[key] = true; requests.push({ source: source, width: size.width,
                    height: size.height, bytes: Math.ceil(pixels * 10) }) }
            }
            for (const child of item.children) visit(child)
        }
        visit(page)
        return requests
    }
    function retainArtwork(artwork) {
        const wanted = ({}), existing = ({})
        let bytes = 0
        for (const routeKey of artworkOrder) {
            const accepted = []
            for (const request of artwork[routeKey] || []) {
                const key = request.source + "|" + request.width + "x" + request.height
                if (!wanted[key] && bytes + request.bytes > artworkBudgetBytes) continue
                if (!wanted[key]) { wanted[key] = request; bytes += request.bytes }
                accepted.push(request)
            }
            if (accepted.length) artwork[routeKey] = accepted
            else delete artwork[routeKey]
        }
        retainedBytes = bytes
        for (let i = 0; i < retainedArtwork.count; ++i)
            existing[retainedArtwork.get(i).cacheKey] = true
        // Append before releasing owners, and keep unchanged Image instances.
        // Replacing a JS-array model would drop and reacquire every pixmap.
        for (const key of Object.keys(wanted)) if (!existing[key]) {
            const request = wanted[key]
            retainedArtwork.append({ cacheKey: key, artworkSource: request.source,
                pixelWidth: request.width, pixelHeight: request.height })
        }
        for (let i = retainedArtwork.count - 1; i >= 0; --i)
            if (!wanted[retainedArtwork.get(i).cacheKey]) retainedArtwork.remove(i)
    }
    function retain() {
        // Keep instant back navigation, while state outlives older visual trees.
        const recent = [route]
        if (remember) for (const key of recentRoutes) {
            if (key !== route) { recent.push(key); break }
        }
        const next = ({}), states = Object.assign({}, pageStates), artwork = Object.assign({}, artworkStates)
        for (const key of recent) next[key] = true
        // The current visual remains until restored covers have finished loading.
        if (displayedRoute) next[displayedRoute] = true
        for (let i = 0; i < pageLoaders.count; ++i) {
            const loader = pageLoaders.itemAt(i)
            if (loader && isInside(loader.item, transitionSourceItem)) next[loader.routeKey] = true
        }
        // Capture before changing Loader.active: its item is gone afterwards.
        for (let i = 0; i < pageLoaders.count; ++i) {
            const loader = pageLoaders.itemAt(i)
            if (remember && loader && loader.item && !next[loader.routeKey]) {
                if (typeof loader.item.saveNavigationState === "function") states[loader.routeKey] = loader.item.saveNavigationState()
                artwork[loader.routeKey] = artworkFor(loader.item)
                artworkOrder = [loader.routeKey].concat(artworkOrder.filter(key => key !== loader.routeKey))
            }
        }
        for (const key of Object.keys(next)) delete artwork[key]
        // Acquire Qt's existing pixmaps before unloading their visual owners.
        // These invisible Images have no layers/effects or rendered delegates.
        retainArtwork(artwork)
        artworkStates = artwork
        pageStates = states
        recentRoutes = recent
        visited = next
    }
    function coversLoading(item) {
        if (!item) return false
        if (item.objectName === "coverSourceImage" && item.status === Image.Loading) return true
        for (const child of item.children) if (coversLoading(child)) return true
        return false
    }
    function displayWhenReady() {
        for (let i = 0; i < pageLoaders.count; ++i) {
            const loader = pageLoaders.itemAt(i)
            if (!loader || loader.routeKey !== route || loader.status !== Loader.Ready) continue
            if (remember && pageStates[route] !== undefined && coversLoading(loader.item)) return
            displayedRoute = route
            displayTimer.stop()
            retain()
            return
        }
    }
    onRouteChanged: { retain(); displayTimer.restart() }
    onArtworkBudgetBytesChanged: retain()
    Component.onCompleted: { retain(); displayTimer.restart() }
    Timer { id: displayTimer; interval: 16; repeat: true; onTriggered: cache.displayWhenReady() }
    ListModel { id: retainedArtwork }
    Item {
        visible: false
        Repeater {
            model: retainedArtwork
            delegate: Image {
                required property string artworkSource
                required property int pixelWidth
                required property int pixelHeight
                objectName: "navigationRetainedArtwork"
                source: artworkSource
                sourceSize: Qt.size(pixelWidth, pixelHeight)
                // Crop mode is part of Qt's pixmap cache key, even when hidden.
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
    }
    Repeater {
        id: pageLoaders
        model: cache.pages
        delegate: Loader {
            required property var modelData
            readonly property string routeKey: modelData.route
            property bool readyForDisplay: false
            anchors.fill: parent
            active: routeKey===cache.route || routeKey===cache.displayedRoute || !!cache.visited[routeKey]
            sourceComponent: modelData.component
            visible: routeKey===cache.displayedRoute
            opacity: readyForDisplay || cache.pageStates[routeKey] === undefined ? 1 : 0
            enabled: visible && routeKey===cache.route && opacity > 0
            onStatusChanged: if (status !== Loader.Ready) readyForDisplay = false
            onLoaded: {
                const state = cache.pageStates[routeKey]
                if (cache.remember && state !== undefined && typeof item.restoreNavigationState === "function")
                    item.restoreNavigationState(state)
                readyForDisplay = true
                displayTimer.restart()
            }
        }
    }
}
