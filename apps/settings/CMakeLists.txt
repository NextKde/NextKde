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
find_package(KF6KCMUtils REQUIRED)
find_package(KF6KIO REQUIRED)
find_package(KF6Service REQUIRED)
find_package(Qt6 6.5 REQUIRED COMPONENTS Concurrent)
if(NOT TARGET kos-flatpak-client)
    add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../platform/flatpak-client ${CMAKE_CURRENT_BINARY_DIR}/flatpak-client)
endif()
if(NOT KOS_FLATPAK_SUPPORT STREQUAL "OFF")
    find_package(PkgConfig QUIET)
    if(PkgConfig_FOUND)
        pkg_check_modules(FLATPAK QUIET IMPORTED_TARGET flatpak>=1.12 ostree-1>=2021.4)
    endif()
    if(FLATPAK_FOUND)
        add_library(kos-flatpak-apps STATIC src/FlatpakApps.cpp src/FlatpakApps.h src/FlatpakRelease.cpp src/FlatpakRelease.h
            src/FlatpakCompatibility.cpp src/FlatpakCompatibility.h
            src/FlatpakTransactionProcess.cpp src/FlatpakTransactionProcess.h)
        target_link_libraries(kos-flatpak-apps PUBLIC Qt6::Core Qt6::Concurrent kos-app-catalog PRIVATE Qt6::Network PkgConfig::FLATPAK)
        add_executable(kos-flatpak-worker src/FlatpakWorkerMain.cpp)
        target_link_libraries(kos-flatpak-worker PRIVATE kos-flatpak-apps)
        target_compile_definitions(kos-flatpak-worker PRIVATE KOS_FLATPAK_NATIVE_HELPERS)
        target_compile_definitions(kos-flatpak-client PRIVATE KOS_FLATPAK_WORKER_BUILD_PATH="$<TARGET_FILE:kos-flatpak-worker>")
        add_dependencies(kos-flatpak-client kos-flatpak-worker)
        install(TARGETS kos-flatpak-worker RUNTIME DESTINATION bin)
    elseif(KOS_FLATPAK_SUPPORT STREQUAL "ON")
        message(FATAL_ERROR "KOS_FLATPAK_SUPPORT=ON requires flatpak>=1.12 and ostree-1>=2021.4 development libraries")
    else()
        message(STATUS "Optional Flatpak backend not built; Settings, platform and kos-apps remain available")
    endif()
endif()
add_executable(kos-apps src/FlatpakAppsCli.cpp)
if(TARGET kos-flatpak-apps)
    target_link_libraries(kos-apps PRIVATE kos-flatpak-apps kos-flatpak-client)
    target_compile_definitions(kos-apps PRIVATE KOS_FLATPAK_NATIVE_HELPERS)
else()
    target_link_libraries(kos-apps PRIVATE kos-flatpak-client)
endif()
install(TARGETS kos-apps RUNTIME DESTINATION bin)
add_executable(kos-app-update-agent src/AppUpdateAgentMain.cpp src/AppUpdateAgent.cpp src/AppUpdateAgent.h
    src/TaskNotifications.cpp src/TaskNotifications.h)
target_link_libraries(kos-app-update-agent PRIVATE kos-flatpak-client Qt6::Concurrent Qt6::DBus)
install(TARGETS kos-app-update-agent RUNTIME DESTINATION bin)
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/../../packaging/desktop/kos-app-updates.desktop.in
    ${CMAKE_CURRENT_BINARY_DIR}/kos-app-updates.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/kos-app-updates.desktop DESTINATION etc/xdg/autostart)

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../shared/gtk/module ${CMAKE_CURRENT_BINARY_DIR}/gtk-module)

# Embed the GTK adapter and assets: installed Settings must work without a checkout.
qt_add_resources(KOS_GTK_RESOURCES ../../shared/gtk/integration.qrc)

qt_add_executable(kos-settings
    src/main.cpp
    src/AboutCache.cpp
    src/AboutCache.h
    src/TaskNotifications.cpp
    src/TaskNotifications.h
    src/AppStore.cpp
    src/AppStore.h
    src/IndependentApps.cpp
    src/IndependentApps.h
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
    src/FontSettings.cpp
    src/FontSettings.h
    src/PowerSettings.cpp
    src/PowerSettings.h
    src/WindowSettings.cpp
    ${KOS_GTK_RESOURCES}
    ../../platform/src/daemon/PlatformDbus.cpp
    ../../platform/src/daemon/PowerProfilesBus.cpp
)
add_dependencies(kos-settings kos-gtk-window-controls)
target_compile_definitions(kos-settings PRIVATE
    KOS_GTK_MODULE_BUILD_PATH="$<TARGET_FILE:kos-gtk-window-controls>"
    KOS_SETTINGS_BUILD_DIR="${CMAKE_CURRENT_BINARY_DIR}")
target_include_directories(kos-settings PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../services/ai/include)

add_dependencies(kos-settings kos-apps kos-app-update-agent)
target_link_libraries(kos-settings PRIVATE
    kos_demo_ui
    kos_demo_ui_plugin
    kos-flatpak-client
    Qt6::Core
    Qt6::DBus
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    KF6::ConfigCore
    KF6::KCMUtilsQuick
    KF6::KIOGui
    KF6::Service
    Qt6::Network
    Qt6::Concurrent
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
    add_executable(kos-wallpaper-gradient-test tests/wallpaper/gradient.cpp)
    target_link_libraries(kos-wallpaper-gradient-test PRIVATE Qt6::Core Qt6::Gui)
    add_test(NAME kos-settings.wallpaper-gradient COMMAND kos-wallpaper-gradient-test)
    set_tests_properties(kos-settings.wallpaper-gradient PROPERTIES LABELS logic TIMEOUT 20)
    find_package(Qt6 6.5 REQUIRED COMPONENTS Test)
    add_executable(kos-app-catalog-test tests/store/catalog.cpp)
    target_link_libraries(kos-app-catalog-test PRIVATE kos-app-catalog Qt6::Test Qt6::Network)
    add_test(NAME kos-settings.app-catalog COMMAND kos-app-catalog-test)
    set_tests_properties(kos-settings.app-catalog PROPERTIES LABELS logic TIMEOUT 120)
    find_program(DBUS_RUN_SESSION_EXECUTABLE dbus-run-session REQUIRED)
    add_executable(kos-app-update-agent-test tests/store/update_agent.cpp
        src/AppUpdateAgent.cpp src/TaskNotifications.cpp)
    target_include_directories(kos-app-update-agent-test PRIVATE src)
    target_link_libraries(kos-app-update-agent-test PRIVATE kos-flatpak-client Qt6::Test Qt6::Concurrent Qt6::DBus)
    add_test(NAME kos-settings.app-updates
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- $<TARGET_FILE:kos-app-update-agent-test>)
    set_tests_properties(kos-settings.app-updates PROPERTIES LABELS logic TIMEOUT 30)
    find_program(XVFB_RUN_EXECUTABLE xvfb-run)
    add_executable(kos-settings-fonts-test tests/backend/FontsTest.cpp src/FontSettings.cpp src/FontSettings.h)
    target_include_directories(kos-settings-fonts-test PRIVATE src)
    target_link_libraries(kos-settings-fonts-test PRIVATE Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test Qt6::DBus
        KF6::KCMUtilsQuick kos_demo_ui kos_demo_ui_plugin)
    target_compile_definitions(kos-settings-fonts-test PRIVATE
        FONT_SETTINGS_PAGE="${CMAKE_CURRENT_SOURCE_DIR}/pages/FontSettingsPage.qml")
    if(XVFB_RUN_EXECUTABLE)
        add_test(NAME kos-settings.fonts
            COMMAND ${XVFB_RUN_EXECUTABLE} -a ${DBUS_RUN_SESSION_EXECUTABLE} -- $<TARGET_FILE:kos-settings-fonts-test>)
        set_tests_properties(kos-settings.fonts PROPERTIES LABELS headless TIMEOUT 30
            ENVIRONMENT "KOS_FONT_SCREENSHOT=${CMAKE_BINARY_DIR}/test-results/fonts.png")
    else()
        message(STATUS "Skipping kos-settings.fonts: xvfb-run is unavailable (other tests remain enabled)")
    endif()
    add_executable(kos-settings-background-test tests/background/session.cpp)
    target_link_libraries(kos-settings-background-test PRIVATE Qt6::Core Qt6::DBus Qt6::Test kos-app-catalog)
    target_compile_definitions(kos-settings-background-test PRIVATE
        SETTINGS_EXECUTABLE="$<TARGET_FILE:kos-settings>"
        SETTINGS_COMPONENTS="${CMAKE_CURRENT_SOURCE_DIR}/components")
    add_dependencies(kos-settings-background-test kos-settings)
    add_test(NAME kos-settings.close-policy
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- $<TARGET_FILE:kos-settings-background-test>)
    set_tests_properties(kos-settings.close-policy PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
        LABELS "headless" TIMEOUT 60)
    find_package(Qt6 6.5 QUIET COMPONENTS QuickTest)
    add_executable(kos-flatpak-process-test tests/store/flatpak_process.cpp src/FlatpakTransactionProcess.cpp)
    target_include_directories(kos-flatpak-process-test PRIVATE src)
    target_link_libraries(kos-flatpak-process-test PRIVATE Qt6::Core Qt6::Test)
    add_test(NAME kos-settings.flatpak-process COMMAND kos-flatpak-process-test)
    set_tests_properties(kos-settings.flatpak-process PROPERTIES
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../.. LABELS logic TIMEOUT 20)
    if(TARGET kos-flatpak-apps)
    add_executable(kos-flatpak-compatibility-test tests/store/flatpak_compatibility.cpp)
    target_include_directories(kos-flatpak-compatibility-test PRIVATE src)
    target_link_libraries(kos-flatpak-compatibility-test PRIVATE kos-flatpak-apps Qt6::Test)
    add_dependencies(kos-flatpak-compatibility-test kos-apps)
    add_test(NAME kos-settings.flatpak-compatibility COMMAND kos-flatpak-compatibility-test)
    set_tests_properties(kos-settings.flatpak-compatibility PROPERTIES
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../.. LABELS logic TIMEOUT 20)
    endif()
    if(TARGET kos-flatpak-apps)
        add_executable(kos-flatpak-release-test tests/store/flatpak_release.cpp)
        target_include_directories(kos-flatpak-release-test PRIVATE src)
        target_link_libraries(kos-flatpak-release-test PRIVATE Qt6::Core Qt6::Network Qt6::Test PkgConfig::FLATPAK kos-app-catalog)
        add_test(NAME kos-settings.flatpak-release COMMAND kos-flatpak-release-test)
        set_tests_properties(kos-settings.flatpak-release PROPERTIES
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../.. LABELS logic TIMEOUT 30)
    endif()
    # Native KMusic controller was removed; catalogue behavior is covered by independent-apps.

    add_executable(kos-independent-apps-test tests/store/independent.cpp src/AppStore.cpp src/IndependentApps.cpp)
    target_include_directories(kos-independent-apps-test PRIVATE src)
    target_link_libraries(kos-independent-apps-test PRIVATE Qt6::Core Qt6::Gui Qt6::Network
        Qt6::Test Qt6::Concurrent KF6::KIOGui KF6::Service kos-flatpak-client)
    add_test(NAME kos-settings.independent-apps COMMAND kos-independent-apps-test)
    set_tests_properties(kos-settings.independent-apps PROPERTIES
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../.. LABELS logic TIMEOUT 30)

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

    add_executable(kos-window-settings-test tests/windows/config.cpp src/WindowSettings.cpp ${KOS_GTK_RESOURCES})
    target_include_directories(kos-window-settings-test PRIVATE src)
    target_link_libraries(kos-window-settings-test PRIVATE Qt6::Core Qt6::DBus KF6::ConfigCore)
    add_test(NAME kos-settings.window-config COMMAND kos-window-settings-test)
    set_tests_properties(kos-settings.window-config PROPERTIES LABELS logic TIMEOUT 15)
    add_executable(kos-animation-async-test tests/windows/async.cpp src/WindowSettings.cpp ${KOS_GTK_RESOURCES})
    target_include_directories(kos-animation-async-test PRIVATE src)
    target_link_libraries(kos-animation-async-test PRIVATE Qt6::Core Qt6::DBus KF6::ConfigCore)
    add_test(NAME kos-settings.animation-async COMMAND dbus-run-session -- $<TARGET_FILE:kos-animation-async-test>)
    set_tests_properties(kos-settings.animation-async PROPERTIES LABELS logic TIMEOUT 20)

    add_executable(kos-native-genie-test tests/windows/native-genie.cpp)
    target_link_libraries(kos-native-genie-test PRIVATE Qt6::Core Qt6::DBus KF6::ConfigCore)
    add_test(NAME kos-settings.native-genie-upgrade COMMAND kos-native-genie-test)
    set_tests_properties(kos-settings.native-genie-upgrade PROPERTIES LABELS logic TIMEOUT 15)
    add_test(NAME kos-settings.window-page COMMAND kos-settings --smoke-test-windows)
    set_tests_properties(kos-settings.window-page PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml;QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml"
        LABELS ui TIMEOUT 15)
    # The settings window ships in the core configuration, so it is not built
    # through kos_add_application and its smoke test lives here. --smoke-test
    # loads main.qml offscreen -- a real load, for one event loop turn -- and
    # turns a QML tree that no longer instantiates into a failed test instead
    # of a window that silently never appears.
    add_test(NAME kos-settings.qml-smoke COMMAND kos-settings --smoke-test)
    set_tests_properties(kos-settings.qml-smoke PROPERTIES
        ENVIRONMENT
            "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QSG_RHI_BACKEND=software;QML_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml;QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/qml"
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

        # Services uses the same statically linked Kos.Demo module as Settings.
        if(TARGET Qt6::QuickTest)
        qt_add_executable(kos-settings-services-test tests/services/main.cpp)
        target_link_libraries(kos-settings-services-test PRIVATE Qt6::QuickTest kos_demo_ui kos_demo_ui_plugin)
        add_test(NAME kos-settings.services-page
            COMMAND kos-settings-services-test
                -input ${CMAKE_CURRENT_SOURCE_DIR}/tests/services/tst_services.qml)
        set_tests_properties(kos-settings.services-page PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software"
            LABELS ui TIMEOUT 30)
        endif()

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
                $<TARGET_FILE:kos-settings> $<TARGET_FILE:kos-gtk-window-controls>)
        set_tests_properties(kos-settings.window-install PROPERTIES LABELS ui TIMEOUT 25)
        add_test(NAME kos-settings.wallpaper-colors
            COMMAND ${KOS_NODE_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/wallpaper/bridge.mjs
                $<TARGET_FILE:kos-settings>)
        set_tests_properties(kos-settings.wallpaper-colors PROPERTIES LABELS ui TIMEOUT 20)
        add_test(NAME kos-settings.wallpaper-palettes
            COMMAND ${KOS_NODE_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/wallpaper/palette.mjs)
        set_tests_properties(kos-settings.wallpaper-palettes PROPERTIES LABELS logic TIMEOUT 20)
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
