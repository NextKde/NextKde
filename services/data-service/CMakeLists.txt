find_program(KOS_GO_EXECUTABLE NAMES go REQUIRED)

set(kos_data_service_sources
    ${CMAKE_CURRENT_SOURCE_DIR}/main.go
    ${CMAKE_CURRENT_SOURCE_DIR}/weather.go
    ${CMAKE_CURRENT_SOURCE_DIR}/go.mod
    ${CMAKE_CURRENT_SOURCE_DIR}/go.sum
)
set(KOS_DATA_SERVICE_EXECUTABLE
    ${CMAKE_CURRENT_BINARY_DIR}/kos-data-service
)

add_custom_command(
    OUTPUT ${KOS_DATA_SERVICE_EXECUTABLE}
    COMMAND ${CMAKE_COMMAND} -E make_directory
        ${CMAKE_CURRENT_BINARY_DIR}/go-cache
    COMMAND ${CMAKE_COMMAND} -E env
        GOCACHE=${CMAKE_CURRENT_BINARY_DIR}/go-cache
        ${KOS_GO_EXECUTABLE} build -trimpath
            -o ${KOS_DATA_SERVICE_EXECUTABLE} .
    DEPENDS ${kos_data_service_sources}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Building KOS data service"
    VERBATIM
)

add_custom_target(kos-data-service-build ALL
    DEPENDS ${KOS_DATA_SERVICE_EXECUTABLE}
)

configure_file(
    systemd/kos-data.service.in
    ${CMAKE_CURRENT_BINARY_DIR}/kos-data.service
    @ONLY
)

install(PROGRAMS ${KOS_DATA_SERVICE_EXECUTABLE}
    DESTINATION ${CMAKE_INSTALL_LIBEXECDIR}
)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/kos-data.service
    DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/systemd/user
)

if(BUILD_TESTING)
    add_test(NAME kos-data-service.go
        COMMAND ${CMAKE_COMMAND} -E env
            GOCACHE=${CMAKE_CURRENT_BINARY_DIR}/go-test-cache
            ${KOS_GO_EXECUTABLE} test ./...
    )
    set_tests_properties(kos-data-service.go PROPERTIES
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        TIMEOUT 60
    )
endif()

set(KOS_DATA_SERVICE_EXECUTABLE
    ${KOS_DATA_SERVICE_EXECUTABLE}
    PARENT_SCOPE
)
