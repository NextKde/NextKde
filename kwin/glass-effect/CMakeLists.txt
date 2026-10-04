cmake_minimum_required(VERSION 3.16.0)

project(kwin_glass)
set(PROJECT_VERSION "1.6.3")
set(PROJECT_VERSION_MAJOR 0)

set(KF_MIN_VERSION "5.240.0")
set(QT_MIN_VERSION "6.6.0")
set(QT_MAJOR_VERSION 6)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CPACK_PACKAGE_NAME "kwin-glass")
set(CPACK_PACKAGING_INSTALL_PREFIX "/usr")
set(CPACK_PACKAGE_FILE_NAME "kwin-glass")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Fork of the KWin Blur effect for KDE Plasma 6 with additional features (including force blur) and bug fixes")
include(CPack)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Choose Release or Debug" FORCE)
endif()
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -DQT_NO_DEBUG_OUTPUT")

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${ECM_MODULE_PATH} ${ECM_KDE_MODULE_DIR})

option(GLASS_WAYLAND "Whether to build Glass for Wayland if present." ON)
option(GLASS_X11 "Whether to build Glass for X11 if present." OFF)

include(FeatureSummary)
include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS
    Gui
    Core
    DBus
    Widgets
    OpenGL
    Network
    Xml
)

include_directories(${Qt6Widgets_INCLUDE_DIRS} ${Qt6Network_INCLUDE_DIRS} ${Qt6OpenGL_INCLUDE_DIRS} ${Qt6Xml_INCLUDE_DIRS})
add_definitions(${Qt6Widgets_DEFINITIONS})

find_package(KF6 ${KF_MIN_VERSION} REQUIRED COMPONENTS
    I18n
    GuiAddons
    KCMUtils
)

if(GLASS_WAYLAND)
    # A KWin config file can be present while one of its transitive development
    # dependencies is not. Treat the complete imported target as the
    # capability check instead of assuming KWinConfig.cmake is sufficient.
    find_package(KWin QUIET COMPONENTS kwineffects)
    find_package(XCB QUIET COMPONENTS XCB)
    if(KWin_FOUND AND TARGET KWin::kwin AND TARGET XCB::XCB)
        if(KWin_VERSION VERSION_LESS 6.4)
            message(FATAL_ERROR "Glass does not support your Plasma version (${KWin_VERSION}). See the README for more information.")
        endif()
        if(KWin_VERSION VERSION_GREATER_EQUAL 6.7)
            set(GLASS_KWIN_67 ON)
        endif()
    else()
        message(STATUS "Glass Wayland effect disabled: KWin or XCB development dependencies are unavailable")
        set(GLASS_WAYLAND OFF)
    endif()
endif()

if(GLASS_X11)
    find_package(X11 QUIET)
    find_package(XCB QUIET COMPONENTS XCB)
    find_package(KWinX11 QUIET COMPONENTS kwineffects)
    if(X11_FOUND AND TARGET XCB::XCB AND KWinX11_FOUND AND TARGET KWinX11::kwin)
        if(KWinX11_VERSION VERSION_LESS 6.4)
            message(FATAL_ERROR "Glass does not support your Plasma version (${KWinX11_VERSION}). See the README for more information.")
        endif()
    else()
        message(STATUS "Glass X11 effect disabled: X11, XCB, or KWin X11 development dependencies are unavailable")
        set(GLASS_X11 OFF)
    endif()
endif()

set(GLASS_BUILD_KCM OFF)
if(GLASS_WAYLAND OR GLASS_X11)
    find_package(KDecoration3 QUIET)
    if(NOT KDecoration3_FOUND OR NOT TARGET KDecoration3::KDecoration)
        message(STATUS "Glass effects disabled: KDecoration3 development dependencies are unavailable")
        set(GLASS_WAYLAND OFF)
        set(GLASS_X11 OFF)
    endif()
endif()

if(GLASS_WAYLAND OR GLASS_X11)
    # The KCM needs KWin's D-Bus XML only to generate its reconfigure proxy.
    # Keep that optional so the effect can build when a distro splits the
    # interface metadata into a separate development package.
    if(GLASS_WAYLAND)
        find_package(KWinDBusInterface CONFIG QUIET)
    elseif(GLASS_X11)
        find_package(KWinX11DBusInterface CONFIG QUIET)
    endif()

    if(KWIN_EFFECTS_INTERFACE AND EXISTS "${KWIN_EFFECTS_INTERFACE}")
        set(GLASS_BUILD_KCM ON)
    else()
        message(STATUS "Glass settings module disabled: KWin's Effects D-Bus interface is unavailable")
    endif()

    add_subdirectory(src)
else()
    message(WARNING "No supported KWin backend is available; Glass effect targets will be skipped")
endif()

ki18n_install(po)

feature_summary(WHAT ALL FATAL_ON_MISSING_REQUIRED_PACKAGES)
