cmake_minimum_required(VERSION 3.21)
project(kos-settings LANGUAGES CXX)
include(CTest)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core DBus Gui Qml Quick QuickControls2 Network)
if(NOT TARGET kos_demo_ui)
    add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../shared/demo-ui ${CMAKE_CURRENT_BINARY_DIR}/demo-ui)
endif()

find_package(KF6Config REQUIRED)
find_package(KF6KIO REQUIRED)
find_package(KF6Service REQUIRED)

qt_add_executable(kos-settings
    src/main.cpp
    src/AppStore.cpp
    src/AppStore.h
    src/SettingsBridge.h
    src/SettingsBridge.cpp
    src/SettingsBridgeDesktop.cpp
    src/SettingsBridgeAppearance.cpp
    src/SettingsBridgeWallpaper.cpp
    src/SettingsBridgeScheduling.cpp
    src/SettingsProbeTasks.cpp
    src/ShellIpcClient.cpp
    src/WallpaperLibrary.h
    src/WallpaperLibrary.cpp
    src/SettingsRuntime.cpp
    src/CacheMaintenance.cpp
    src/PowerSettings.cpp
    src/PowerSettings.h
    src/WindowSettings.cpp
    ../../platform/src/daemon/PlatformDbus.cpp
    ../../platform/src/daemon/PowerProfilesBus.cpp
)
target_include_directories(kos-settings PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../services/ai/include)

target_link_libraries(kos-settings PRIVATE
    kos_demo_ui
    kos_demo_ui_plugin
    Qt6::Core
    Qt6::DBus
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    KF6::ConfigCore
    KF6::KIOGui
    KF6::Service
    Qt6::Network
)

# Development host: released packages will embed or install this QML tree.
# SETTINGS_SHELL_DIR must be the directory that *contains* shell.qml: the
# binary hands it to `quickshell ipc --path <dir>` to reach the Shell it was
# built for, and the IPC client only accepts it after finding shell.qml inside.
# Pointing at the repository root made that check fail, so every .desktop
# launch (app grid, KRunner, menu) fell through to the installed
# ~/.config/quickshell/kos session and reported "外观设置请求失败".
target_compile_definitions(kos-settings PRIVATE
    SETTINGS_QML_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
    SETTINGS_SHELL_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../../shell"
)

install(TARGETS kos-settings RUNTIME DESTINATION bin)
file(GLOB SETTINGS_RUNTIME_QML CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/*.qml")
install(FILES ${SETTINGS_RUNTIME_QML} DESTINATION share/kos/settings)
install(DIRECTORY icons app-store DESTINATION share/kos/settings)
install(DIRECTORY pages components DESTINATION share/kos/settings
    FILES_MATCHING PATTERN "*.qml")

if(BUILD_TESTING)
    find_package(Qt6 6.5 REQUIRED COMPONENTS Test)
    find_package(Qt6 6.5 QUIET COMPONENTS QuickTest)
    add_executable(kos-app-store-test tests/store/backend.cpp src/AppStore.cpp)
    target_include_directories(kos-app-store-test PRIVATE src)
    target_link_libraries(kos-app-store-test PRIVATE Qt6::Core Qt6::Gui Qt6::Network
        Qt6::Test KF6::KIOGui KF6::Service)
    add_test(NAME kos-settings.app-store COMMAND kos-app-store-test)
    set_tests_properties(kos-settings.app-store PROPERTIES LABELS logic TIMEOUT 30)

    add_executable(kos-settings-backend-test
        tests/backend/ModulesTest.cpp
        src/SettingsProbeTasks.cpp
        src/ShellIpcClient.cpp
        src/WallpaperLibrary.cpp
        src/WallpaperLibrary.h)
    target_include_directories(kos-settings-backend-test PRIVATE src)
    target_link_libraries(kos-settings-backend-test PRIVATE Qt6::Core Qt6::Gui Qt6::Test)
    target_compile_definitions(kos-settings-backend-test PRIVATE
        SETTINGS_SHELL_DIR="${CMAKE_CURRENT_SOURCE_DIR}/../../shell")
    add_test(NAME kos-settings.backend-modules COMMAND kos-settings-backend-test)
    set_tests_properties(kos-settings.backend-modules PROPERTIES LABELS logic TIMEOUT 20)

    add_executable(kos-power-settings-test
        tests/power/backend.cpp
        src/PowerSettings.cpp
        src/PowerSettings.h
        ../../platform/src/daemon/PlatformDbus.cpp
        ../../platform/src/daemon/PowerProfilesBus.cpp)
    target_include_directories(kos-power-settings-test PRIVATE src)
    target_link_libraries(kos-power-settings-test PRIVATE Qt6::Core Qt6::DBus)
    add_test(NAME kos-settings.power-config COMMAND kos-power-settings-test)
    set_tests_properties(kos-settings.power-config PROPERTIES LABELS logic TIMEOUT 20)

    add_executable(kos-power-settings-bus-test
        tests/power/bus.cpp
        src/PowerSettings.cpp
        src/PowerSettings.h
        ../../platform/src/daemon/PlatformDbus.cpp
        ../../platform/src/daemon/PowerProfilesBus.cpp)
    target_include_directories(kos-power-settings-bus-test PRIVATE src)
    target_link_libraries(kos-power-settings-bus-test PRIVATE Qt6::Core Qt6::DBus)
    if(NOT DBUS_DAEMON_EXECUTABLE)
        find_program(DBUS_DAEMON_EXECUTABLE dbus-daemon)
    endif()
    if(DBUS_DAEMON_EXECUTABLE)
        add_test(NAME kos-settings.power-bus COMMAND kos-power-settings-bus-test)
        set_tests_properties(kos-settings.power-bus PROPERTIES LABELS logic TIMEOUT 20)
    endif()

    add_executable(kos-window-settings-test tests/windows/config.cpp src/WindowSettings.cpp)
    target_include_directories(kos-window-settings-test PRIVATE src)
    target_link_libraries(kos-window-settings-test PRIVATE Qt6::Core Qt6::DBus KF6::ConfigCore)
    add_test(NAME kos-settings.window-config COMMAND kos-window-settings-test)
    set_tests_properties(kos-settings.window-config PROPERTIES LABELS logic TIMEOUT 15)
    add_test(NAME kos-settings.window-page COMMAND kos-settings --smoke-test-windows)
    set_tests_properties(kos-settings.window-page PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
        LABELS ui TIMEOUT 15)
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

    # The settings QML imports the same static Demo module as the application.
    # A dedicated QuickTest host registers that module without installing it.
    set(KOS_QMLTESTRUNNER_EXECUTABLE "")
    if(TARGET Qt6::QuickTest)
        qt_add_executable(kos-settings-qml-tests tests/QmlTestMain.cpp)
        target_link_libraries(kos-settings-qml-tests PRIVATE Qt6::QuickTest
            kos_demo_ui kos_demo_ui_plugin)
        set(KOS_QMLTESTRUNNER_EXECUTABLE "$<TARGET_FILE:kos-settings-qml-tests>")
    endif()
    if(KOS_QMLTESTRUNNER_EXECUTABLE)
        add_test(NAME kos-settings.page-contracts
            COMMAND ${KOS_QMLTESTRUNNER_EXECUTABLE}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/pages)
        set_tests_properties(kos-settings.page-contracts PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS ui TIMEOUT 30)
        add_test(NAME kos-settings.power-interactions
            COMMAND ${KOS_QMLTESTRUNNER_EXECUTABLE} -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/power/tst_power.qml)
        set_tests_properties(kos-settings.power-interactions PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software" LABELS ui TIMEOUT 20)
        add_test(NAME kos-settings.window-interactions
            COMMAND ${KOS_QMLTESTRUNNER_EXECUTABLE}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/windows/tst_windows.qml)
        set_tests_properties(kos-settings.window-interactions PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS ui TIMEOUT 20)
        add_test(NAME kos-settings.wallpaper-page
            COMMAND ${KOS_QMLTESTRUNNER_EXECUTABLE}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/wallpaper/tst_wallpaper.qml)
        set_tests_properties(kos-settings.wallpaper-page PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS ui TIMEOUT 15)

        add_test(NAME kos-settings.services-page
            COMMAND ${KOS_QMLTESTRUNNER_EXECUTABLE}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/services/tst_services.qml)
        set_tests_properties(kos-settings.services-page PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS ui TIMEOUT 15)

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

    if(KOS_QMLTESTRUNNER_EXECUTABLE)
        add_test(NAME kos-settings.segmented-layout
            COMMAND ${KOS_QMLTESTRUNNER_EXECUTABLE}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/segmented-layout)
        set_tests_properties(kos-settings.segmented-layout PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QT_FORCE_STDERR_LOGGING=1"
            LABELS ui TIMEOUT 15)
        add_test(NAME kos-settings.notifications
            COMMAND ${KOS_QMLTESTRUNNER_EXECUTABLE}
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/notifications/tst_notifications.qml)
        set_tests_properties(kos-settings.notifications PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QT_FORCE_STDERR_LOGGING=1"
            LABELS ui TIMEOUT 15)
    endif()

    if(KOS_NODE_EXECUTABLE)
        find_program(KOS_QUICKSHELL_EXECUTABLE NAMES quickshell)
        if(KOS_QUICKSHELL_EXECUTABLE)
            add_test(NAME kos-settings.notifications-bridge
                COMMAND ${KOS_NODE_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/notifications/bridge.mjs
                    $<TARGET_FILE:kos-settings> ${KOS_QUICKSHELL_EXECUTABLE})
            set_tests_properties(kos-settings.notifications-bridge PROPERTIES LABELS ui TIMEOUT 20)
        else()
            message(STATUS "Skipping kos-settings.notifications-bridge: Quickshell is unavailable")
        endif()
        add_test(NAME kos-settings.window-install
            COMMAND ${KOS_NODE_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/windows/installed.mjs
                $<TARGET_FILE:kos-settings>)
        set_tests_properties(kos-settings.window-install PROPERTIES LABELS ui TIMEOUT 25)
        add_test(NAME kos-settings.wallpaper-colors
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/wallpaper/bridge.mjs
                $<TARGET_FILE:kos-settings>)
        set_tests_properties(kos-settings.wallpaper-colors PROPERTIES LABELS ui TIMEOUT 20)
        # The smoke test above proves the pages load; this one proves the right
        # pages were chosen, which is a separate failure mode: an installed binary
        # serving a checkout Shell would open and render the installed copy, look
        # entirely correct, and ignore every QML edit until someone reinstalls.
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
    # The notification bridge needs Quickshell; the remaining Settings UI
    # regressions run with the offscreen backend in a container. Backend logic
    # tests already belong to their own CI group and must not also be headless.
    get_property(KOS_SETTINGS_TESTS DIRECTORY PROPERTY TESTS)
    foreach(test IN LISTS KOS_SETTINGS_TESTS)
        get_property(test_labels TEST ${test} PROPERTY LABELS)
        if("ui" IN_LIST test_labels
                AND NOT test STREQUAL "kos-settings.notifications-bridge")
            set_property(TEST ${test} APPEND PROPERTY LABELS headless)
        endif()
    endforeach()

endif()
