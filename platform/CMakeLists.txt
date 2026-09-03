cmake_minimum_required(VERSION 3.21)

project(kos-platform LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Concurrent DBus Gui Network)
find_package(KF6IconThemes REQUIRED)

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
    KF6::IconThemes
)

install(TARGETS kos-platform
    RUNTIME DESTINATION libexec
)

install(FILES kwin/window-bridge.js
    DESTINATION share/kos/platform/kwin
)
