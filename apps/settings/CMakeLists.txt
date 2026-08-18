cmake_minimum_required(VERSION 3.21)
project(kos-settings LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick)

qt_add_executable(kos-settings
    src/main.cpp
)

target_link_libraries(kos-settings PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
)

# Development host: released packages will embed or install this QML tree.
target_compile_definitions(kos-settings PRIVATE
    SETTINGS_QML_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
    SETTINGS_SHELL_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../.."
)
