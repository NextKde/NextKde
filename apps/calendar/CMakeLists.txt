if(NOT TARGET kos_demo_ui)
    add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../shared/demo-ui ${CMAKE_CURRENT_BINARY_DIR}/demo-ui)
endif()

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
        qml/CalendarGlassSurface.qml
        qml/CalendarToolTip.qml
        qml/CalendarPopupSurface.qml
        qml/CalendarStyle.qml
        qml/CalendarButton.qml
        qml/CalendarCheckBox.qml
        qml/CalendarTimeField.qml
        qml/CalendarDateField.qml
        qml/CalendarTextField.qml
        qml/CalendarComboBox.qml
        qml/CalendarEditorFooter.qml
        qml/CalendarMonthView.qml
        qml/CalendarScheduleView.qml
        qml/CalendarTaskEditorDialog.qml
        qml/EventEditorDialog.qml
        qml/EventDetailsPopover.qml
        qml/HolidayCalendarDialog.qml
        qml/CalendarCategoryDialog.qml
        qml/CalendarEditorTabs.qml
        qml/CalendarOrganizationDialog.qml
        qml/CalendarReminderInlineFields.qml
        qml/CalendarReminderRow.qml
        qml/CalendarReminderInlineAdd.qml
        qml/CalendarReminderSection.qml
        qml/CalendarRemindersView.qml
        qml/CalendarReminderSidebar.qml
        qml/CalendarReminderListPopover.qml
        qml/CalendarReminderImages.qml
    LINK_LIBRARIES
        kos_demo_ui
        kos_demo_ui_plugin
        Kos::PimClient
        Kos::PimClientPlugin
        Qt6::QuickDialogs2
)
