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
    src/daemon/PlatformServer.cpp
    src/daemon/PlatformServer.h
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

install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/../integrations/kwin/window-bridge.js
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
        # Destination-shape contract for file.copy: a path that already exists
        # must be replaceable, and the shapes that must stay rejected (a
        # symlink, a missing component under a file) must keep failing.
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
