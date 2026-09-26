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

    find_program(KOS_QMLTESTRUNNER_EXECUTABLE NAMES qmltestrunner6 qmltestrunner
        HINTS "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_BINS}" /usr/lib/qt6/bin)
    if(KOS_QMLTESTRUNNER_EXECUTABLE)
        add_test(NAME kos-settings.builtin-checkboxes
            COMMAND ${KOS_QMLTESTRUNNER_EXECUTABLE}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/builtins/tst_builtins.qml)
        set_tests_properties(kos-settings.builtin-checkboxes PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS ui TIMEOUT 15)
        add_test(NAME kos-settings.widget-appearance
            COMMAND ${KOS_QMLTESTRUNNER_EXECUTABLE}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/widgets/tst_widgets.qml)
        set_tests_properties(kos-settings.widget-appearance PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS ui TIMEOUT 15)
    endif()

    # The smoke test above proves the pages load; this one proves the right
    # pages were chosen, which is a separate failure mode: an installed binary
    # serving a checkout Shell would open and render the installed copy, look
    # entirely correct, and ignore every QML edit until someone reinstalls.
    if(KOS_NODE_EXECUTABLE)
        add_test(NAME kos-settings.dev-session-entry
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/dev-session/run.mjs
                $<TARGET_FILE:kos-settings>
        )
        set_tests_properties(kos-settings.dev-session-entry PROPERTIES
            LABELS ui
            TIMEOUT 30
        )
    endif()
endif()
