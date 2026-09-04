qt_add_qml_module(kos_pim_client
    URI Kos.Pim
    VERSION 1.0
    STATIC
    PLUGIN_TARGET kos_pim_client_plugin
    RESOURCE_PREFIX /qt/qml
    SOURCES
        src/PimClient.cpp
        src/PimClient.h
)

add_library(Kos::PimClient ALIAS kos_pim_client)
add_library(Kos::PimClientPlugin ALIAS kos_pim_client_plugin)

target_include_directories(kos_pim_client PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)

target_link_libraries(kos_pim_client PUBLIC
    Qt6::Core
    Qt6::DBus
    Qt6::Qml
)
