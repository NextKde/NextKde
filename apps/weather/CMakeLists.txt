kos_add_application(kos-weather
    URI Kos.Apps.Weather
    DISPLAY_NAME "KOS Weather"
    DESKTOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-weather.desktop
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

if(BUILD_TESTING)
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
    set_tests_properties(kos-weather.client-snapshot PROPERTIES TIMEOUT 10)
endif()
