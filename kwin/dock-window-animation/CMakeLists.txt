cmake_minimum_required(VERSION 3.21)

project(kos_dock_window_animation LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(QT_MAJOR_VERSION 6)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${ECM_MODULE_PATH} ${ECM_KDE_MODULE_DIR})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core DBus Gui Widgets OpenGL Network Xml)
find_package(KF6 REQUIRED COMPONENTS Config)
find_package(KWin REQUIRED COMPONENTS kwineffects)

add_library(kos_dock_window_animation MODULE
    dockwindowanimationeffect.cpp
    main.cpp
)

target_link_libraries(kos_dock_window_animation PRIVATE
    Qt6::Core
    Qt6::DBus
    KF6::ConfigCore
    KWin::kwin
)

# Since KWin 6.7 (master), presentTime was dropped from the prePaintScreen /
# prePaintWindow hooks and TimeLine::advance(RenderView*) replaced
# TimeLine::advance(std::chrono::milliseconds). Detect which API the installed
# KWin headers provide so the effect builds on both 6.6.x and 6.7+.
set(_kwin_effecthandler "")
get_target_property(_kwin_include_dirs KWin::kwin INTERFACE_INCLUDE_DIRECTORIES)
foreach(_dir ${_kwin_include_dirs})
    if(EXISTS "${_dir}/effect/effecthandler.h")
        set(_kwin_effecthandler "${_dir}/effect/effecthandler.h")
        break()
    endif()
endforeach()
if(NOT _kwin_effecthandler AND EXISTS "/usr/include/kwin/effect/effecthandler.h")
    set(_kwin_effecthandler "/usr/include/kwin/effect/effecthandler.h")
endif()
if(_kwin_effecthandler)
    file(READ "${_kwin_effecthandler}" _kwin_effecthandler_src)
    if(_kwin_effecthandler_src MATCHES "prePaintScreen\\(ScreenPrePaintData[^;]*std::chrono::milliseconds")
        message(STATUS "KWin API: prePaint hooks take presentTime (6.6-style)")
        target_compile_definitions(kos_dock_window_animation PRIVATE KOS_KWIN_PAINT_TIME_API)
    else()
        message(STATUS "KWin API: prePaint hooks without presentTime (6.7-style)")
    endif()
endif()

install(TARGETS kos_dock_window_animation
    DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin/effects/plugins
    COMPONENT kwin_plugins)
