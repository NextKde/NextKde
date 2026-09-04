kos_add_application(kos-weather
    URI Kos.Apps.Weather
    DISPLAY_NAME "KOS Weather"
    DESKTOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-weather.desktop.in
    ICON_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-weather.svg
    METAINFO_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/org.nextkde.Kos.Weather.metainfo.xml
    SOURCES
        src/main.cpp
    QML_SOURCES
        src/WeatherClient.cpp
        src/WeatherClient.h
    QML_FILES
        qml/Main.qml
    LINK_LIBRARIES
        Qt6::Network
)

# Qt's generated QML type registrar includes native element headers by their
# basename, so expose this app's private source directory to that target.
target_include_directories(kos-weather PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)
add_dependencies(kos-weather kos-data-service-build)
target_compile_definitions(kos-weather PRIVATE
    KOS_DATA_SERVICE_BUILD_PATH="${KOS_DATA_SERVICE_EXECUTABLE}"
)

if(BUILD_TESTING)
    set_property(TEST kos-weather.qml-smoke APPEND PROPERTY ENVIRONMENT
        "KOS_WEATHER_DISABLE_SERVICE_AUTOSTART=1"
    )

    qt_add_executable(kos-weather-client-test
        tests/WeatherClientTest.cpp
        src/WeatherClient.cpp
        src/WeatherClient.h
    )
    target_include_directories(kos-weather-client-test PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    target_link_libraries(kos-weather-client-test PRIVATE
        Qt6::Core
        Qt6::Network
        Qt6::Qml
        Qt6::Test
    )
    add_test(NAME kos-weather.client-snapshot COMMAND kos-weather-client-test)
    set_tests_properties(kos-weather.client-snapshot PROPERTIES
        ENVIRONMENT "KOS_WEATHER_DISABLE_SERVICE_AUTOSTART=1"
        TIMEOUT 10
    )
endif()
