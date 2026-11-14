cmake_minimum_required(VERSION 3.21)

# VERSION is the desktop distribution identity; protocol/app versions are separate.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION")
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" KOS_RELEASE_VERSION LIMIT_COUNT 1)
if(NOT KOS_RELEASE_VERSION MATCHES "^([0-9]+\\.[0-9]+\\.[0-9]+)(-[0-9A-Za-z.-]+)?$")
    message(FATAL_ERROR "Invalid desktop VERSION")
endif()
set(KOS_RELEASE_NUMERIC_VERSION "${CMAKE_MATCH_1}")
project(KOS VERSION ${KOS_RELEASE_NUMERIC_VERSION} LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

include(CTest)
include(GNUInstallDirs)

option(KOS_BUILD_PLATFORM "Build the KOS platform daemon and settings app" ON)
option(KOS_BUILD_KWIN_PLUGINS "Build the KWin plugins and the window decoration" ON)
set(KOS_FLATPAK_SUPPORT "AUTO" CACHE STRING "Optional Flatpak backend: AUTO, ON or OFF")
set_property(CACHE KOS_FLATPAK_SUPPORT PROPERTY STRINGS AUTO ON OFF)
if(NOT KOS_FLATPAK_SUPPORT MATCHES "^(AUTO|ON|OFF)$")
    message(FATAL_ERROR "KOS_FLATPAK_SUPPORT must be AUTO, ON or OFF")
endif()
# Removed application switches are migration errors, not silently ignored knobs.
foreach(app CALENDAR TODO WEATHER LISTENFREE CALCULATOR)
    if(DEFINED KOS_BUILD_${app} AND KOS_BUILD_${app})
        message(FATAL_ERROR
            "KOS_BUILD_${app} moved to its independent NextKde repository. "
            "Use tools/kosctl install apps --app <calendar|calculator|weather|listenfree> "
            "or build that repository directly (Todo belongs to kos-calendar). "
            "Remove the old ON cache entry before configuring core.")
    endif()
endforeach()
# The depth engine (kos-ai) needs OpenCV and the ONNX Runtime, and the 3D
# wallpaper plugin needs Qt Quick 3D. KOS_BUILD_SPATIAL decides whether they are
# built; the resolution below turns it into KOS_SPATIAL_ENABLED, which both this
# file and platform/CMakeLists.txt read:
#
#   AUTO (default)  build them when the dependencies are already installed
#   ON              require them; configure fails when they are missing
#   OFF             never build them, never look for them
if(NOT DEFINED KOS_BUILD_SPATIAL)
    set(KOS_BUILD_SPATIAL "AUTO" CACHE STRING
        "Build the ONNX/OpenCV depth engine and 3D wallpaper plugin: AUTO, ON or OFF")
endif()
set_property(CACHE KOS_BUILD_SPATIAL PROPERTY STRINGS AUTO ON OFF)

set(KOS_SPATIAL_ENABLED FALSE)
if(KOS_BUILD_SPATIAL STREQUAL "ON")
    # The REQUIRED find_package calls in services/ai/CMakeLists.txt are the loud
    # failure for this mode; nothing is probed here.
    set(KOS_SPATIAL_ENABLED TRUE)
elseif(KOS_BUILD_SPATIAL STREQUAL "AUTO" OR KOS_BUILD_SPATIAL STREQUAL "TRUE"
        OR KOS_BUILD_SPATIAL STREQUAL "1")
    find_package(OpenCV QUIET COMPONENTS core imgproc imgcodecs)
    find_path(ONNXRUNTIME_INCLUDE_DIR onnxruntime_cxx_api.h
        PATH_SUFFIXES onnxruntime onnxruntime/core/session)
    find_library(ONNXRUNTIME_LIBRARY NAMES onnxruntime)
    if(OpenCV_FOUND AND ONNXRUNTIME_INCLUDE_DIR AND ONNXRUNTIME_LIBRARY)
        set(KOS_SPATIAL_ENABLED TRUE)
    else()
        message(STATUS
            "Depth engine skipped: OpenCV or the ONNX Runtime is not installed. "
            "Install both and configure with -DKOS_BUILD_SPATIAL=ON to build it.")
    endif()
elseif(NOT KOS_BUILD_SPATIAL STREQUAL "OFF")
    message(FATAL_ERROR "KOS_BUILD_SPATIAL must be AUTO, ON or OFF")
endif()

# tools/kosctl reads this to decide whether to deploy (or clean up) the worker:
# AUTO resolves here rather than in the script, and a build tree can still hold
# a worker binary from an earlier configuration.
if(KOS_SPATIAL_ENABLED)
    file(WRITE "${CMAKE_BINARY_DIR}/kos-spatial-enabled" "ON\n")
else()
    file(WRITE "${CMAKE_BINARY_DIR}/kos-spatial-enabled" "OFF\n")
endif()

if(BUILD_TESTING)
    find_program(KOS_NODE_EXECUTABLE NAMES node)
    if(KOS_NODE_EXECUTABLE)
        # Group Dock logic by module responsibility; node:test retains named
        # scenarios inside each suite and continues after an individual failure.
        foreach(suite model policy motion native-target)
            add_test(NAME kos-dock.${suite}
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock/${suite}.test.mjs)
            set_tests_properties(kos-dock.${suite} PROPERTIES LABELS logic TIMEOUT 30)
        endforeach()
        # Regression: material-style Dock showed two overlapping tooltips. The
        # popup's active condition must stay decoupled from magnification.
        add_test(NAME kos-dock.tooltip-mutex
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock/tooltip-mutex.test.mjs)
        set_tests_properties(kos-dock.tooltip-mutex PROPERTIES LABELS logic TIMEOUT 10)
        # Regression: the DeskCenter weather card overlapped its hero/symbol/
        # condition text on short cards; the size formulas must keep their
        # availability terms above the weekly forecast.
        add_test(NAME kos-deskcenter.weather-card
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/deskcenter/weather-card-205.test.mjs)
        set_tests_properties(kos-deskcenter.weather-card PROPERTIES LABELS logic TIMEOUT 10)
        # Regression: SurfaceShape ignored scale changes, so panels animating
        # scale on entry (wallpaper preview) fringed at the corners.
        add_test(NAME kos-surface-shape.scale-sync
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/surface-shape/scale-sync-214.test.mjs)
        set_tests_properties(kos-surface-shape.scale-sync PROPERTIES LABELS logic TIMEOUT 10)
        add_test(NAME kos-applauncher.screen-routing
            COMMAND ${KOS_NODE_EXECUTABLE}
                --test ${CMAKE_CURRENT_SOURCE_DIR}/tests/applauncher/screen-routing.test.mjs)
        set_tests_properties(kos-applauncher.screen-routing PROPERTIES LABELS logic TIMEOUT 10)
        add_test(NAME kos-shell.traffic-history
            COMMAND ${KOS_NODE_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/status-area/test_traffic_history.mjs)
        set_tests_properties(kos-shell.traffic-history PROPERTIES LABELS logic TIMEOUT 10)
        add_test(NAME kos-shell.application-traffic
            COMMAND ${KOS_NODE_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/status-area/test_application_traffic.mjs)
        set_tests_properties(kos-shell.application-traffic PROPERTIES LABELS logic TIMEOUT 10)
        add_test(NAME kos-shell.battery-data
            COMMAND ${KOS_NODE_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/status-area/test_battery_data.mjs)
        set_tests_properties(kos-shell.battery-data PROPERTIES LABELS logic TIMEOUT 10)
        add_test(NAME kos-shell.language
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/localization/widget-language.mjs)
        set_tests_properties(kos-shell.language PROPERTIES LABELS logic TIMEOUT 10)
        add_test(NAME kos-shell.clipboard-placement
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/clipboard-placement/test_geometry.mjs)
        set_tests_properties(kos-shell.clipboard-placement PROPERTIES LABELS logic TIMEOUT 10)
        add_test(NAME kos-deskcenter.density-metrics
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/desktop-density/test_metrics.mjs)
        set_tests_properties(kos-deskcenter.density-metrics PROPERTIES LABELS logic TIMEOUT 10)
        add_test(NAME kos-deskcenter.widget-layout
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/deskcenter/test_widget_layout.mjs
        )
        set_tests_properties(kos-deskcenter.widget-layout PROPERTIES TIMEOUT 10)
        # Widget geometry must look identical at 60 and 240 Hz; the replaced
        # SpringAnimation advanced in fixed 16 ms steps.
        add_test(NAME kos-deskcenter.motion-spring
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/common/test_motion_spring.mjs
        )
        set_tests_properties(kos-deskcenter.motion-spring PROPERTIES LABELS logic TIMEOUT 10)
        add_test(NAME kos-ui.visual-contract
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shared/qml/test_visual_contract.mjs
        )
        set_tests_properties(kos-ui.visual-contract PROPERTIES TIMEOUT 10)
        # The wheel-scroll curve itself (KosKineticScrollPhysics.mjs): distance
        # per notch, time to settle, the coast after a spin, the bounds. A
        # compositor can only show these as "it felt wrong".
        add_test(NAME kos-ui.kinetic-scroll-physics
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shared/qml/foundation/test_kinetic_scroll.mjs
        )
        set_tests_properties(kos-ui.kinetic-scroll-physics PROPERTIES LABELS logic TIMEOUT 10)
        add_test(NAME kos-ui.color-scheme
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/color-scheme/test_color_scheme.mjs
        )
        set_tests_properties(kos-ui.color-scheme PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.date-buckets
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/common/test_date_buckets.mjs
        )
        set_tests_properties(kos-shell.date-buckets PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.squircle
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/common/test_squircle.mjs
        )
        set_tests_properties(kos-shell.squircle PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.tray-attention-match
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/common/test_tray_attention_match.mjs
        )
        set_tests_properties(kos-shell.tray-attention-match PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.tray-identity
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/bar/test_tray_identity.mjs)
        set_tests_properties(kos-shell.tray-identity PROPERTIES TIMEOUT 10 LABELS logic)
        add_test(NAME kos-shell.notification-count-match
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/common/test_notification_count_match.mjs
        )
        set_tests_properties(kos-shell.notification-count-match PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.control-center-submenu-state
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/bar/test_control_center_submenu_state.mjs
        )
        set_tests_properties(kos-shell.control-center-submenu-state PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.status-collection
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/bar/test_status_collection.mjs
        )
        set_tests_properties(kos-shell.status-collection PROPERTIES TIMEOUT 10 LABELS logic)
        add_test(NAME kos-shell.network-traffic-width
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/bar/test_network_traffic_width.mjs
        )
        set_tests_properties(kos-shell.network-traffic-width PROPERTIES TIMEOUT 10 LABELS logic)
        add_test(NAME kos-shell.visibility-policy
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/common/test_visibility_policy.mjs
        )
        set_tests_properties(kos-shell.visibility-policy PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.audio-output-names
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/common/test_audio_output_names.mjs
        )
        set_tests_properties(kos-shell.audio-output-names PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.weather-fields
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/weather/test_weather_service_fields.mjs
        )
        set_tests_properties(kos-shell.weather-fields PROPERTIES TIMEOUT 10 LABELS logic)
        find_program(KOS_QMLTESTRUNNER_EXECUTABLE NAMES qmltestrunner
            HINTS /usr/lib/qt6/bin /usr/lib64/qt6/bin)
        if(KOS_QMLTESTRUNNER_EXECUTABLE)
            if(KOS_BUILD_PLATFORM OR KOS_BUILD_KWIN_PLUGINS)
                add_test(NAME kos-shell.startup-reveal
                    COMMAND ${KOS_NODE_EXECUTABLE}
                        ${CMAKE_CURRENT_SOURCE_DIR}/tests/shell-startup/reveal.mjs
                        ${KOS_QMLTESTRUNNER_EXECUTABLE})
                set_tests_properties(kos-shell.startup-reveal PROPERTIES
                    LABELS "ui;headless" TIMEOUT 30
                    ENVIRONMENT "QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
            endif()
            add_test(NAME kos-shell.stage-visibility-qml
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/stage-visibility/run.mjs
                    ${KOS_QMLTESTRUNNER_EXECUTABLE})
            set_tests_properties(kos-shell.stage-visibility-qml PROPERTIES LABELS "ui;headless" TIMEOUT 25)
            add_test(NAME kos-shell.dock-native-target
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock/runtime.mjs native-target
                    ${KOS_QMLTESTRUNNER_EXECUTABLE})
            set_tests_properties(kos-shell.dock-native-target PROPERTIES LABELS "ui;headless" TIMEOUT 20)
            add_test(NAME kos-shell.dock-selection-highlight
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock/runtime.mjs highlight
                    ${KOS_QMLTESTRUNNER_EXECUTABLE})
            set_tests_properties(kos-shell.dock-selection-highlight PROPERTIES LABELS "ui;headless" TIMEOUT 20)
            add_test(NAME kos-shell.desktop-lyrics
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock/runtime.mjs lyrics
                    ${KOS_QMLTESTRUNNER_EXECUTABLE})
            set_tests_properties(kos-shell.desktop-lyrics PROPERTIES LABELS "ui;headless" TIMEOUT 15)
            add_test(NAME kos-shell.date-projection
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/date-projection/run.mjs
                    ${KOS_QMLTESTRUNNER_EXECUTABLE}
            )
            set_tests_properties(kos-shell.date-projection PROPERTIES TIMEOUT 15)
        endif()
        add_test(NAME kos-shell.wallpaper-slideshow
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/wallpaper/test_wallpaper_slideshow.mjs
        )
        set_tests_properties(kos-shell.wallpaper-slideshow PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.wallpaper-handoff
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/wallpaper/test_wallpaper_handoff.mjs)
        set_tests_properties(kos-shell.wallpaper-handoff PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.wallpaper-transitions
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/wallpaper/test_wallpaper_transitions.mjs)
        set_tests_properties(kos-shell.wallpaper-transitions PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.wallpaper-preview
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/wallpaper/test_wallpaper_preview.mjs
        )
        set_tests_properties(kos-shell.wallpaper-preview PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.theme-wallpaper-policy
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/wallpaper/test_theme_wallpaper_policy.mjs)
        set_tests_properties(kos-shell.theme-wallpaper-policy PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.theme-wallpaper-state
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/wallpaper/test_theme_wallpaper_state.mjs)
        set_tests_properties(kos-shell.theme-wallpaper-state PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.stage-geometry
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/stage/test_stage_geometry.mjs
        )
        set_tests_properties(kos-shell.stage-geometry PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.stage-visibility
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/stage/test_stage_visibility.mjs)
        set_tests_properties(kos-shell.stage-visibility PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.stage-groups
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/stage/test_stage_groups.mjs
        )
        set_tests_properties(kos-shell.stage-groups PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.stage-effects
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/stage/test_stage_effects.mjs)
        set_tests_properties(kos-shell.stage-effects PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.stage-protocol
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/stage/test_stage_protocol.mjs)
        set_tests_properties(kos-shell.stage-protocol PROPERTIES TIMEOUT 10)
        find_program(KOS_QUICKSHELL_EXECUTABLE NAMES quickshell)
        find_program(KOS_WEATHER_PYTHON_EXECUTABLE NAMES python3)
        if(KOS_QUICKSHELL_EXECUTABLE AND KOS_WEATHER_PYTHON_EXECUTABLE)
            add_test(NAME kos-shell.weather-refresh
                COMMAND ${KOS_WEATHER_PYTHON_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/weather-refresh/run.py
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-shell.weather-refresh PROPERTIES
                LABELS "ui;headless" TIMEOUT 20
                ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
        endif()
        if(KOS_QUICKSHELL_EXECUTABLE)
            add_test(NAME kos-shell.dock-surface
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock/runtime.mjs surface
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-shell.dock-surface PROPERTIES LABELS ui TIMEOUT 10)
            add_test(NAME kos-shell.dock-reveal-runtime
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock/runtime.mjs reveal
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-shell.dock-reveal-runtime PROPERTIES LABELS ui TIMEOUT 25
                ENVIRONMENT "QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
            add_test(NAME kos-deskcenter.density-runtime
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/desktop-density/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-deskcenter.density-runtime PROPERTIES LABELS ui TIMEOUT 15)
            add_test(NAME kos-shell.dock-builtins
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock/runtime.mjs builtins
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-shell.dock-builtins PROPERTIES
                LABELS ui TIMEOUT 25
                ENVIRONMENT "QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
            # A live DesktopEntry stored in a descriptor or an identity result
            # crashed the shell on every catalogue rescan. Nothing may carry one
            # now, and every launch resolves the entry from its desktop id.
            add_test(NAME kos-shell.app-launch-resolution
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/app-launch-resolution/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-shell.app-launch-resolution PROPERTIES
                LABELS ui TIMEOUT 45
                ENVIRONMENT "QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
            add_test(NAME kos-shell.dock-startup
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock/runtime.mjs startup
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-shell.dock-startup PROPERTIES LABELS ui TIMEOUT 60)
            add_test(NAME kos-shell.dock-reveal-indicator
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock/runtime.mjs reveal-indicator
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-shell.dock-reveal-indicator PROPERTIES
                LABELS ui TIMEOUT 25
                ENVIRONMENT "QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
            add_test(NAME kos-shell.tray-notification-intent
                COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/notification-history/run-tray-bridge.sh
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-shell.tray-notification-intent PROPERTIES LABELS "ui;headless" TIMEOUT 15)
            add_test(NAME kos-shell.notification-history
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/notification-history/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-shell.notification-history PROPERTIES LABELS ui TIMEOUT 15)
            add_test(NAME kos-shell.notification-history-visual
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/notification-history/run-visual.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-shell.notification-history-visual PROPERTIES LABELS ui TIMEOUT 15)
            add_test(NAME kos-shell.notification-pane
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/notification-history/run-pane.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-shell.notification-pane PROPERTIES
                LABELS "ui;headless" TIMEOUT 25
                ENVIRONMENT "QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
            add_test(NAME kos-shell.notification-source-icons
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/notification-history/run-icons.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-shell.notification-source-icons PROPERTIES LABELS ui TIMEOUT 15)
            find_program(KOS_DBUS_RUN_SESSION_EXECUTABLE NAMES dbus-run-session)
            find_program(KOS_GDBUS_EXECUTABLE NAMES gdbus)
            if(KOS_DBUS_RUN_SESSION_EXECUTABLE AND KOS_GDBUS_EXECUTABLE)
                add_test(NAME kos-shell.notification-history-dbus
                    COMMAND ${KOS_NODE_EXECUTABLE}
                        ${CMAKE_CURRENT_SOURCE_DIR}/tests/notification-history/run-dbus.mjs
                        ${KOS_QUICKSHELL_EXECUTABLE})
                set_tests_properties(kos-shell.notification-history-dbus PROPERTIES LABELS ui TIMEOUT 25)
                add_test(NAME kos-shell.notification-policy-production
                    COMMAND ${KOS_NODE_EXECUTABLE}
                        ${CMAKE_CURRENT_SOURCE_DIR}/tests/notification-history/run-production.mjs
                        ${KOS_QUICKSHELL_EXECUTABLE})
                set_tests_properties(kos-shell.notification-policy-production PROPERTIES LABELS "ui;headless" TIMEOUT 60)
            endif()
            add_test(NAME kos-shell.static-work-runtime
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/static-work/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE}
            )
            set_tests_properties(kos-shell.static-work-runtime PROPERTIES TIMEOUT 15)
            add_test(NAME kos-shell.squircle-mask
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/squircle-mask/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE}
            )
            set_tests_properties(kos-shell.squircle-mask PROPERTIES TIMEOUT 15)
            add_test(NAME kos-shell.liquid-glass-panel
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/liquid-glass-panel/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE}
            )
            set_tests_properties(kos-shell.liquid-glass-panel PROPERTIES TIMEOUT 15)
            # Reads the resolved glass ink in the states 液态玻璃跟随外观模式 can
            # put the glass in. The binding chain it walks (config -> appearance
            # token -> surface/text) renders a plausible colour even when it is
            # broken, so only the resolved values catch it.
            add_test(NAME kos-shell.glass-ink
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/glass-ink/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE}
            )
            set_tests_properties(kos-shell.glass-ink PROPERTIES TIMEOUT 15)
            # 使用系统字体: reads the font.family every surface actually resolved,
            # in both states of the option. A Text that keeps its designed
            # family still renders a plausible interface, so only the resolved
            # value catches a broken link in the chain.
            add_test(NAME kos-shell.system-font
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/system-font/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE}
            )
            set_tests_properties(kos-shell.system-font PROPERTIES TIMEOUT 30
                LABELS "ui;headless"
                ENVIRONMENT "QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml;QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
            # Reads the resolved plate and ink of the Bar's mac style in the
            # states its slider can put it in. The ink follows the wallpaper
            # blended with the plate at the chosen tint, and an ink that read
            # the plate alone still renders plausibly -- it only fails on a
            # bright wallpaper at a low tint, which is what this walks.
            add_test(NAME kos-shell.bar-mac-style
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/bar-mac-style/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE}
            )
            set_tests_properties(kos-shell.bar-mac-style PROPERTIES TIMEOUT 15)
            # Drives the shipping DockIcon's magnificationPointer by hand to
            # check where the Dock decides an icon is hovered. The hover test
            # must not read geometry that the hover lift itself moves, which is
            # what makes the cursor jitter at the slot edge.
            add_test(NAME kos-shell.dock-hover-hit
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock/runtime.mjs hover-hit
                    ${KOS_QUICKSHELL_EXECUTABLE}
            )
            set_tests_properties(kos-shell.dock-hover-hit PROPERTIES TIMEOUT 20)
            add_test(NAME kos-shell.dock-magnification-runtime
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock/runtime.mjs magnification
                    ${KOS_QUICKSHELL_EXECUTABLE}
            )
            set_tests_properties(kos-shell.dock-magnification-runtime PROPERTIES TIMEOUT 20)
            if(KOS_QMLTESTRUNNER_EXECUTABLE)
                add_test(NAME kos-shell.selection-surfaces
                    COMMAND ${KOS_NODE_EXECUTABLE}
                        ${CMAKE_CURRENT_SOURCE_DIR}/tests/selection-surfaces/run.mjs
                        ${KOS_QMLTESTRUNNER_EXECUTABLE}
                        ${KOS_QUICKSHELL_EXECUTABLE})
                set_tests_properties(kos-shell.selection-surfaces PROPERTIES
                    LABELS ui TIMEOUT 20
                    ENVIRONMENT "QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
            endif()
            add_test(NAME kos-shell.traditional-color-runtime
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/traditional-color/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE}
            )
            set_tests_properties(kos-shell.traditional-color-runtime PROPERTIES TIMEOUT 15)
            set_tests_properties(kos-shell.static-work-runtime
                kos-shell.squircle-mask kos-shell.liquid-glass-panel
                kos-shell.glass-ink
                kos-shell.dock-hover-hit kos-shell.dock-magnification-runtime
                PROPERTIES ENVIRONMENT "QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
        endif()
        find_program(KOS_WESTON_EXECUTABLE NAMES weston)
        if(KOS_QUICKSHELL_EXECUTABLE AND KOS_WESTON_EXECUTABLE)
            # The whole shell on a real compositor: tests/shell-startup drives
            # headless weston and waits for quickshell to report
            # "Configuration Loaded". It needs both binaries, so it only ever
            # registers on a machine that can actually run it.
            add_test(NAME kos-shell.startup
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/shell-startup/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE} ${KOS_WESTON_EXECUTABLE}
            )
            set_tests_properties(kos-shell.startup PROPERTIES
                LABELS ui
                TIMEOUT 180
            )
        endif()
        find_program(KOS_LOGIN_KWIN_EXECUTABLE NAMES kwin_wayland)
        if(KOS_QUICKSHELL_EXECUTABLE AND KOS_LOGIN_KWIN_EXECUTABLE)
            find_package(Python3 REQUIRED COMPONENTS Interpreter)
            add_test(NAME kos-shell.installed-startup
                COMMAND ${Python3_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/shell-startup/installed.py
                    --private-compositor
            )
            set_tests_properties(kos-shell.installed-startup PROPERTIES
                LABELS "ui;installed"
                ENVIRONMENT "QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml"
                TIMEOUT 300
            )
        endif()
        add_test(NAME kos-ui.page-cache-policy
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shared/qml/test_page_cache_policy.mjs
        )
        set_tests_properties(kos-ui.page-cache-policy PROPERTIES TIMEOUT 10)
        # These two were passing but were never added to the suite, so nothing
        # ran them: the settings app's Material palette resolution and the
        # traditional colour scheme contract. Pure node, no display needed --
        # which is also why they carry the logic label below, not ui.
        add_test(NAME kos-ui.settings-material
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/settings-material/run.mjs
        )
        set_tests_properties(kos-ui.settings-material PROPERTIES TIMEOUT 10)
        add_test(NAME kos-ui.traditional-color
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/traditional-color/test_traditional_color.mjs
        )
        # The full swatch/contrast sweep takes over 20s on the supported VM.
        # Keep all samples and allow slower CPU-only runners to finish.
        set_tests_properties(kos-ui.traditional-color PROPERTIES TIMEOUT 60)
        # The kdeglobals `font=` grammar 使用系统字体 builds on, without Qt: the
        # shell test above proves the chain, this one pins the parser's corner
        # cases (a serialised QFont, a family alone, the wrong group).
        add_test(NAME kos-ui.system-font-policy
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/system-font/policy.test.mjs
        )
        set_tests_properties(kos-ui.system-font-policy PROPERTIES TIMEOUT 10 LABELS logic)
        # These four were written and passing but never added to the suite, so
        # nothing ran them. They cover the Dock's adaptive layout and auto-hide
        # math, the appearance configuration migration, and the platform
        # window-placement rules -- all pure logic, no display or shell needed.
        add_test(NAME kos-shell.appmenu-refresh
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/bar/test_appmenu_refresh.mjs)
        set_tests_properties(kos-shell.appmenu-refresh PROPERTIES TIMEOUT 10 LABELS logic)
        add_test(NAME kos-shell.appearance-config
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/common/test_appearance_config.mjs
        )
        set_tests_properties(kos-shell.appearance-config PROPERTIES TIMEOUT 10)
        add_test(NAME kos-deskcenter.desktop-outputs
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/deskcenter/test_desktop_outputs.mjs
        )
        set_tests_properties(kos-deskcenter.desktop-outputs PROPERTIES TIMEOUT 10)
        add_test(NAME kos-notifications.activation
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/notifications/test_notification_activation.mjs
        )
        set_tests_properties(kos-notifications.activation PROPERTIES LABELS logic TIMEOUT 10)
        add_test(NAME kos-deskcenter.desktop-stack
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/platform/tests/test_desktop_stack.mjs
        )
        set_tests_properties(kos-deskcenter.desktop-stack PROPERTIES LABELS logic TIMEOUT 10)
        add_test(NAME kos-shell.screen-selection
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/common/test_screen_selection.mjs
        )
        set_tests_properties(kos-shell.screen-selection PROPERTIES TIMEOUT 10)
        add_test(NAME kos-platform.window-placement
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/platform/tests/test_window_placement.mjs
        )
        set_tests_properties(kos-platform.window-placement PROPERTIES TIMEOUT 10)
        # The JSONL transport core shared by PlatformClient and DataClient:
        # reconnect queueing, dedup, expiry and the fail-all path run under a
        # stubbed socket, no daemon or display needed.
        add_test(NAME kos-platform.jsonl-client
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/platform/tests/test_jsonl_client.mjs
        )
        set_tests_properties(kos-platform.jsonl-client PROPERTIES TIMEOUT 10)
    endif()
    # The platform contract test is dependency-free Python with its own
    # __main__ entry point, so a plain interpreter is all it needs. It is the
    # only check that keeps shared/contracts/platform.v1.md, ShortcutsService's
    # default table and the daemon's generated handler in agreement.
    find_program(KOS_PYTHON_EXECUTABLE NAMES python3 python)
    if(KOS_PYTHON_EXECUTABLE)
        add_test(NAME kos-window.firefox-buttons-install
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/tests/test_firefox_buttons.py)
        set_tests_properties(kos-window.firefox-buttons-install PROPERTIES LABELS logic TIMEOUT 15)
        add_test(NAME kos-window.gtk-buttons-install
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tools/tests/test_gtk_window_buttons.py)
        set_tests_properties(kos-window.gtk-buttons-install PROPERTIES LABELS logic TIMEOUT 15)
        add_test(NAME kos-app.dependency-migration
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/app-install/test_dependencies.py)
        set_tests_properties(kos-app.dependency-migration PROPERTIES LABELS data TIMEOUT 10)
        add_test(NAME kos-ci.inventory-contract
            COMMAND ${KOS_PYTHON_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/ci/test_inventory.py)
        set_tests_properties(kos-ci.inventory-contract PROPERTIES LABELS logic TIMEOUT 10)
    endif()
    find_program(KOS_INTERACTION_QMLTEST NAMES qmltestrunner qmltestrunner6
        HINTS /usr/lib/qt6/bin)
    find_program(KOS_INTERACTION_QUICKSHELL NAMES quickshell)
    if(KOS_NODE_EXECUTABLE AND KOS_INTERACTION_QMLTEST)
        add_test(NAME kos-shell.inputmethod-motion
            COMMAND ${KOS_NODE_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/inputmethod/run.mjs
                ${KOS_INTERACTION_QMLTEST})
        set_tests_properties(kos-shell.inputmethod-motion PROPERTIES LABELS "ui;headless" TIMEOUT 20)
    endif()
    if(KOS_NODE_EXECUTABLE)
        add_test(NAME kos-shell.inputmethod-placement
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/inputmethod/test_inputmethod_placement.mjs)
        add_test(NAME kos-shell.inputmethod-status
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/inputmethod/test_inputmethod_status_dismissal.mjs)
        set_tests_properties(kos-shell.inputmethod-placement kos-shell.inputmethod-status
            PROPERTIES LABELS logic TIMEOUT 10)
    endif()
    find_program(KOS_TEST_KWIN NAMES kwin_wayland)
    find_program(KOS_TEST_DBUS_RUN NAMES dbus-run-session)
    if(KOS_PYTHON_EXECUTABLE AND KOS_INTERACTION_QUICKSHELL AND KOS_TEST_KWIN AND KOS_TEST_DBUS_RUN)
        add_test(NAME kos-ui.tray-color
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/tray-color/run.py)
        set_tests_properties(kos-ui.tray-color PROPERTIES
            ENVIRONMENT "QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml;QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml"
            LABELS "ui;compositor" TIMEOUT 30 RUN_SERIAL TRUE)
        add_test(NAME kos-ui.status-panels
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/status-area/run-panels.py --vulkan)
        add_test(NAME kos-ui.status-panels-opengl
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/status-area/run-panels.py --opengl --scale-2)
        add_test(NAME kos-ui.battery-mode-geometry
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/status-area/run-panels.py --battery-modes --opengl --scale-105)
        set_tests_properties(kos-ui.status-panels kos-ui.status-panels-opengl kos-ui.battery-mode-geometry PROPERTIES
            ENVIRONMENT "QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml;QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml"
            LABELS "ui;compositor" TIMEOUT 45 RUN_SERIAL TRUE)
        add_test(NAME kos-ui.control-center-modules
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/control-center/run.py)
        set_tests_properties(kos-ui.control-center-modules PROPERTIES
            ENVIRONMENT "QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml;QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml"
            LABELS "ui;headless" TIMEOUT 40 RUN_SERIAL TRUE)
        add_test(NAME kos-ui.clipboard-placement
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/clipboard-placement/run.py)
        set_tests_properties(kos-ui.clipboard-placement PROPERTIES LABELS ui TIMEOUT 40)
    endif()
    if(KOS_INTERACTION_QMLTEST)
        # Exercise the shipping controller without importing Quickshell-only
        # notification singletons into the plain Qt QuickTest runner.
        set(kos_notification_test_module "${CMAKE_BINARY_DIR}/tests/qml/Kos/Test/NotificationOpen")
        foreach(component NotificationOpenController.qml NotificationActivation.mjs)
            configure_file(
                "${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/notifications/${component}"
                "${kos_notification_test_module}/${component}" COPYONLY)
        endforeach()
        file(WRITE "${kos_notification_test_module}/qmldir"
            "module Kos.Test.NotificationOpen\nNotificationOpenController 1.0 NotificationOpenController.qml\n")
        add_test(NAME kos-shell.notification-open
            COMMAND ${KOS_INTERACTION_QMLTEST}
                -import "${CMAKE_BINARY_DIR}/tests/qml"
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/notification-open/tst_open.qml)
        set_tests_properties(kos-shell.notification-open PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS "ui;headless" TIMEOUT 20)
        add_test(NAME kos-ui.motion-tokens
            COMMAND ${KOS_INTERACTION_QMLTEST}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/motion-tokens)
        set_tests_properties(kos-ui.motion-tokens PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS "ui;headless" TIMEOUT 20)
        add_test(NAME kos-ui.interaction-controls
            COMMAND ${KOS_INTERACTION_QMLTEST}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/interaction-controls/tst_controls.qml)
        set_tests_properties(kos-ui.interaction-controls PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS "ui;headless" TIMEOUT 20)
        # The shipping motion components only need QtQuick. Importing their
        # entire launcher directory also loads Quickshell-only singletons,
        # whose embedded plugins are unavailable to plain qmltestrunner.
        set(kos_motion_test_module "${CMAKE_BINARY_DIR}/tests/qml/Kos/Test/LauncherMotion")
        foreach(component LauncherMotion LauncherIconMotion)
            set(motion_source "${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/applauncher/${component}.qml")
            set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${motion_source}")
            file(READ "${motion_source}" motion_qml)
            string(REPLACE "../../../shared/qml/foundation"
                "file:${CMAKE_CURRENT_SOURCE_DIR}/shared/qml/foundation" motion_qml "${motion_qml}")
            file(MAKE_DIRECTORY "${kos_motion_test_module}")
            file(WRITE "${kos_motion_test_module}/${component}.qml" "${motion_qml}")
        endforeach()
        file(WRITE "${kos_motion_test_module}/qmldir"
            "module Kos.Test.LauncherMotion\nLauncherMotion 1.0 LauncherMotion.qml\nLauncherIconMotion 1.0 LauncherIconMotion.qml\n")
        # tst_motion.qml loads apps/settings/main.qml, which imports the static
        # Kos.Demo module that plain qmltestrunner cannot load. Run the suite
        # through a QuickTest host that registers the plugin instead.
        find_package(Qt6 6.5 QUIET COMPONENTS QuickTest QuickControls2)
        set(kos_motion_test_runner ${KOS_INTERACTION_QMLTEST})
        if(TARGET Qt6::QuickTest)
            if(NOT TARGET kos_demo_ui)
                add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/shared/demo-ui
                    ${CMAKE_CURRENT_BINARY_DIR}/demo-ui)
            endif()
            qt_add_executable(kos-shared-motion-tests
                tests/interaction-controls/QmlTestMain.cpp)
            target_link_libraries(kos-shared-motion-tests PRIVATE Qt6::QuickTest
                kos_demo_ui kos_demo_ui_plugin)
            set(kos_motion_test_runner "$<TARGET_FILE:kos-shared-motion-tests>")
        endif()
        add_test(NAME kos-ui.shared-motion
            COMMAND ${kos_motion_test_runner}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/interaction-controls/tst_motion.qml)
        set_tests_properties(kos-ui.shared-motion PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/tests/qml;QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/tests/qml"
            LABELS "ui;headless" TIMEOUT 20)
        add_test(NAME kos-ui.lyric-transition
            COMMAND ${KOS_INTERACTION_QMLTEST}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/interaction-controls/tst_lyrics.qml)
        set_tests_properties(kos-ui.lyric-transition PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS ui TIMEOUT 15)
        add_test(NAME kos-ui.kinetic-scroll
            COMMAND ${KOS_INTERACTION_QMLTEST}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/interaction-controls/tst_kinetic_scroll.qml)
        set_tests_properties(kos-ui.kinetic-scroll PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS "ui;headless" TIMEOUT 30)
        add_test(NAME kos-ui.kinetic-input
            COMMAND ${KOS_INTERACTION_QMLTEST}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/interaction-controls/tst_kinetic_input.qml)
        set_tests_properties(kos-ui.kinetic-input PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS "ui;headless" TIMEOUT 20)
    endif()
    if(KOS_PYTHON_EXECUTABLE AND KOS_INTERACTION_QUICKSHELL)
        add_test(NAME kos-ui.interaction-runtime
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/interaction-runtime/run.py)
        add_test(NAME kos-ui.widget-experience
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/widget-experience/run.py --private-compositor)
        add_test(NAME kos-ui.widget-resize
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/widget-resize/run.py --private-compositor)
        add_test(NAME kos-ui.desktop-overview
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/desktop-overview/run.py --private-compositor)
        add_test(NAME kos-ui.popup-motion
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/popup-motion/run.py)
        if(KOS_BUILD_KWIN_PLUGINS)
            add_test(NAME kos-ui.surface-shape-sync
                COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/popup-motion/run.py --verify-wayland)
            set_tests_properties(kos-ui.surface-shape-sync PROPERTIES
                ENVIRONMENT "QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml;QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml"
                LABELS "ui;kwin" TIMEOUT 60 RUN_SERIAL TRUE)
        endif()
        set_tests_properties(kos-ui.interaction-runtime kos-ui.widget-experience kos-ui.widget-resize kos-ui.popup-motion PROPERTIES
            LABELS ui TIMEOUT 60 RUN_SERIAL TRUE)
        set_tests_properties(kos-ui.widget-resize PROPERTIES
            LABELS "ui;widgets" TIMEOUT 120
            ENVIRONMENT "QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml;QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
        set_tests_properties(kos-ui.widget-experience PROPERTIES
            LABELS "ui;widgets" TIMEOUT 90
            ENVIRONMENT "QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml;QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
        set_tests_properties(kos-ui.desktop-overview PROPERTIES
            LABELS "ui;widgets" TIMEOUT 60 RUN_SERIAL TRUE
            ENVIRONMENT "QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml;QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
    endif()
    if(KOS_PYTHON_EXECUTABLE)
        add_test(NAME kos-platform.contracts
            COMMAND ${KOS_PYTHON_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/platform/tests/test_contract.py
        )
        set_tests_properties(kos-platform.contracts PROPERTIES TIMEOUT 10)
    endif()
    # Labels group the suite so a caller can run one layer without the others.
    # `tools/run-tests.sh` and CI both drive `ctest -L`, so a test only has to
    # be listed once, here, to join a layer:
    #
    #   logic    pure computation, node or python, no display and no service
    #   platform the daemon's contract test
    #   ui       needs a QML engine (and, for the panel tests, a compositor)
    #
    # The data/service layer is labelled where those tests are registered, in
    # services/data-service, which remains a core Shell dependency.
    # Every label has to be applied under the same condition that registered
    # the test: set_tests_properties aborts the configure when a named test
    # does not exist, and each source below is optional -- the node tests need
    # node, date-projection additionally needs qmltestrunner, the three runtime
    # tests need an installed quickshell (absent in a CI container), and the
    # contract test needs python.
    if(KOS_NODE_EXECUTABLE)
        set_tests_properties(kos-deskcenter.widget-layout kos-shell.date-buckets
            kos-shell.squircle kos-shell.tray-attention-match
            kos-shell.notification-count-match kos-shell.control-center-submenu-state
            kos-shell.visibility-policy
            kos-shell.wallpaper-slideshow kos-shell.wallpaper-handoff
            kos-shell.wallpaper-transitions kos-shell.wallpaper-preview
            kos-shell.theme-wallpaper-policy
            kos-shell.theme-wallpaper-state
            kos-shell.stage-geometry kos-shell.stage-groups kos-shell.stage-effects kos-shell.stage-protocol
            kos-shell.stage-visibility
            kos-shell.appearance-config
            kos-deskcenter.desktop-outputs
            kos-shell.screen-selection
            kos-ui.visual-contract kos-ui.color-scheme
            kos-ui.page-cache-policy kos-ui.settings-material
            kos-ui.traditional-color
            PROPERTIES LABELS logic)
        set_tests_properties(kos-platform.window-placement
            kos-platform.jsonl-client PROPERTIES LABELS platform)
    endif()
    if(KOS_QMLTESTRUNNER_EXECUTABLE)
        set_tests_properties(kos-shell.date-projection PROPERTIES LABELS logic)
    endif()
    if(KOS_QUICKSHELL_EXECUTABLE)
        set_tests_properties(kos-shell.static-work-runtime kos-shell.squircle-mask
            kos-shell.liquid-glass-panel kos-shell.glass-ink
            kos-shell.bar-mac-style
            kos-shell.traditional-color-runtime
            kos-shell.dock-hover-hit kos-shell.dock-magnification-runtime
            PROPERTIES LABELS ui)
    endif()
    if(KOS_PYTHON_EXECUTABLE)
        set_tests_properties(kos-platform.contracts PROPERTIES LABELS platform)
    endif()
endif()

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    DBus
    Gui
    Network
    Qml
    Quick
    QuickControls2
)
find_package(KF6WindowSystem 6.0 QUIET)
if(BUILD_TESTING)
    find_package(Qt6 6.5 REQUIRED COMPONENTS Test)
    add_executable(kos-window-effect-policy-test
        kwin/common/tests/windoweffectpolicy_test.cpp)
    target_link_libraries(kos-window-effect-policy-test PRIVATE Qt6::Core)
    add_test(NAME kos-window.effect-policy COMMAND kos-window-effect-policy-test)
    set_tests_properties(kos-window.effect-policy PROPERTIES LABELS platform TIMEOUT 10)

    add_executable(kos-stage-desktop-policy-test
        kwin/kwin-effects-stageanim/tests/test_desktop_policy.cpp)
    target_link_libraries(kos-stage-desktop-policy-test PRIVATE Qt6::Core)
    add_test(NAME kos-stage.desktop-policy COMMAND kos-stage-desktop-policy-test)
    set_tests_properties(kos-stage.desktop-policy PROPERTIES LABELS platform TIMEOUT 10)
    qt_add_executable(kos-legacy-glass-blur-test
        kwin/glass-effect/tests/test_legacy_blur_region.cpp)
    target_link_libraries(kos-legacy-glass-blur-test PRIVATE Qt6::Core Qt6::Gui)
    add_test(NAME kos-glass.legacy-blur-region COMMAND kos-legacy-glass-blur-test)
    set_tests_properties(kos-glass.legacy-blur-region PROPERTIES LABELS platform TIMEOUT 10)
    qt_add_executable(kos-desktop-glass-blur-test
        kwin/glass-effect/tests/test_desktop_blur.cpp)
    target_link_libraries(kos-desktop-glass-blur-test PRIVATE Qt6::Core Qt6::Gui)
    add_test(NAME kos-glass.desktop-blur COMMAND kos-desktop-glass-blur-test)
    set_tests_properties(kos-glass.desktop-blur PROPERTIES LABELS platform TIMEOUT 10)
    qt_add_executable(kos-overview-panel-projection-test
        kwin/glass-effect/tests/test_overview_panel_projection.cpp)
    target_link_libraries(kos-overview-panel-projection-test PRIVATE Qt6::Quick)
    add_test(NAME kos-glass.overview-panel-projection COMMAND kos-overview-panel-projection-test)
    set_tests_properties(kos-glass.overview-panel-projection PROPERTIES
        LABELS platform TIMEOUT 10
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")
endif()

qt_standard_project_setup(REQUIRES 6.5)
qt_policy(SET QTP0001 NEW)
if(Qt6_VERSION VERSION_GREATER_EQUAL 6.8)
    qt_policy(SET QTP0004 NEW)
endif()

# Keep every generated QML module below one canonical import root. This lets
# qmllint and qmlimportscanner resolve Kos.Ui from each standalone app.
set(QT_QML_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml")
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

if(KOS_BUILD_PLATFORM)
    add_subdirectory(platform)
    add_subdirectory(apps/settings)
endif()

# Shared telemetry/weather is a core service, independent of optional apps.
# Keep its Go coverage even in platform-disabled CI configurations.
if(KOS_BUILD_PLATFORM OR BUILD_TESTING)
    add_subdirectory(services/data-service)
endif()

if(BUILD_TESTING)
    # apps/lockscreen is a data-only Plasma Look-and-Feel package: there is no
    # target to build, so the check is a script. It compiles a throwaway probe
    # against KF6::Package that reproduces the greeter's own skin selection --
    # the trap it guards is invisible otherwise, because a metadata.json whose
    # "X-Plasma-APIVersion" is nested inside "KPlugin" makes the greeter fall
    # back to a KDE default skin without logging anything a locked session can
    # show. Missing development headers fail the check rather than skip it.
    add_test(NAME kos-lockscreen.theme-resolution
        COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/apps/lockscreen/tests/theme-resolution/run.sh")
    # Labelled here rather than in the block above: `if(TARGET ...)` cannot see
    # tests (they are not build targets), and this test is registered only now,
    # so an earlier set_tests_properties would name a test that does not exist
    # yet. Without this line the test carries no label and no layer runs it.
    set_tests_properties(kos-lockscreen.theme-resolution PROPERTIES LABELS "ui;headless" TIMEOUT 30)
    if(KOS_INTERACTION_QMLTEST)
        add_test(NAME kos-lockscreen.media-selection
            COMMAND dbus-run-session -- ${KOS_INTERACTION_QMLTEST}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/apps/lockscreen/tests/media)
        set_tests_properties(kos-lockscreen.media-selection PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QML_DISABLE_DISK_CACHE=1"
            LABELS "ui;headless" TIMEOUT 15)
        add_test(NAME kos-lockscreen.wake-authentication
            COMMAND dbus-run-session -- ${KOS_INTERACTION_QMLTEST}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/apps/lockscreen/tests/headless/tst_wake.qml)
        set_tests_properties(kos-lockscreen.wake-authentication PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QML_DISABLE_DISK_CACHE=1"
            LABELS "ui;headless" TIMEOUT 30)
    endif()
endif()

# The shell imports this QML module even without compositor effects.
if(KOS_BUILD_PLATFORM OR KOS_BUILD_KWIN_PLUGINS)
    add_subdirectory(shell/native/surface-shape)
endif()

if(KOS_BUILD_KWIN_PLUGINS)
    add_subdirectory(kwin/dock-window-animation)
    add_subdirectory(kwin/context-menu-input)
    add_subdirectory(kwin/kos-bridge)
    add_subdirectory(kwin/kos-decoration)
    add_subdirectory(kwin/kwin-effects-stageanim)
    if(BUILD_TESTING AND KOS_PYTHON_EXECUTABLE)
        find_program(KOS_STAGE_QUICKSHELL_EXECUTABLE NAMES quickshell qs)
        find_program(KOS_STAGE_KWIN_EXECUTABLE NAMES kwin_wayland)
        find_program(KOS_STAGE_QDBUS_EXECUTABLE NAMES qdbus6)
        find_program(KOS_STAGE_DBUS_EXECUTABLE NAMES dbus-run-session)
        if(KOS_STAGE_QUICKSHELL_EXECUTABLE AND KOS_STAGE_KWIN_EXECUTABLE
                AND KOS_STAGE_QDBUS_EXECUTABLE AND KOS_STAGE_DBUS_EXECUTABLE)
            add_test(NAME kos-stage.static-desktop-compositor
                COMMAND ${KOS_PYTHON_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/stage-visibility/static_compositor.py
                    $<TARGET_FILE:stageanim13>
                    --quickshell ${KOS_STAGE_QUICKSHELL_EXECUTABLE}
                    --output ${CMAKE_BINARY_DIR}/stage-static-compositor)
            set_tests_properties(kos-stage.static-desktop-compositor PROPERTIES LABELS ui TIMEOUT 40)
        endif()
    endif()
endif()

# The spatial wallpaper mesh is an optional QML extension, built only when the
# depth engine is. Keep Qt Quick 3D and OpenCV outside the shell's mandatory
# dependencies so systems without them retain the existing shader renderer.
if(KOS_BUILD_PLATFORM AND KOS_SPATIAL_ENABLED)
    find_package(Qt6 QUIET COMPONENTS Quick3D)
    if(TARGET Qt6::Quick3D AND Qt6_VERSION VERSION_GREATER_EQUAL 6.5)
        add_subdirectory(shell/native/spatial3d)
    else()
        message(STATUS "Qt Quick 3D not found; spatial mesh renderer disabled")
    endif()
endif()

# No install() rules for the shell and shared QML trees, on purpose: user-side
# deployment is owned by tools/kosctl (deploy_artifacts) and Nix's own
# installPhase, which both copy from the source tree. Rules here would be a
# second, drifting copy of the same file list -- and nothing in this repo ever
# ran `cmake --install` for them anyway.
