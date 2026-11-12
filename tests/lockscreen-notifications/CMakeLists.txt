cmake_minimum_required(VERSION 3.21)
# Standalone: cmake -S tests/lockscreen-notifications -B /tmp/kos-lockscreen-tests
#            cmake --build /tmp/kos-lockscreen-tests
#            ctest --test-dir /tmp/kos-lockscreen-tests --output-on-failure
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    project(kos-lockscreen-notifications-tests LANGUAGES CXX)
    include(CTest)
endif()
set(CMAKE_AUTOMOC ON)
find_package(Qt6 6.5 REQUIRED COMPONENTS Core DBus Network Test)
find_program(LOCKSCREEN_DBUS_RUN_SESSION dbus-run-session)
find_program(LOCKSCREEN_NODE node)
find_program(LOCKSCREEN_QUICKSHELL NAMES quickshell qs)
add_executable(kos-lockscreen-notifications-test
    test_bridge.cpp
    ../../platform/src/daemon/LockScreenNotifications.cpp
    ../../platform/src/daemon/LockScreenNotifications.h)
target_compile_features(kos-lockscreen-notifications-test PRIVATE cxx_std_20)
target_link_libraries(kos-lockscreen-notifications-test PRIVATE Qt6::Core Qt6::DBus Qt6::Network Qt6::Test)
target_include_directories(kos-lockscreen-notifications-test PRIVATE ../../platform/src/daemon)
target_compile_definitions(kos-lockscreen-notifications-test PRIVATE
    LOCKSCREEN_TEST_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
if(LOCKSCREEN_DBUS_RUN_SESSION)
    add_test(NAME kos-lockscreen.notifications-dbus
        COMMAND "${LOCKSCREEN_DBUS_RUN_SESSION}" -- "${CMAKE_COMMAND}" -E env
            KOS_LOCKSCREEN_TEST_BUS=1 QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software
            $<TARGET_FILE:kos-lockscreen-notifications-test>)
    set_tests_properties(kos-lockscreen.notifications-dbus PROPERTIES TIMEOUT 70 LABELS "platform;lockscreen")
endif()
if(LOCKSCREEN_NODE)
    add_test(NAME kos-lockscreen.notifications-projection
        COMMAND "${LOCKSCREEN_NODE}" "${CMAKE_CURRENT_SOURCE_DIR}/test_snapshot.mjs")
    set_tests_properties(kos-lockscreen.notifications-projection PROPERTIES LABELS "platform;lockscreen")
    if(LOCKSCREEN_DBUS_RUN_SESSION AND DEFINED kos_platform_sources)
        add_test(NAME kos-lockscreen.notifications-platform
            COMMAND "${LOCKSCREEN_NODE}" "${CMAKE_CURRENT_SOURCE_DIR}/run-platform.mjs"
                $<TARGET_FILE:kos-platform>)
        set_tests_properties(kos-lockscreen.notifications-platform PROPERTIES TIMEOUT 30 LABELS "platform;lockscreen")
    endif()
    if(LOCKSCREEN_QUICKSHELL AND LOCKSCREEN_DBUS_RUN_SESSION)
        add_test(NAME kos-lockscreen.notifications-qml
            COMMAND "${LOCKSCREEN_DBUS_RUN_SESSION}" -- "${LOCKSCREEN_NODE}"
                "${CMAKE_CURRENT_SOURCE_DIR}/run-qml.mjs" "${LOCKSCREEN_QUICKSHELL}")
        set_tests_properties(kos-lockscreen.notifications-qml PROPERTIES TIMEOUT 20 LABELS "platform;lockscreen")
    endif()
endif()
