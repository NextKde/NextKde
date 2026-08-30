kos_add_application(kos-calendar
    URI Kos.Apps.Calendar
    DISPLAY_NAME "KOS Calendar"
    DESKTOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-calendar.desktop
    SOURCES
        src/main.cpp
    QML_FILES
        qml/Main.qml
)
