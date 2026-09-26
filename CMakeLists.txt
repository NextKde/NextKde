cmake_minimum_required(VERSION 3.21)

project(KOS VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

include(CTest)
include(GNUInstallDirs)

option(KOS_BUILD_PLATFORM "Build the KOS platform daemon and settings app" ON)
option(KOS_BUILD_KWIN_PLUGINS "Build the two KWin effect plugins" ON)
option(KOS_BUILD_CALENDAR "Build the Calendar application" OFF)
option(KOS_BUILD_TODO "Build the Todo application" OFF)
option(KOS_BUILD_WEATHER "Build the Weather application" OFF)
option(KOS_BUILD_MUSIC "Build the Music application" OFF)

if(BUILD_TESTING)
    find_program(KOS_NODE_EXECUTABLE NAMES node)
    if(KOS_NODE_EXECUTABLE)
        add_test(NAME kos-deskcenter.density-metrics
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/desktop-density/test_metrics.mjs)
        set_tests_properties(kos-deskcenter.density-metrics PROPERTIES LABELS logic TIMEOUT 10)
        add_test(NAME kos-deskcenter.widget-layout
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/deskcenter/test_widget_layout.mjs
        )
        set_tests_properties(kos-deskcenter.widget-layout PROPERTIES TIMEOUT 10)
        add_test(NAME kos-ui.visual-contract
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shared/qml/test_visual_contract.mjs
        )
        set_tests_properties(kos-ui.visual-contract PROPERTIES TIMEOUT 10)
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
        add_test(NAME kos-shell.visibility-policy
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/common/test_visibility_policy.mjs
        )
        set_tests_properties(kos-shell.visibility-policy PROPERTIES TIMEOUT 10)
        find_program(KOS_QMLTESTRUNNER_EXECUTABLE NAMES qmltestrunner
            HINTS /usr/lib/qt6/bin)
        if(KOS_QMLTESTRUNNER_EXECUTABLE)
            add_test(NAME kos-shell.date-projection
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/date-projection/run.mjs
                    ${KOS_QMLTESTRUNNER_EXECUTABLE}
            )
            set_tests_properties(kos-shell.date-projection PROPERTIES TIMEOUT 15)
        endif()
        add_test(NAME kos-shell.window-placement-updates
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/dock/test_window_placement_updates.mjs
        )
        set_tests_properties(kos-shell.window-placement-updates PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.window-record-index
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/dock/test_window_record_index.mjs
        )
        set_tests_properties(kos-shell.window-record-index PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.wallpaper-color-source
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/dock/test_wallpaper_color_source.mjs
        )
        set_tests_properties(kos-shell.wallpaper-color-source PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.process-identity
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/dock/test_process_identity.mjs
        )
        set_tests_properties(kos-shell.process-identity PROPERTIES TIMEOUT 10)
        find_program(KOS_QUICKSHELL_EXECUTABLE NAMES quickshell)
        if(KOS_QUICKSHELL_EXECUTABLE)
            add_test(NAME kos-deskcenter.density-runtime
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/desktop-density/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-deskcenter.density-runtime PROPERTIES LABELS ui TIMEOUT 15)
            add_test(NAME kos-shell.dock-builtins
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock-builtins/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-shell.dock-builtins PROPERTIES
                LABELS ui TIMEOUT 25
                ENVIRONMENT "QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml")
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
            # Drives the shipping DockIcon's magnificationPointer by hand to
            # check where the Dock decides an icon is hovered. The hover test
            # must not read geometry that the hover lift itself moves, which is
            # what makes the cursor jitter at the slot edge.
            add_test(NAME kos-shell.dock-hover-hit
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/dock-hover-hit/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE}
            )
            set_tests_properties(kos-shell.dock-hover-hit PROPERTIES TIMEOUT 20)
            add_test(NAME kos-shell.traditional-color-runtime
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/traditional-color/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE}
            )
            set_tests_properties(kos-shell.traditional-color-runtime PROPERTIES TIMEOUT 15)
            set_tests_properties(kos-shell.static-work-runtime
                kos-shell.squircle-mask kos-shell.liquid-glass-panel
                kos-shell.glass-ink
                kos-shell.dock-hover-hit
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
        set_tests_properties(kos-ui.traditional-color PROPERTIES TIMEOUT 10)

        # These four were written and passing but never added to the suite, so
        # nothing ran them. They cover the Dock's adaptive layout and auto-hide
        # math, the appearance configuration migration, and the platform
        # window-placement rules -- all pure logic, no display or shell needed.
        add_test(NAME kos-shell.appearance-config
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/common/test_appearance_config.mjs
        )
        set_tests_properties(kos-shell.appearance-config PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.dock-adaptive
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/dock/test_adaptive.mjs
        )
        set_tests_properties(kos-shell.dock-adaptive PROPERTIES TIMEOUT 10)
        add_test(NAME kos-shell.dock-autohide
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/dock/test_autohide.mjs
        )
        set_tests_properties(kos-shell.dock-autohide PROPERTIES TIMEOUT 10)
        add_test(NAME kos-deskcenter.desktop-outputs
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shell/desktop/modules/deskcenter/test_desktop_outputs.mjs
        )
        set_tests_properties(kos-deskcenter.desktop-outputs PROPERTIES TIMEOUT 10)
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
    find_program(KOS_INTERACTION_QMLTEST NAMES qmltestrunner qmltestrunner6
        HINTS /usr/lib/qt6/bin)
    find_program(KOS_INTERACTION_QUICKSHELL NAMES quickshell)
    if(KOS_INTERACTION_QMLTEST)
        add_test(NAME kos-ui.interaction-controls
            COMMAND ${KOS_INTERACTION_QMLTEST}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/interaction-controls/tst_controls.qml)
        set_tests_properties(kos-ui.interaction-controls PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS ui TIMEOUT 20)
    endif()
    if(KOS_PYTHON_EXECUTABLE AND KOS_INTERACTION_QUICKSHELL)
        add_test(NAME kos-ui.interaction-runtime
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/interaction-runtime/run.py)
        add_test(NAME kos-ui.widget-experience
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/widget-experience/run.py)
        set_tests_properties(kos-ui.interaction-runtime kos-ui.widget-experience PROPERTIES
            LABELS ui TIMEOUT 60 RUN_SERIAL TRUE)
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
    # apps/common, apps/weather, apps/music, services/pim-service and
    # services/data-service, because those directories only exist when their
    # parent feature is configured.
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
            kos-shell.window-placement-updates
            kos-shell.window-record-index kos-shell.wallpaper-color-source
            kos-shell.process-identity
            kos-shell.appearance-config kos-shell.dock-adaptive
            kos-shell.dock-autohide kos-deskcenter.desktop-outputs
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
            kos-shell.traditional-color-runtime
            kos-shell.dock-hover-hit
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
endif()
if(KOS_BUILD_CALENDAR OR KOS_BUILD_TODO)
    find_package(KF6CalendarCore 6.0 REQUIRED)
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

if(KOS_BUILD_CALENDAR OR KOS_BUILD_TODO OR KOS_BUILD_WEATHER OR KOS_BUILD_MUSIC)
    add_subdirectory(shared/qml)
    add_subdirectory(apps/common)
endif()

if(KOS_BUILD_CALENDAR OR KOS_BUILD_TODO)
    add_subdirectory(shared/pim)
    add_subdirectory(services/pim-service)
endif()

if(KOS_BUILD_WEATHER)
    add_subdirectory(services/data-service)
endif()

include(KosApplication)

# Every application ships behind an opt-in flag, but its tests must not: the
# C++ suites that cover app-owned code are the only thing that exercises
# ApplicationPreferences, WeatherClient, the music database and the PIM store,
# and gating them behind their own app turned the whole layer into tests that
# nothing ever ran. Each directory below configures and builds its test targets
# without turning its application on -- the flags above still decide whether the
# app itself is built.
#
#  - apps/common:      kos_app_core is a plain STATIC library holding no app
#                      code, so the preference store test only needs this
#                      directory.
#  - apps/weather:     the client test compiles src/WeatherClient.cpp directly
#                      rather than linking the app, so no data-service is
#                      involved.
#  - apps/music:       needs PkgConfig plus gstreamer/taglib; skipped when they
#                      are missing so such a machine still configures the rest.
#  - services/pim-service: the store/DBus tests link kos_pim_service_core, and
#                      the two DBus tests also run the service binary, which
#                      this directory builds unconditionally.
#  - services/data-service: a bare `go test ./...`, independent of any C++.
#
# This block sits after include(KosApplication) because apps/music and
# services/pim-service call kos_add_application, which that include defines.
if(BUILD_TESTING)
    if(NOT (KOS_BUILD_CALENDAR OR KOS_BUILD_TODO OR KOS_BUILD_WEATHER
            OR KOS_BUILD_MUSIC))
        add_subdirectory(apps/common)
    endif()

    if(NOT (KOS_BUILD_CALENDAR OR KOS_BUILD_TODO))
        find_package(KF6CalendarCore 6.0 QUIET)
        if(TARGET KF6::CalendarCore)
            add_subdirectory(shared/pim)
            add_subdirectory(services/pim-service)
        endif()
    endif()

    if(NOT KOS_BUILD_WEATHER)
        add_subdirectory(services/data-service)
        # Tests only: KOS_WEATHER_TESTS_ONLY makes apps/weather skip
        # kos_add_application, so the client test runs without Kos::Ui or the
        # data-service build target the application would drag in.
        set(KOS_WEATHER_TESTS_ONLY ON)
        add_subdirectory(apps/weather)
        unset(KOS_WEATHER_TESTS_ONLY)
    endif()

    if(NOT KOS_BUILD_MUSIC)
        find_package(PkgConfig QUIET)
        if(PkgConfig_FOUND)
            pkg_check_modules(KOS_MUSIC_GSTREAMER QUIET IMPORTED_TARGET
                gstreamer-1.0 gstreamer-audio-1.0 gstreamer-pbutils-1.0)
            pkg_check_modules(KOS_MUSIC_TAGLIB QUIET IMPORTED_TARGET
                taglib>=1.12)
            if(TARGET PkgConfig::KOS_MUSIC_GSTREAMER
                    AND TARGET PkgConfig::KOS_MUSIC_TAGLIB)
                # Tests only: KOS_MUSIC_TESTS_ONLY makes this directory skip
                # kos_add_application, so no app (and no Kos::Ui dependency)
                # is pulled in.
                set(KOS_MUSIC_TESTS_ONLY ON)
                add_subdirectory(apps/music)
                unset(KOS_MUSIC_TESTS_ONLY)
            endif()
        endif()
    endif()

    # apps/lockscreen is a data-only Plasma Look-and-Feel package: there is no
    # target to build, so the check is a script. It compiles a throwaway probe
    # against KF6::Package that reproduces the greeter's own skin selection --
    # the trap it guards is invisible otherwise, because a metadata.json whose
    # "X-Plasma-APIVersion" is nested inside "KPlugin" makes the greeter fall
    # back to a KDE default skin without logging anything a locked session can
    # show. The script exits 0 (skip) when the development headers are missing.
    add_test(NAME kos-lockscreen.theme-resolution
        COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/apps/lockscreen/tests/theme-resolution/run.sh")
    # Labelled here rather than in the block above: `if(TARGET ...)` cannot see
    # tests (they are not build targets), and this test is registered only now,
    # so an earlier set_tests_properties would name a test that does not exist
    # yet. Without this line the test carries no label and no layer runs it.
    set_tests_properties(kos-lockscreen.theme-resolution PROPERTIES LABELS ui)
endif()

if(KOS_BUILD_CALENDAR)
    add_subdirectory(apps/calendar)
endif()
if(KOS_BUILD_TODO)
    add_subdirectory(apps/todo)
endif()
if(KOS_BUILD_WEATHER)
    add_subdirectory(apps/weather)
endif()
if(KOS_BUILD_MUSIC)
    add_subdirectory(apps/music)
endif()

if(KOS_BUILD_KWIN_PLUGINS)
    add_subdirectory(integrations/quickshell/surface-shape)
    add_subdirectory(integrations/kwin/dock-window-animation)
    add_subdirectory(integrations/kwin/context-menu-input)
    add_subdirectory(integrations/kwin/decoration-liquid-glass)
endif()

# No install() rules for the shell and shared QML trees, on purpose: user-side
# deployment is owned by tools/kosctl (deploy_artifacts) and Nix's own
# installPhase, which both copy from the source tree. Rules here would be a
# second, drifting copy of the same file list -- and nothing in this repo ever
# ran `cmake --install` for them anyway.
