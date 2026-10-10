# Add the localization domain
add_definitions(-DTRANSLATION_DOMAIN="kwin_effects_glass")

if(GLASS_BUILD_KCM)
    add_subdirectory(kcm)
endif()

# Read compat preambles
file(READ shaders/compat_core.glsl COMPAT_CORE)
#file(READ shaders/compat_legacy.glsl COMPAT_LEGACY)
file(READ shaders/oklab.glsl OKLAB_SHADER)
file(READ shaders/snells-glass.glsl SNELLS_GLASS_SHADER)
file(READ shaders/glass.glsl GLASS_SHADER)

# These files are consumed by file(READ) during configure rather than compiled
# as ordinary sources. Without explicit configure dependencies, editing a GLSL
# helper can leave the embedded shader -- and glass.so -- unchanged until some
# unrelated CMake input happens to trigger regeneration.
file(GLOB GLASS_CONFIGURE_SHADER_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/shaders/*.glsl")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    ${GLASS_CONFIGURE_SHADER_SOURCES})

# glass.glsl is inserted into the final fragment shader as text, so expand its
# own helper include before that insertion.
string(REPLACE "#include \"snells-glass.glsl\"" "${SNELLS_GLASS_SHADER}" GLASS_SHADER "${GLASS_SHADER}")

# Generate a core shader variant from a single .glsl source.
# Output goes into generated/ to keep source shaders/ clean.
function(generate_shader_variants input_glsl output_base)
    # Re-run shader generation when its source changes, including incremental
    # builds; an old generated fragment would silently miss appearance masks.
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/${input_glsl}")
    file(READ "${input_glsl}" SHADER_SRC)

    # Expand helper-shader includes
    string(REPLACE "#include \"oklab.glsl\"" "${OKLAB_SHADER}" SHADER_SRC_EXPANDED "${SHADER_SRC}")
    string(REPLACE "#include \"glass.glsl\"" "${GLASS_SHADER}" SHADER_SRC_EXPANDED "${SHADER_SRC_EXPANDED}")

    # The generated sources already carry the core compatibility preamble.
    # KWin <= 6.6 resolves a second, core-profile variant of every shader by
    # appending a "_core" suffix to the resource name (6.7 merged the two
    # variants into one), so publish the same bytes under both names.
    file(WRITE "generated/${output_base}${ARGN}" "${COMPAT_CORE}\n${SHADER_SRC_EXPANDED}")
    file(WRITE "generated/${output_base}_core${ARGN}" "${COMPAT_CORE}\n${SHADER_SRC_EXPANDED}")
endfunction()

# Generate vertex shaders
generate_shader_variants(shaders/vertex.glsl vertex .vert)
generate_shader_variants(shaders/onscreen_rounded_vertex.glsl onscreen_rounded .vert)

# Generate fragment shaders
generate_shader_variants(shaders/downsample.glsl downsample .frag)
generate_shader_variants(shaders/upsample.glsl upsample .frag)
generate_shader_variants(shaders/noise.glsl noise .frag)
generate_shader_variants(shaders/onscreen_rounded.glsl onscreen_rounded .frag)

set(glass_SOURCES
    blur.cpp
    settings.cpp
    surfaceshapemanager.cpp
    blur.qrc
    main.cpp
)

find_package(WaylandScanner REQUIRED)
set(KOS_SURFACE_SHAPE_PROTOCOL
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../shell/native/surface-shape/kos-surface-shape-v1.xml"
    CACHE FILEPATH "KOS surface shape protocol used by the Glass effect")
ecm_add_wayland_server_protocol(glass_SOURCES
    PROTOCOL "${KOS_SURFACE_SHAPE_PROTOCOL}"
    BASENAME kos-surface-shape-v1)

kconfig_add_kcfg_files(glass_SOURCES
    blurconfig.kcfgc
)

if(GLASS_WAYLAND)
    add_library(glass MODULE ${glass_SOURCES})
    target_link_libraries(glass PRIVATE
        KDecoration3::KDecoration
        KF6::ConfigGui
        KWin::kwin
        XCB::XCB
    )
    if(GLASS_KWIN_67)
        target_compile_definitions(glass PRIVATE GLASS_KWIN_67)
    endif()
    install(TARGETS glass DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin/effects/plugins)
endif()
if(GLASS_X11)
    add_library(glass_x11 MODULE ${glass_SOURCES})
    target_link_libraries(glass_x11 PRIVATE
        KDecoration3::KDecoration
        KF6::ConfigGui
        KWinX11::kwin
        XCB::XCB
    )
    target_compile_definitions(glass_x11 PRIVATE GLASS_X11)
    install(TARGETS glass_x11 DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin-x11/effects/plugins)
endif()
