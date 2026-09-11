set_source_files_properties(
    foundation/AppTheme.qml
    colorize/ColorScheme.qml
    colorize/WallpaperColorSource.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(kos_ui
    URI Kos.Ui
    VERSION 1.0
    STATIC
    PLUGIN_TARGET kos_ui_plugin
    RESOURCE_PREFIX /qt/qml
    QML_FILES
        foundation/AppTheme.qml
        foundation/KosApplicationWindow.qml
        foundation/KosButton.qml
        foundation/KosCard.qml
        foundation/KosEmptyState.qml
        foundation/KosNavigationButton.qml
        foundation/KosPageCache.qml
        foundation/KosRoundButton.qml
        foundation/KosSettingsDialog.qml
        foundation/KosSlider.qml
        foundation/KosSurface.qml
        foundation/KosSwitch.qml
        foundation/KosToolButton.qml
        foundation/PageCachePolicy.js
        controls/LiquidTextField.qml
        controls/LiquidSegmentedControl.qml
        colorize/ArtworkColorSource.qml
        colorize/Cam16Hct.mjs
        colorize/ColorScheme.qml
        colorize/MaterialColorScheme.mjs
        colorize/WallpaperColorSource.qml
)

add_library(Kos::Ui ALIAS kos_ui)
add_library(Kos::UiPlugin ALIAS kos_ui_plugin)

target_link_libraries(kos_ui PUBLIC
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
)
