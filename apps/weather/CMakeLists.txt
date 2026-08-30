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
