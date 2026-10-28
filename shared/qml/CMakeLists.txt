set_source_files_properties(
    foundation/AppTheme.qml
    i18n/I18n.qml
    controls/ControlForm.qml
    controls/LiquidStyle.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(kos_ui
    URI Kos.Ui
    VERSION 1.0
    STATIC
    PLUGIN_TARGET kos_ui_plugin
    RESOURCE_PREFIX /qt/qml
    QML_FILES
        i18n/I18n.qml
        foundation/AppTheme.qml
        foundation/KosSidebar.qml
        foundation/KosSidebarToggle.qml
        foundation/KosSidebarGlyph.qml
        foundation/KosCheckBox.qml
        foundation/KosComboBox.qml
        foundation/KosTextArea.qml
        foundation/KosApplicationWindow.qml
        foundation/KosWindowControls.qml
        foundation/KosWindowResizeHandles.qml
        foundation/KosButton.qml
        foundation/KosCard.qml
        foundation/KosWorkspaceDialog.qml
        foundation/KosItemDelegate.qml
        foundation/KosDialog.qml
        foundation/KosEmptyState.qml
        foundation/KosNavigationButton.qml
        foundation/KosPageCache.qml
        foundation/KosPageMotion.qml
        foundation/KosRoundButton.qml
        foundation/KosSettingsDialog.qml
        foundation/KosSlider.qml
        foundation/KosSurface.qml
        foundation/KosSwitch.qml
        foundation/KosTextField.qml
        foundation/KosToolButton.qml
        foundation/KosLyricLine.qml
        foundation/KosKineticScroll.qml
        foundation/KosKineticScrollPhysics.mjs
        foundation/PageCachePolicy.js
        controls/ControlForm.qml
        controls/LiquidTextField.qml
        controls/LiquidSegmentedControl.qml
        controls/LiquidStyle.qml
        controls/LiquidBackdrop.qml
        controls/LiquidSurface.qml
        controls/LiquidGlassNumber.qml
        controls/LiquidCompactSurface.qml
        controls/SelectionHighlight.qml
    RESOURCES
        controls/shaders/liquid_number.vert.qsb
        controls/shaders/liquid_number.frag.qsb
        i18n/qmldir
        i18n/ZhCatalog.mjs
        i18n/SystemLanguage.mjs
        controls/shaders/liquid_compact_surface.frag.qsb
        controls/shaders/liquid_compact_surface.vert.qsb
        controls/shaders/liquid_convex.frag.qsb
        controls/shaders/liquid_convex.vert.qsb
        controls/shaders/liquid_diffuse.frag.qsb
        controls/shaders/liquid_diffuse.vert.qsb
        controls/shaders/liquid_highlight_full_extended.frag.qsb
        controls/shaders/liquid_highlight_full_extended_fallback.frag.qsb
        controls/shaders/liquid_highlight_tint.vert.qsb
        controls/shaders/liquid_highlight_topbottom_wider.frag.qsb
        controls/shaders/liquid_highlight_topbottom_wider_fallback.frag.qsb
        controls/shaders/liquid_surface.vert.qsb
        controls/shaders/liquid_surface.frag.qsb
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
