# The old command remains for pinned launchers and scripts, with no second UI.
add_executable(kos-todo src/main.cpp)
target_link_libraries(kos-todo PRIVATE Qt6::Core)
add_dependencies(kos-todo kos-calendar)
install(TARGETS kos-todo RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
set(KOS_APP_EXECUTABLE "${CMAKE_INSTALL_FULL_BINDIR}/kos-todo")
configure_file(data/kos-todo.desktop.in kos-todo.desktop @ONLY)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/kos-todo.desktop"
    DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/applications)

# Preserve old pinned-icon lookups without shipping a second app identity.
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../calendar/data/kos-calendar.svg"
    DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/icons/hicolor/scalable/apps
    RENAME kos-todo.svg)

if(BUILD_TESTING)
    find_program(KOS_TODO_REVIEW_PYTHON NAMES python3)
    find_program(KOS_TODO_REVIEW_DBUS NAMES dbus-run-session)
    find_program(KOS_TODO_REVIEW_DBUS_SEND NAMES dbus-send)
    if(KOS_TODO_REVIEW_PYTHON AND KOS_TODO_REVIEW_DBUS AND KOS_TODO_REVIEW_DBUS_SEND)
        add_test(NAME kos-calendar.unified-activation
            COMMAND ${KOS_TODO_REVIEW_PYTHON}
                ${CMAKE_CURRENT_SOURCE_DIR}/../calendar/tests/run-unified-activation-review.py
                ${CMAKE_BINARY_DIR})
        set_tests_properties(kos-calendar.unified-activation PROPERTIES LABELS "ui;headless" TIMEOUT 45)
    endif()
endif()
