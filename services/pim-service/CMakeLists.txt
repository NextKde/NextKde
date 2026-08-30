add_library(kos_pim_service_core STATIC
    src/PimStore.cpp
    src/PimStore.h
)
target_include_directories(kos_pim_service_core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)
target_link_libraries(kos_pim_service_core PUBLIC
    Qt6::Core
    Qt6::DBus
    KF6::CalendarCore
)

qt_add_executable(kos-pim-service
    src/main.cpp
)
target_link_libraries(kos-pim-service PRIVATE
    kos_pim_service_core
)
target_compile_definitions(kos-pim-service PRIVATE
    KOS_APP_VERSION="${PROJECT_VERSION}"
)

configure_file(
    data/org.nextkde.Kos.Pim1.service.in
    ${CMAKE_CURRENT_BINARY_DIR}/org.nextkde.Kos.Pim1.service
    @ONLY
)

install(TARGETS kos-pim-service
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/org.nextkde.Kos.Pim1.service
    DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services
)

if(BUILD_TESTING)
    qt_add_executable(kos-pim-store-test
        tests/PimStoreTest.cpp
    )
    target_link_libraries(kos-pim-store-test PRIVATE
        kos_pim_service_core
        Qt6::Test
    )
    add_test(NAME kos-pim.store COMMAND kos-pim-store-test)
    set_tests_properties(kos-pim.store PROPERTIES TIMEOUT 20)

    find_program(DBUS_RUN_SESSION_EXECUTABLE dbus-run-session REQUIRED)
    qt_add_executable(kos-pim-dbus-test
        tests/PimDbusTest.cpp
    )
    target_link_libraries(kos-pim-dbus-test PRIVATE
        Qt6::Core
        Qt6::DBus
        Qt6::Test
    )
    add_test(NAME kos-pim.dbus
        COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} --
            $<TARGET_FILE:kos-pim-dbus-test>
            $<TARGET_FILE:kos-pim-service>
    )
    set_tests_properties(kos-pim.dbus PROPERTIES TIMEOUT 20)
endif()
