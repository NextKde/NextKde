cmake_minimum_required(VERSION 3.21)

project(kos_decoration LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(QT_MAJOR_VERSION 6)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${ECM_MODULE_PATH} ${ECM_KDE_MODULE_DIR})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui)
find_package(KF6 REQUIRED COMPONENTS CoreAddons)
# KDecoration3Config.cmake defines KDECORATION_PLUGIN_DIR, the subdirectory
# KWin scans for decoration plugins.
find_package(KDecoration3 REQUIRED)

add_library(kos_decoration MODULE
    kosdecoration.cpp
    main.cpp
    ../kos-bridge/windowappearance/contour.cpp
)

target_link_libraries(kos_decoration PRIVATE
    Qt6::Core
    Qt6::Gui
    KF6::CoreAddons
    KDecoration3::KDecoration
)

install(TARGETS kos_decoration
    DESTINATION ${KDE_INSTALL_PLUGINDIR}/${KDECORATION_PLUGIN_DIR}
    COMPONENT kwin_decoration)
