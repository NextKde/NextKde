# Settings page for the Glass effect. KWin discovers it by filename
# (kwin_<effect id>_config) inside kwin/effects/configs.
set(kwin_glass_config_SRCS
    glass_config.cpp
    glass_config.h
)

if(NOT KWIN_EFFECTS_INTERFACE OR NOT EXISTS "${KWIN_EFFECTS_INTERFACE}")
    message(STATUS "Glass settings module disabled: KWin's Effects D-Bus interface is unavailable")
    return()
endif()

qt_add_dbus_interface(kwin_glass_config_SRCS "${KWIN_EFFECTS_INTERFACE}" kwineffects_interface)

add_library(kwin_glass_config MODULE ${kwin_glass_config_SRCS})
target_link_libraries(kwin_glass_config PRIVATE
    KWin::kwin
    KF6::KCMUtils
    KF6::CoreAddons
    KF6::I18n
    Qt6::Widgets
    Qt6::DBus
)

install(TARGETS kwin_glass_config
    DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin/effects/configs)
