cmake_minimum_required(VERSION 3.21)

project(kos-bridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)
set(QT_MAJOR_VERSION 6)

find_package(ECM REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} ${ECM_MODULE_PATH} ${ECM_KDE_MODULE_DIR})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core DBus Gui Widgets OpenGL Network Xml)
find_package(KWin REQUIRED COMPONENTS kwineffects)
# To read which decoration KWin is configured to use out of kwinrc. Nothing else
# in the plugin uses KConfig.
find_package(KF6 REQUIRED COMPONENTS Config)

add_library(kos_bridge MODULE
    bridge.cpp
    main.cpp
    windowbuttons/adjustsession.cpp
    windowbuttons/buttonglyph.cpp
    windowbuttons/buttonrenderer.cpp
    windowbuttons/buttonconfig.cpp
    windowbuttons/buttoninput.cpp
    windowbuttons/panelgeometry.cpp
    windowbuttons/tilemenu.cpp
    windowbuttons/titlebarmetrics.cpp
    windowbuttons/windowrules.cpp
)

target_link_libraries(kos_bridge PRIVATE
    Qt6::Core
    Qt6::DBus
    KF6::ConfigCore
    KWin::kwin
)

# Offline preview of the window-button panel. The lights are pure QPainter
# geometry over a rectangle (see windowbuttons/buttonglyph.h), so the whole panel
# can be rendered without a compositor -- which is the point: the alternative is
# to build the effect, install it to /usr, and restart KWin, and KWin restarting
# takes every Wayland client with it. Hot-loading a replaced plugin .so is the
# operation that has crashed KWin before, so it is not an option either.
#
#   cmake -S . -B build -DKOS_BRIDGE_BUILD_PREVIEW=ON
#   cmake --build build --target glyph_preview
#   QT_QPA_PLATFORM=offscreen build/glyph_preview /tmp/panel.png
#
# Off by default so packaging builds stay lean.
option(KOS_BRIDGE_BUILD_PREVIEW "Build the offline window-button panel preview" OFF)
if(KOS_BRIDGE_BUILD_PREVIEW)
    add_executable(glyph_preview
        preview/glyph_preview.cpp
        windowbuttons/buttonglyph.cpp
        windowbuttons/panelgeometry.cpp
    )
    # Qt6::Gui and nothing else: no KWin, no KF6, no DBus. If this target ever
    # needs one of those, the light drawing has picked up a dependency it should
    # not have and the preview has stopped being able to answer the question it
    # exists to answer.
    target_link_libraries(glyph_preview PRIVATE Qt6::Gui)
endif()

# Offline harness for the title-bar scan. The scan is pure geometry over a
# pixel block, so it can be checked against synthetic title bars without a
# compositor; off by default so packaging builds stay lean.
option(KOS_BRIDGE_BUILD_TESTS "Build the title-bar scan harness and the rules test" OFF)
if(KOS_BRIDGE_BUILD_TESTS)
    add_executable(scan_titlebar
        tests/scan_titlebar.cpp
        windowbuttons/titlebarscan.cpp
    )
    target_link_libraries(scan_titlebar PRIVATE Qt6::Gui)

    # The rule list, the geometry the adjust gesture works in, and the four-step
    # resolution that decides which of them a window gets. None of it touches a
    # compositor: panelgeometry and windowrules are deliberately free of KWin
    # headers so that they can be tested like this.
    enable_testing()
    add_executable(rules_test
        tests/rules_test.cpp
        windowbuttons/panelgeometry.cpp
        windowbuttons/tilemenu.cpp
        windowbuttons/windowrules.cpp
        windowbuttons/buttonconfig.cpp
    )
    target_link_libraries(rules_test PRIVATE Qt6::Core KF6::ConfigCore)
    add_test(NAME rules_test COMMAND rules_test)
endif()

install(TARGETS kos_bridge
    DESTINATION ${KDE_INSTALL_PLUGINDIR}/kwin/effects/plugins
    COMPONENT kwin_plugins)
