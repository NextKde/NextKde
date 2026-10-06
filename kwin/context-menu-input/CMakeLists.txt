cmake_minimum_required(VERSION 3.21)

project(kos_context_menu_input LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
# KWin's CMake package loads QtQuick transitively. Set the default major
# before that happens, otherwise Qt's versionless helper picks no Qt version.
set(QT_MAJOR_VERSION 6)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${ECM_MODULE_PATH} ${ECM_KDE_MODULE_DIR})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

# KWin::kwin exports these public Qt dependencies, so declare them before
# importing the KWin target even though this probe directly uses only Core and
# DBus.
find_package(Qt6 6.6 REQUIRED COMPONENTS Core DBus Gui Widgets OpenGL Network Xml)
find_package(KWin REQUIRED COMPONENTS kwineffects)

add_library(kos_context_menu_input MODULE
    contextmenuinputeffect.cpp
    main.cpp
)

target_link_libraries(kos_context_menu_input PRIVATE
    Qt6::Core
    Qt6::DBus
    KWin::kwin
)

install(TARGETS kos_context_menu_input
    DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin/effects/plugins
    COMPONENT kwin_plugins)
