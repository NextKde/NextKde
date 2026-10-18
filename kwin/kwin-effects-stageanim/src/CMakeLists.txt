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
        # 6.7+ 端口的编译开关（自建 ItemRendererOpenGL 替代 scene()->renderer()）。
        # ⚠️ 不能依赖构建缓存：干净配置丢这个定义 = STAGE_LIVE_CONTENT_RENDER=0
        # 静默编译成静态玻璃卡（2026-10-09 实锤本机缓存路径）
        target_compile_definitions(stageanim13 PRIVATE ANLAND_KWIN_67)
        # 6.8 把 ItemRendererOpenGL 构造从 EglDisplay* 改成 RenderDevice*
        #（RenderBackend::renderDevice() 公开访问器）。探测头文件选路径
        set(_iro_header "")
        foreach(_dir IN LISTS _kwin_include_dirs)
            if(EXISTS "${_dir}/scene/itemrenderer_opengl.h")
                set(_iro_header "${_dir}/scene/itemrenderer_opengl.h")
                break()
            endif()
        endforeach()
        if(_iro_header)
            file(READ "${_iro_header}" _iro_src)
            if(_iro_src MATCHES "ItemRendererOpenGL\\(RenderDevice")
                message(STATUS "KWin API: ItemRendererOpenGL takes RenderDevice (6.8)")
                target_compile_definitions(stageanim13 PRIVATE STAGE_RENDERER_RENDERDEVICE_API)
            else()
                message(STATUS "KWin API: ItemRendererOpenGL takes EglDisplay (6.7)")
            endif()
        endif()
    endif()
endif()

install(TARGETS stageanim13
    DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin/effects/plugins
    COMPONENT kwin_plugins)

# KWin 6.8 propagates paint success through the effect chain. Detect the
# installed signature so older releases and distribution backports still work.
if(TARGET stageanim13)
    get_target_property(_kos_paint_includes KWin::kwin INTERFACE_INCLUDE_DIRECTORIES)
    foreach(_dir IN LISTS _kos_paint_includes)
        if(EXISTS "${_dir}/effect/effect.h")
            set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_dir}/effect/effect.h")
            file(READ "${_dir}/effect/effect.h" _kos_paint_header)
            if(_kos_paint_header MATCHES "bool drawWindow\\(")
                target_compile_definitions(stageanim13 PRIVATE KOS_KWIN_PAINT_RESULT_API)
            endif()
            break()
        endif()
    endforeach()
    set_property(TARGET stageanim13 APPEND PROPERTY AUTOMOC_MACRO_NAMES
        KWIN_EFFECT_FACTORY_SUPPORTED_ENABLED)
endif()
