cmake_minimum_required(VERSION 3.21)

project(kos-platform LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Concurrent DBus Gui Network)
find_package(KF6CoreAddons REQUIRED)
find_package(KF6IconThemes REQUIRED)
find_package(KF6GlobalAccel REQUIRED)
find_package(KF6KIO REQUIRED)

qt_standard_project_setup()

qt_add_executable(kos-platform
    src/daemon/main.cpp
    src/daemon/PlatformServer.cpp
    src/daemon/PlatformServer.h
    src/daemon/Shortcuts.cpp
    src/daemon/Shortcuts.h
    src/kwin/KWinBridge.cpp
    src/kwin/KWinBridge.h
)

target_link_libraries(kos-platform PRIVATE
    Qt6::Core
    Qt6::Concurrent
    Qt6::DBus
    Qt6::Gui
    Qt6::Network
    KF6::CoreAddons
    KF6::IconThemes
    KF6::GlobalAccel
    KF6::KIOGui
)

install(TARGETS kos-platform
    RUNTIME DESTINATION libexec
)

install(FILES kwin/window-bridge.js
    DESTINATION share/kos/platform/kwin
)

# Startup smoke for the daemon itself: run the freshly built binary on a
# private session bus, wait for its READY line, answer-check platform.ping
# and confirm SIGTERM stops it cleanly. It needs an interpreter and
# dbus-run-session, so it registers only when both exist.
if(BUILD_TESTING)
    if(NOT KOS_PYTHON_EXECUTABLE)
        find_program(KOS_PYTHON_EXECUTABLE NAMES python3 python)
    endif()
    find_program(DBUS_RUN_SESSION_EXECUTABLE dbus-run-session)
    if(KOS_PYTHON_EXECUTABLE AND DBUS_RUN_SESSION_EXECUTABLE)
        add_test(NAME kos-platform.startup
            COMMAND ${KOS_PYTHON_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_platform_startup.py
                $<TARGET_FILE:kos-platform>
        )
        set_tests_properties(kos-platform.startup PROPERTIES
            LABELS platform
            TIMEOUT 60
        )
    endif()
endif()
