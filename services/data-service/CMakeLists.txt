find_program(KOS_GO_EXECUTABLE NAMES go REQUIRED)

set(kos_data_service_sources
    ${CMAKE_CURRENT_SOURCE_DIR}/main.go
    ${CMAKE_CURRENT_SOURCE_DIR}/weather.go
    ${CMAKE_CURRENT_SOURCE_DIR}/desktop_placement.go
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
    # -buildvcs=false: Go stamps VCS info by shelling out to git, and that step
    # aborts the build with "error obtaining VCS status: exit status 128" when
    # git cannot read the checkout -- the usual case in a CI container, where
    # the workspace is owned by another uid (dubious ownership). Nothing reads
    # the stamped info, so drop it; the binary is then identical wherever it
    # was built. The Nix path gets the same behaviour from buildGoModule.
    COMMAND ${CMAKE_COMMAND} -E env
        GOCACHE=${CMAKE_CURRENT_BINARY_DIR}/go-cache
        ${KOS_GO_EXECUTABLE} build -trimpath -buildvcs=false
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
    # The first run on a cold module cache compiles the whole standard library
    # before the first assertion executes and takes well over a minute; a warm
    # cache finishes in about ten seconds. One number has to cover both, and
    # only the cold path matters to CI, so size it for that.
    set_tests_properties(kos-data-service.go PROPERTIES
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
        TIMEOUT 180
        LABELS data
    )
endif()

set(KOS_DATA_SERVICE_EXECUTABLE
    ${KOS_DATA_SERVICE_EXECUTABLE}
    PARENT_SCOPE
)
