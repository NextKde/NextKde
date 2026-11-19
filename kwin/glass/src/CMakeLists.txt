# The shaders are assembled at configure time from small GLSL sources so the
# core-profile preamble and helper includes are expanded once, before Qt
# resources are generated.
file(READ shaders/compat_core.glsl COMPAT_CORE)

file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/generated")
configure_file(glass.qrc "${CMAKE_CURRENT_BINARY_DIR}/glass.qrc" COPYONLY)

set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/glass.qrc"
    "${CMAKE_CURRENT_SOURCE_DIR}/shaders/compat_core.glsl")

function(glass_generate_shader input_glsl output_base extension)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/${input_glsl}")
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/${input_glsl}" SHADER_SRC)
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/generated/${output_base}${extension}"
        "${COMPAT_CORE}\n${SHADER_SRC}")
    # KWin <= 6.6 resolves a second, core-profile variant by appending "_core"
    # to the resource name; 6.7 merged the two. Publish the same bytes twice.
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/generated/${output_base}_core${extension}"
        "${COMPAT_CORE}\n${SHADER_SRC}")
endfunction()

glass_generate_shader(shaders/vertex.glsl vertex .vert)
glass_generate_shader(shaders/onscreen_vertex.glsl onscreen .vert)
glass_generate_shader(shaders/downsample.glsl downsample .frag)
glass_generate_shader(shaders/upsample.glsl upsample .frag)
glass_generate_shader(shaders/onscreen.glsl onscreen .frag)

find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
set(KOS_SURFACE_SHAPE_PROTOCOL
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../shell/native/surface-shape/kos-surface-shape-v1.xml"
    CACHE FILEPATH "KOS surface shape protocol used by the Glass effect")
set(_glass_server_header
    "${CMAKE_CURRENT_BINARY_DIR}/wayland-kos-surface-shape-v1-server-protocol.h")
set(_glass_protocol_code
    "${CMAKE_CURRENT_BINARY_DIR}/wayland-kos-surface-shape-v1-protocol.c")

add_custom_command(OUTPUT "${_glass_server_header}"
    COMMAND ${WAYLAND_SCANNER} server-header "${KOS_SURFACE_SHAPE_PROTOCOL}"
            "${_glass_server_header}"
    DEPENDS "${KOS_SURFACE_SHAPE_PROTOCOL}" VERBATIM)
add_custom_command(OUTPUT "${_glass_protocol_code}"
    COMMAND ${WAYLAND_SCANNER} public-code "${KOS_SURFACE_SHAPE_PROTOCOL}"
            "${_glass_protocol_code}"
    DEPENDS "${KOS_SURFACE_SHAPE_PROTOCOL}" VERBATIM)
set_source_files_properties("${_glass_server_header}" "${_glass_protocol_code}"
    PROPERTIES GENERATED TRUE SKIP_AUTOMOC TRUE)

set(glass_SOURCES
    glass.cpp
    surfaceshapemanager.cpp
    main.cpp
    "${CMAKE_CURRENT_BINARY_DIR}/glass.qrc"
    "${_glass_server_header}"
    "${_glass_protocol_code}"
)

add_library(glass MODULE ${glass_SOURCES})

target_link_libraries(glass PRIVATE
    KWin::kwin
    Qt6::Core
    Qt6::Gui
)

if(KWin_VERSION VERSION_GREATER_EQUAL 6.7)
    target_compile_definitions(glass PRIVATE GLASS_KWIN_67)
endif()

# KWin 6.8 propagates paint success through the effect chain. Detect the
# installed signature so 6.6/6.7 still build with the void form.
get_target_property(_glass_kwin_includes KWin::kwin INTERFACE_INCLUDE_DIRECTORIES)
foreach(_dir IN LISTS _glass_kwin_includes)
    if(EXISTS "${_dir}/effect/effect.h")
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_dir}/effect/effect.h")
        file(READ "${_dir}/effect/effect.h" _glass_effect_header)
        if(_glass_effect_header MATCHES "bool drawWindow\\(")
            target_compile_definitions(glass PRIVATE KOS_KWIN_PAINT_RESULT_API)
        endif()
        break()
    endif()
endforeach()

set_property(TARGET glass APPEND PROPERTY AUTOMOC_MACRO_NAMES
    KWIN_EFFECT_FACTORY_SUPPORTED_ENABLED)

install(TARGETS glass
    DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin/effects/plugins)

if(KF6KCMUtils_FOUND AND KWinDBusInterface_FOUND)
    add_subdirectory(kcm)
else()
    message(STATUS "Glass settings module skipped (KCMUtils or KWinDBusInterface not found)")
endif()
