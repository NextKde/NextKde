add_library(kos_app_core STATIC
    src/ApplicationActivation.cpp
    src/ApplicationActivation.h
    src/ApplicationPreferences.cpp
    src/ApplicationPreferences.h
    src/ApplicationQmlReloader.cpp
    include/KosApp/ApplicationQmlReloader.h
    src/ApplicationRunner.cpp
)

add_library(Kos::AppCore ALIAS kos_app_core)

target_include_directories(kos_app_core
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/../../shared/i18n>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)

find_package(Qt6 REQUIRED COMPONENTS LinguistTools)
qt_add_translations(kos_app_core
    SOURCE_TARGETS kos_app_core
    SOURCES
        ../calendar/qml ../calculator/qml ../todo/qml ../weather/qml
        ../../shared/qml/foundation ../../shared/pim
    TS_FILES translations/kos_apps_zh_CN.ts translations/kos_apps_pt_BR.ts
        translations/kos_apps_en_US.ts
    RESOURCE_PREFIX /kos/i18n
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
    set_tests_properties(kos-application.preferences PROPERTIES LABELS data)

    add_executable(kos-language-test ../../tests/localization/LanguageTest.cpp)
    target_link_libraries(kos-language-test PRIVATE Kos::AppCore Qt6::Test)
    foreach(language zh_CN zh_TW zh_HK pt_BR pt_PT en_US fr_FR ja_JP)
        if(language MATCHES "^zh")
            set(expected zh)
        elseif(language MATCHES "^pt")
            set(expected pt)
        else()
            set(expected en)
        endif()
        add_test(NAME kos-language.${language} COMMAND kos-language-test)
        set_tests_properties(kos-language.${language} PROPERTIES
            ENVIRONMENT "LANG=en_US.UTF-8;LC_ALL=en_US.UTF-8;LANGUAGE=${language};EXPECTED_LANGUAGE=${expected}"
            LABELS data TIMEOUT 10)
    endforeach()
endif()
