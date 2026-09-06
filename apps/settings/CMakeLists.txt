cmake_minimum_required(VERSION 3.21)
project(kos-settings LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core DBus Gui Qml Quick)

qt_add_executable(kos-settings
    src/main.cpp
)

# kos-settings is an independent app whose canonical artifact lives in-tree:
# DesktopAppLauncher execs it from here in development sessions, so every
# build configuration (top-level kosctl build or a standalone configure of
# this directory) writes the one and only binary to apps/settings/build.
set_target_properties(kos-settings PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/build")

target_link_libraries(kos-settings PRIVATE
    Qt6::Core
    Qt6::DBus
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
)

# Development host: released packages will embed or install this QML tree.
target_compile_definitions(kos-settings PRIVATE
    SETTINGS_QML_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
    SETTINGS_SHELL_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../.."
)

install(TARGETS kos-settings RUNTIME DESTINATION bin)
install(FILES main.qml DESTINATION share/kos/settings)
