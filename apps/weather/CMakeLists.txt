kos_add_application(kos-weather
    URI Kos.Apps.Weather
    DISPLAY_NAME "KOS Weather"
    DESKTOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-weather.desktop
    SOURCES
        src/main.cpp
    QML_FILES
        qml/Main.qml
)
