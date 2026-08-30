kos_add_application(kos-music
    URI Kos.Apps.Music
    DISPLAY_NAME "KOS Music"
    DESKTOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-music.desktop
    SOURCES
        src/main.cpp
    QML_FILES
        qml/Main.qml
)
