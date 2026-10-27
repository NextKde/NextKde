# KOS_WEATHER_TESTS_ONLY is set by the root project when it descends here only
# for the tests below: kos-weather links Kos::Ui, which is gated behind the app
# flags, so building the application from a test-only descent would fail.
if(NOT KOS_WEATHER_TESTS_ONLY)
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
        qml/WeatherIcon.qml
        qml/WeatherLoadingIndicator.qml
        qml/SnowGlass.qml
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

# 批 7/11｜雪粒子 sprite（程序化生成，无外部美术资源）；雨 sprite 已随批 11
# 删除下落雨粒子层一并移除。与 QML 模块同前缀打包。
# 批 12｜雨改折射：drop-offset.png（偏移图，PIL 脚本生成）+ 折射 shader。
qt_add_resources(kos-weather "weather_particles"
    PREFIX "/qt/qml/Kos/Apps/Weather"
    BASE ${CMAKE_CURRENT_SOURCE_DIR}
    FILES
        qml/particles/snow.png
        qml/particles/drop-offset.png
        qml/shaders/rain_refract.vert.qsb
        qml/shaders/rain_refract.frag.qsb
        qml/shaders/snow_glass.vert.qsb
        qml/shaders/snow_glass.frag.qsb
)
endif()

if(BUILD_TESTING)
    # kos-weather.qml-smoke is registered by kos_add_application, so it only
    # exists when the application itself was configured.
    if(TARGET kos-weather)
        set_property(TEST kos-weather.qml-smoke APPEND PROPERTY ENVIRONMENT
            "KOS_WEATHER_DISABLE_SERVICE_AUTOSTART=1"
        )
    endif()

    # The client test recompiles WeatherClient.cpp and links nothing from the
    # app, so it configures and runs even when KOS_BUILD_WEATHER is off. It is
    # the only coverage WeatherClient has, so it must not sit behind the flag
    # that gates the application.
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
        LABELS data
    )
endif()
