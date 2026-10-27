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
# The depth engine is the only part of the platform that needs OpenCV and the
# ONNX Runtime, so it follows KOS_SPATIAL_ENABLED (resolved from
# KOS_BUILD_SPATIAL in the top-level file) instead of being unconditional. The
# model a build like this would use is still a user-cache download.
if(KOS_SPATIAL_ENABLED)
    add_subdirectory(${CMAKE_SOURCE_DIR}/services/ai ${CMAKE_BINARY_DIR}/services/ai)
endif()

qt_standard_project_setup()

set(kos_platform_sources
    src/daemon/main.cpp
    src/daemon/KWinShortcutConflicts.cpp
    src/daemon/KWinShortcutConflicts.h
    src/daemon/PlatformServer.cpp
    src/daemon/PlatformDbus.cpp
    src/daemon/PowerProfilesBus.cpp
    src/daemon/PowerProfilesBus.h
    src/daemon/PlatformNetworkConnect.cpp
    src/daemon/PlatformNetworkRead.cpp
    src/daemon/PlatformPaths.cpp
    src/daemon/PlatformProcess.cpp
    src/daemon/PlatformServerAppMenu.cpp
    src/daemon/PlatformServerApplications.cpp
    src/daemon/PlatformServerAudio.cpp
    src/daemon/PlatformServerBluetooth.cpp
    src/daemon/PlatformServerClipboard.cpp
    src/daemon/PlatformServerClipboardPins.cpp
    src/daemon/PlatformServerDesktop.cpp
    src/daemon/PlatformServerDisplay.cpp
    src/daemon/PlatformServerFiles.cpp
    src/daemon/BatteryData.h
    src/daemon/PlatformServerPower.cpp
    src/daemon/PlatformServerNetwork.cpp
    src/daemon/PlatformServerState.cpp
    src/daemon/PlatformServerTheme.cpp
    src/daemon/PlatformServerTray.cpp
    src/daemon/PlatformServerWallpaper.cpp
    src/daemon/PlatformServerWatches.cpp
    src/daemon/PlatformServerWindows.cpp
    src/daemon/PlatformClipboardStorage.h
    src/daemon/PlatformDbus.h
    src/daemon/PlatformNetworkBackend.h
    src/daemon/PlatformPaths.h
    src/daemon/PlatformProcess.h
    src/daemon/PlatformServer.h
    src/daemon/KeepAwakeLease.cpp
    src/daemon/KeepAwakeLease.h
    src/daemon/Shortcuts.cpp
    src/daemon/Shortcuts.h
    src/kwin/KWinBridge.cpp
    src/kwin/KWinBridge.h
    src/wallpaper/PlasmaWallpaperAdapter.cpp
    src/wallpaper/PlasmaWallpaperAdapter.h
)
if(KOS_SPATIAL_ENABLED)
    list(APPEND kos_platform_sources
        src/ai/AiWorkerClient.cpp
        src/ai/AiWorkerClient.h)
endif()

if(BUILD_TESTING)
    qt_add_executable(kos-status-panel-data-test tests/test_status_panel_data.cpp)
    target_link_libraries(kos-status-panel-data-test PRIVATE Qt6::Core)
    add_test(NAME kos-platform.status-panel-data COMMAND kos-status-panel-data-test)
    set_tests_properties(kos-platform.status-panel-data PROPERTIES LABELS "platform;data")

    qt_add_executable(kos-power-profiles-bus-test
        tests/test_power_profiles_bus.cpp
        src/daemon/PlatformDbus.cpp
        src/daemon/PowerProfilesBus.cpp)
    target_link_libraries(kos-power-profiles-bus-test PRIVATE Qt6::Core Qt6::DBus)
    find_program(DBUS_DAEMON_EXECUTABLE dbus-daemon)
    if(DBUS_DAEMON_EXECUTABLE)
        add_test(NAME kos-platform.power-profiles-bus COMMAND kos-power-profiles-bus-test)
        set_tests_properties(kos-platform.power-profiles-bus PROPERTIES LABELS platform TIMEOUT 20)
    endif()
endif()

qt_add_executable(kos-platform ${kos_platform_sources})
set_target_properties(kos-platform PROPERTIES
    INSTALL_RPATH "$ORIGIN/../lib")

# The daemon drops the spatial operations, and the capability that gates the
# Shell's spatial UI, when there is no worker to talk to.
if(KOS_SPATIAL_ENABLED)
    target_compile_definitions(kos-platform PRIVATE KOS_SPATIAL_ENABLED)
endif()

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

if(KOS_SPATIAL_ENABLED)
    qt_add_executable(kos-ai-worker
        ${CMAKE_SOURCE_DIR}/services/ai/worker/main.cpp
    )
    target_link_libraries(kos-ai-worker PRIVATE kos-ai Qt6::Core)
    set_target_properties(kos-ai-worker PROPERTIES
        INSTALL_RPATH "$ORIGIN/../lib")

    install(TARGETS kos-platform kos-ai-worker
        RUNTIME DESTINATION libexec
    )
else()
    install(TARGETS kos-platform
        RUNTIME DESTINATION libexec
    )
endif()

set(KOS_PLATFORM_KWIN_SCRIPT_SOURCE
    "${CMAKE_CURRENT_SOURCE_DIR}/../kwin/window-bridge.js"
    CACHE FILEPATH "KWin script installed with the platform daemon")
install(FILES ${KOS_PLATFORM_KWIN_SCRIPT_SOURCE}
    DESTINATION share/kos/platform/kwin
)

# Startup smoke for the daemon itself: run the freshly built binary on a
# private session bus, wait for its READY line, answer-check platform.ping
# and confirm SIGTERM stops it cleanly. It needs an interpreter and
# dbus-run-session, so it registers only when both exist.
if(BUILD_TESTING AND KOS_SPATIAL_ENABLED)
    qt_add_executable(kos-ai-worker-fake tests/fake_ai_worker.cpp)
    target_link_libraries(kos-ai-worker-fake PRIVATE Qt6::Core)
    set_target_properties(kos-ai-worker-fake PROPERTIES
        OUTPUT_NAME kos-ai-worker
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/ai-worker-test")

    qt_add_executable(kos-ai-worker-client-test
        tests/test_ai_worker_client.cpp
        src/ai/AiWorkerClient.cpp
        src/ai/AiWorkerClient.h)
    target_link_libraries(kos-ai-worker-client-test PRIVATE Qt6::Core)
    set_target_properties(kos-ai-worker-client-test PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/ai-worker-test")
    add_dependencies(kos-ai-worker-client-test kos-ai-worker-fake)
    add_test(NAME kos-platform.ai-worker-client
        COMMAND $<TARGET_FILE:kos-ai-worker-client-test>)
    set_tests_properties(kos-platform.ai-worker-client PROPERTIES
        LABELS platform
        TIMEOUT 10)
endif()

if(BUILD_TESTING)
    if(NOT KOS_PYTHON_EXECUTABLE)
        find_program(KOS_PYTHON_EXECUTABLE NAMES python3 python)
    endif()
    find_program(DBUS_RUN_SESSION_EXECUTABLE dbus-run-session)
    if(DBUS_RUN_SESSION_EXECUTABLE)
        qt_add_executable(kos-keep-awake-test tests/test_keep_awake.cpp)
        target_link_libraries(kos-keep-awake-test PRIVATE Qt6::Core Qt6::DBus Qt6::Network)
        add_test(NAME kos-platform.keep-awake
            COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- $<TARGET_FILE:kos-keep-awake-test>
                $<TARGET_FILE:kos-platform>)
        set_tests_properties(kos-platform.keep-awake PROPERTIES LABELS platform TIMEOUT 60)

        # The KWin conflict repair talks to kglobalaccel over the session bus,
        # so the test runs on a private bus under dbus-run-session with a fake
        # daemon: it proves both the bytes on the wire (a(ssssssaiai)) and the
        # exact repair call (release Meta+Tab, keep Alt+Tab, SetPresent set).
        qt_add_executable(kos-kwin-shortcut-conflict-test
            tests/test_shortcut_conflicts.cpp
            src/daemon/KWinShortcutConflicts.cpp
            src/daemon/KWinShortcutConflicts.h)
        target_link_libraries(kos-kwin-shortcut-conflict-test PRIVATE
            Qt6::Core
            Qt6::DBus
            Qt6::Gui)
        add_test(NAME kos-platform.kwin-shortcut-conflict
            COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} --
                $<TARGET_FILE:kos-kwin-shortcut-conflict-test>)
        set_tests_properties(kos-platform.kwin-shortcut-conflict PROPERTIES
            LABELS platform
            TIMEOUT 30)
    endif()
    if(KOS_PYTHON_EXECUTABLE AND DBUS_RUN_SESSION_EXECUTABLE)
        add_test(NAME kos-platform.status-panel-operations
            COMMAND ${KOS_PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_status_panel_operations.py $<TARGET_FILE:kos-platform>)
        set_tests_properties(kos-platform.status-panel-operations PROPERTIES LABELS platform TIMEOUT 30)
        add_test(NAME kos-platform.startup
            COMMAND ${KOS_PYTHON_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_platform_startup.py
                $<TARGET_FILE:kos-platform>
        )
        set_tests_properties(kos-platform.startup PROPERTIES
            LABELS platform
            TIMEOUT 60
        )
        # Destination-shape contract for file.copy: a path that already exists
        # must be replaceable, and the shapes that must stay rejected (a
        # symlink, a missing component under a file) must keep failing.
        add_test(NAME kos-platform.media-feedback
            COMMAND ${KOS_PYTHON_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_media_feedback.py
                $<TARGET_FILE:kos-platform>)
        set_tests_properties(kos-platform.media-feedback PROPERTIES LABELS platform TIMEOUT 60)
        add_test(NAME kos-platform.file-copy
            COMMAND ${KOS_PYTHON_EXECUTABLE}
                ${CMAKE_CURRENT_SOURCE_DIR}/tests/test_file_copy.py
                $<TARGET_FILE:kos-platform>
        )
        set_tests_properties(kos-platform.file-copy PROPERTIES
            LABELS platform
            TIMEOUT 60
        )
    endif()
endif()
