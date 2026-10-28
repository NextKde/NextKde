# Canonical nextkdeAppDemo controls, isolated from the legacy Kos.Ui module.
set_source_files_properties(foundation/AppTheme.qml i18n/I18n.qml
    controls/ControlForm.qml controls/LiquidStyle.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
qt_add_qml_module(kos_demo_ui URI Kos.Demo VERSION 1.0 STATIC
    PLUGIN_TARGET kos_demo_ui_plugin RESOURCE_PREFIX /qt/qml
    OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/Kos/Demo
    QML_FILES
        foundation/AppTheme.qml
        foundation/SettingsGroup.qml
        foundation/SettingsItem.qml
        foundation/KosToolTip.qml
        foundation/SettingsAppearancePreview.qml
        i18n/I18n.qml
        controls/ControlForm.qml
        controls/LiquidStyle.qml
        controls/LiquidBackdrop.qml
        controls/LiquidSurface.qml
        controls/LiquidOuterShadow.qml
        controls/VectorIcon.qml
        controls/LiquidActionButton.qml
        controls/LiquidActionButtonGroup.qml
        controls/LiquidTextField.qml
        controls/LiquidSegmentedControl.qml
        controls/LiquidGlassSwitch.qml
        controls/LiquidSlider.qml
        controls/LiquidSelect.qml
    RESOURCES
        i18n/ZhCatalog.mjs
        i18n/SystemLanguage.mjs
        i18n/qmldir
        controls/shaders/liquid_convex.frag.qsb
        controls/shaders/liquid_convex.frag
        controls/shaders/liquid_convex.vert.qsb
        controls/shaders/liquid_convex.vert
        controls/shaders/liquid_diffuse.frag.qsb
        controls/shaders/liquid_diffuse.frag
        controls/shaders/liquid_diffuse.vert.qsb
        controls/shaders/liquid_diffuse.vert
        controls/shaders/liquid_highlight_full_extended.frag.qsb
        controls/shaders/liquid_highlight_full_extended.frag
        controls/shaders/liquid_highlight_full_extended_fallback.frag.qsb
        controls/shaders/liquid_highlight_full_extended_fallback.frag
        controls/shaders/liquid_highlight_tint.vert.qsb
        controls/shaders/liquid_highlight_tint.vert
        controls/shaders/liquid_highlight_topbottom_wider.frag.qsb
        controls/shaders/liquid_highlight_topbottom_wider.frag
        controls/shaders/liquid_highlight_topbottom_wider_fallback.frag.qsb
        controls/shaders/liquid_highlight_topbottom_wider_fallback.frag
        controls/shaders/liquid_shadow.frag.qsb
        controls/shaders/liquid_shadow.frag
        controls/shaders/liquid_shadow.vert.qsb
        controls/shaders/liquid_shadow.vert
        controls/shaders/liquid_surface.frag.qsb
        controls/shaders/liquid_surface.frag
        controls/shaders/liquid_surface.vert.qsb
        controls/shaders/liquid_surface.vert
        foundation/qmldir
)
target_link_libraries(kos_demo_ui PUBLIC Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2)
