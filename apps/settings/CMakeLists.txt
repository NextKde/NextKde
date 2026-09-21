cmake_minimum_required(VERSION 3.21)
project(kos-settings LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core DBus Gui Qml Quick)

qt_add_executable(kos-settings
    src/main.cpp
)

target_link_libraries(kos-settings PRIVATE
    Qt6::Core
    Qt6::DBus
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
)

# Development host: released packages will embed or install this QML tree.
# SETTINGS_SHELL_DIR must be the directory that *contains* shell.qml: the
# binary hands it to `quickshell ipc --path <dir>` to reach the Shell it was
# built for, and main.cpp only accepts it after finding shell.qml inside.
# Pointing at the repository root made that check fail, so every .desktop
# launch (app grid, KRunner, menu) fell through to the installed
# ~/.config/quickshell/kos session and reported "外观设置请求失败".
target_compile_definitions(kos-settings PRIVATE
    SETTINGS_QML_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
    SETTINGS_SHELL_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../../shell"
)

install(TARGETS kos-settings RUNTIME DESTINATION bin)
install(FILES main.qml DESTINATION share/kos/settings)

if(BUILD_TESTING)
    # The settings window ships in the core configuration, so it is not built
    # through kos_add_application and its smoke test lives here. --smoke-test
    # loads main.qml offscreen -- a real load, for one event loop turn -- and
    # turns a QML tree that no longer instantiates into a failed test instead
    # of a window that silently never appears.
    add_test(NAME kos-settings.qml-smoke COMMAND kos-settings --smoke-test)
    set_tests_properties(kos-settings.qml-smoke PROPERTIES
        ENVIRONMENT
            "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QSG_RHI_BACKEND=software"
        LABELS ui
        TIMEOUT 15
    )
endif()
