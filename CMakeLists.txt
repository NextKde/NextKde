cmake_minimum_required(VERSION 3.21)

project(KOS VERSION 1.0 LANGUAGES CXX)

include(GNUInstallDirs)

option(KOS_BUILD_KWIN_PLUGINS "Build the two KWin effect plugins" ON)

add_subdirectory(platform)
add_subdirectory(apps/settings)

if(KOS_BUILD_KWIN_PLUGINS)
    add_subdirectory(integrations/kwin-dock-window-animation)
    add_subdirectory(integrations/kwin-context-menu-input)
endif()

# Quickshell loads this tree at runtime; CMake only installs it and does not
# attempt to compile QML into the platform binary.
install(DIRECTORY shell/ DESTINATION share/kos/shell
    PATTERN "*.qml" PATTERN "*.qmlc" EXCLUDE)
install(DIRECTORY shared/ DESTINATION share/kos/shared)
