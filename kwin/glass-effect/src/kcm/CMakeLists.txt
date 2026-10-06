set(kwin_glass_config_SRCS
    blur_config.cpp
    blur_config.h
    blur_config.qrc
)

# This directory is normally gated by GLASS_BUILD_KCM in its parent.  Keep a
# local guard as well so direct or downstream inclusion never calls Qt's D-Bus
# generator with an empty interface path.
if(NOT KWIN_EFFECTS_INTERFACE OR NOT EXISTS "${KWIN_EFFECTS_INTERFACE}")
    message(STATUS "Glass settings module disabled: KWin's Effects D-Bus interface is unavailable")
    return()
endif()

ki18n_wrap_ui(kwin_glass_config_SRCS blur_config.ui)
# GENERATE_MOC keeps the generated blurconfig.h out of AUTOMOC. KConfigXT emits
# the moc code itself instead, which breaks a dependency cycle Ninja otherwise
# reports as
#   kwin_glass_config_autogen/timestamp -> blurconfig.h -> kwin_glass_config_autogen
# The header is an AUTOGEN input that only exists once AUTOGEN has run, so the
# two wait on each other and the build fails with "dependency cycle". The effect
# plugin processes the same .kcfgc without hitting this because it generates into
# its own directory rather than a directory AUTOMOC also scans.
kconfig_add_kcfg_files(kwin_glass_config_SRCS ../blurconfig.kcfgc GENERATE_MOC)

# This will only work as long as KWin and KWin X11 have the same interface
qt_add_dbus_interface(kwin_glass_config_SRCS "${KWIN_EFFECTS_INTERFACE}" kwineffects_interface)

add_library(kwin_glass_config MODULE ${kwin_glass_config_SRCS})
target_link_libraries(kwin_glass_config
    KF6::KCMUtils
    KF6::CoreAddons
    KF6::I18n
    Qt6::DBus
)

if(GLASS_WAYLAND)
    install(TARGETS kwin_glass_config DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin/effects/configs)
endif()
if(GLASS_X11)
    install(TARGETS kwin_glass_config DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin-x11/effects/configs)
endif()

add_compile_definitions(ABOUT_VERSION_STRING="${PROJECT_VERSION}")
