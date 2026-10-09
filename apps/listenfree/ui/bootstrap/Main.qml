import QtQuick
import QtQuick.Window
import QtQuick.Effects

Window {
    id: window
    flags: Qt.Window | Qt.FramelessWindowHint
    width: 1040
    height: 709
    minimumWidth: 1040
    minimumHeight: 709
    visible: true
    color: "transparent"
    title: "ListenFree"
    readonly property real cornerRadius: visibility === Window.Maximized || visibility === Window.FullScreen ? 0 : AppTheme.normalWindowCornerRadius
    Rectangle {
        id: windowMask
        anchors.fill: parent
        radius: window.cornerRadius
        color: "white"
        visible: false
        layer.enabled: true
    }

    // Keep modal popups out of a full-overlay ShaderEffect layer: Qt's modal
    // wheel hit test otherwise sees that layer instead of the popup beneath it.
    // Individual dimmers use the same window radius without a capture layer.
    Binding { target: AppTheme; property: "windowCornerRadius"; value: window.cornerRadius }
    AppFacade { id: facade }
    AppShell {
        id: appShell
        objectName: "appShell"
        anchors.fill: parent
        layer.enabled: window.cornerRadius > 0
        layer.effect: MultiEffect { maskEnabled: true; maskSource: windowMask; maskThresholdMin: .5; maskSpreadAtMin: 1 }
        catalog: backendCatalog
        facade: facade
        hostWindow: window
        sourceController: backendSourceController
        appController: backendAppController
        playerController: backendPlayerController
        libraryController: backendLibraryController
        playlistController: backendPlaylistController
        onlineController: backendOnlineController
        settingsController: backendSettingsController
        downloadController: backendDownloads
    }
}
