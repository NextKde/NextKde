add_definitions(-DTRANSLATION_DOMAIN="kwin_effects_stageanim")

set(CMAKE_AUTORCC ON)

set(stageanim_SOURCES
    stageanim.cpp
    main.cpp
    shaders.qrc
)

add_library(stageanim13 MODULE ${stageanim_SOURCES})
target_link_libraries(stageanim13 PRIVATE
    KF6::ConfigGui
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
        target_compile_definitions(stageanim13 PRIVATE KOS_KWIN_PAINT_TIME_API)
    else()
        message(STATUS "KWin API: prePaint hooks without presentTime (6.7-style)")
    endif()
endif()

install(TARGETS stageanim13
    DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin/effects/plugins
    COMPONENT kwin_plugins)
