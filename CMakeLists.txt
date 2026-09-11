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
        find_program(KOS_QUICKSHELL_EXECUTABLE NAMES quickshell)
        if(KOS_QUICKSHELL_EXECUTABLE)
            add_test(NAME kos-shell.static-work-runtime
                COMMAND ${KOS_NODE_EXECUTABLE}
                    ${CMAKE_CURRENT_SOURCE_DIR}/tests/static-work/run.mjs
                    ${KOS_QUICKSHELL_EXECUTABLE}
            )
            set_tests_properties(kos-shell.static-work-runtime PROPERTIES TIMEOUT 15)
        endif()
        add_test(NAME kos-ui.page-cache-policy
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/shared/qml/test_page_cache_policy.mjs
        )
        set_tests_properties(kos-ui.page-cache-policy PROPERTIES TIMEOUT 10)
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
    add_subdirectory(integrations/kwin/dock-window-animation)
    add_subdirectory(integrations/kwin/context-menu-input)
    add_subdirectory(integrations/kwin/decoration-liquid-glass)
endif()

if(KOS_BUILD_PLATFORM)
    # Quickshell loads this tree at runtime; CMake copies the complete source
    # tree and does not attempt to compile QML into the platform binary.
    install(DIRECTORY shell/ DESTINATION share/kos/shell)
    install(DIRECTORY shared/ DESTINATION share/kos/shared)
    # apps/settings/main.qml is also runnable directly from an installed prefix.
    install(DIRECTORY shared/qml/controls/ DESTINATION share/shared/qml/controls)
endif()
