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
endif()

if(KOS_BUILD_PLATFORM)
    # Quickshell loads this tree at runtime; CMake copies the complete source
    # tree and does not attempt to compile QML into the platform binary.
    install(DIRECTORY shell/ DESTINATION share/kos/shell)
    install(DIRECTORY shared/ DESTINATION share/kos/shared)
    # apps/settings/main.qml is also runnable directly from an installed prefix.
    install(DIRECTORY shared/qml/controls/ DESTINATION share/shared/qml/controls)
endif()
