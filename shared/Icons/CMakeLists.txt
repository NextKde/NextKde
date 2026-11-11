set_source_files_properties(IconRegistry.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
qt_add_qml_module(kos_icons
    URI Kos.Icons VERSION 1.0 STATIC
    PLUGIN_TARGET kos_icons_plugin
    OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/Kos/Icons
    RESOURCE_PREFIX /qt/qml
    QML_FILES BatteryIcon.qml SignalIcon.qml VolumeIcon.qml Icon.qml IconRegistry.qml IconMap.js
    RESOURCES NextKdeIcons.ttf LICENSE.Framework7 provenance.json)
add_library(Kos::Icons ALIAS kos_icons)
add_library(Kos::IconsPlugin ALIAS kos_icons_plugin)
target_link_libraries(kos_icons PUBLIC Qt6::Quick)
install(FILES LICENSE.Framework7 provenance.json DESTINATION share/licenses/kos-icons)
