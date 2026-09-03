cmake_minimum_required(VERSION 3.21)

project(NextKdeApps
    VERSION 0.1.0
    DESCRIPTION "Standalone applications for the NextKde desktop"
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

include(CTest)
include(GNUInstallDirs)

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

qt_standard_project_setup(REQUIRES 6.5)
qt_policy(SET QTP0001 NEW)
if(Qt6_VERSION VERSION_GREATER_EQUAL 6.8)
    qt_policy(SET QTP0004 NEW)
endif()

# Keep every generated QML module below one canonical import root. This is
# required for qmllint and qmlimportscanner to resolve Kos.Ui from each
# independently built application module.
set(QT_QML_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml")

option(KOS_BUILD_CALENDAR "Build the Calendar application" ON)
option(KOS_BUILD_TODO "Build the Todo application" ON)
option(KOS_BUILD_WEATHER "Build the Weather application" ON)
option(KOS_BUILD_MUSIC "Build the Music application" ON)

if(KOS_BUILD_CALENDAR OR KOS_BUILD_TODO)
    find_package(KF6CalendarCore 6.0 REQUIRED)
endif()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

add_subdirectory(shared/qml)
add_subdirectory(apps/common)

if(KOS_BUILD_CALENDAR OR KOS_BUILD_TODO)
    add_subdirectory(shared/pim)
    add_subdirectory(services/pim-service)
endif()

if(KOS_BUILD_WEATHER)
    add_subdirectory(services/shell-data-service)
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
