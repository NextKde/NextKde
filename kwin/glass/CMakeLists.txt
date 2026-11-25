cmake_minimum_required(VERSION 3.16)

project(kwin_glass VERSION 2.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# KWin's package imports Qt Quick; make the Qt 6 versionless macros resolvable
# before that dependency is evaluated.
set(QT_MAJOR_VERSION 6)
set(QT_DEFAULT_MAJOR_VERSION 6)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Choose Release or Debug" FORCE)
endif()

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${ECM_MODULE_PATH} ${ECM_KDE_MODULE_DIR})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Gui Widgets Qml Quick)
find_package(KWin QUIET COMPONENTS kwineffects)
# Optional: the settings page. Building the effect never depends on it; a
# system without KCMUtils or KWin's Effects D-Bus interface still gets glass.
find_package(KF6 6.0 QUIET COMPONENTS KCMUtils I18n)
find_package(KWinDBusInterface QUIET)

if(NOT KWin_FOUND OR NOT TARGET KWin::kwin)
    message(FATAL_ERROR "A supported KWin development package is required")
endif()
if(KWin_VERSION VERSION_LESS 6.4)
    message(FATAL_ERROR "Glass requires KWin 6.4 or newer (found ${KWin_VERSION})")
endif()

add_subdirectory(src)

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/po" AND COMMAND ki18n_install)
    ki18n_install(po)
endif()
