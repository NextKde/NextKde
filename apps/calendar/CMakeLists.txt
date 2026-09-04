find_package(Qt6 6.5 REQUIRED COMPONENTS QuickDialogs2)

kos_add_application(kos-calendar
    URI Kos.Apps.Calendar
    DISPLAY_NAME "KOS Calendar"
    DESKTOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-calendar.desktop.in
    ICON_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-calendar.svg
    METAINFO_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/org.nextkde.Kos.Calendar.metainfo.xml
    SOURCES
        src/main.cpp
    QML_FILES
        qml/Main.qml
        qml/CalendarMonthView.qml
        qml/CalendarScheduleView.qml
        qml/CalendarTaskEditorDialog.qml
        qml/EventEditorDialog.qml
    LINK_LIBRARIES
        Kos::PimClient
        Kos::PimClientPlugin
        Qt6::QuickDialogs2
)
