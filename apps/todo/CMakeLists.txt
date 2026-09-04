kos_add_application(kos-todo
    URI Kos.Apps.Todo
    DISPLAY_NAME "KOS Todo"
    DESKTOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-todo.desktop.in
    ICON_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-todo.svg
    METAINFO_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/org.nextkde.Kos.Todo.metainfo.xml
    SOURCES
        src/main.cpp
    QML_FILES
        qml/Main.qml
        qml/TodoEditorDialog.qml
    LINK_LIBRARIES
        Kos::PimClient
        Kos::PimClientPlugin
)
