add_library(kos_app_core STATIC
    src/ApplicationActivation.cpp
    src/ApplicationActivation.h
    src/ApplicationPreferences.cpp
    src/ApplicationPreferences.h
    src/ApplicationRunner.cpp
)

add_library(Kos::AppCore ALIAS kos_app_core)

target_include_directories(kos_app_core
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)

target_link_libraries(kos_app_core PUBLIC
    Qt6::Core
    Qt6::DBus
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
)

if(TARGET KF6::WindowSystem)
    target_link_libraries(kos_app_core PUBLIC KF6::WindowSystem)
    target_compile_definitions(kos_app_core PRIVATE KOS_HAVE_KWINDOWSYSTEM=1)
endif()

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(kos_app_core PRIVATE
        -Wall
        -Wextra
        -Wpedantic
    )
endif()

if(BUILD_TESTING)
    add_executable(kos-application-preferences-test
        tests/ApplicationPreferencesTest.cpp
    )
    target_include_directories(kos-application-preferences-test PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    target_link_libraries(kos-application-preferences-test PRIVATE
        Kos::AppCore
        Qt6::Test
    )
    add_test(NAME kos-application.preferences
        COMMAND kos-application-preferences-test
    )
    set_tests_properties(kos-application.preferences PROPERTIES TIMEOUT 20)
endif()
