include_guard(GLOBAL)

function(kos_add_application target)
    set(oneValueArgs URI DISPLAY_NAME DESKTOP_FILE)
    set(multiValueArgs SOURCES QML_SOURCES QML_FILES LINK_LIBRARIES)
    cmake_parse_arguments(KOS_APP "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    foreach(required_argument URI DISPLAY_NAME DESKTOP_FILE)
        if(NOT KOS_APP_${required_argument})
            message(FATAL_ERROR "kos_add_application(${target}) requires ${required_argument}")
        endif()
    endforeach()

    qt_add_executable(${target}
        ${KOS_APP_SOURCES}
    )

    qt_add_qml_module(${target}
        URI ${KOS_APP_URI}
        VERSION 1.0
        RESOURCE_PREFIX /qt/qml
        SOURCES ${KOS_APP_QML_SOURCES}
        QML_FILES ${KOS_APP_QML_FILES}
    )

    target_link_libraries(${target} PRIVATE
        Kos::AppCore
        Kos::Ui
        Kos::UiPlugin
        Qt6::Core
        Qt6::Gui
        Qt6::Qml
        Qt6::Quick
        Qt6::QuickControls2
        ${KOS_APP_LINK_LIBRARIES}
    )

    target_compile_definitions(${target} PRIVATE
        KOS_APP_VERSION="${PROJECT_VERSION}"
    )

    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        target_compile_options(${target} PRIVATE
            -Wall
            -Wextra
            -Wpedantic
        )
    endif()

    install(TARGETS ${target}
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    )
    install(FILES ${KOS_APP_DESKTOP_FILE}
        DESTINATION ${CMAKE_INSTALL_DATAROOTDIR}/applications
    )

    if(BUILD_TESTING)
        add_test(NAME ${target}.version COMMAND ${target} --version)
        set_tests_properties(${target}.version PROPERTIES
            ENVIRONMENT "QT_QPA_PLATFORM=offscreen"
            TIMEOUT 10
        )

        add_test(NAME ${target}.qml-smoke COMMAND ${target} --smoke-test)
        set_tests_properties(${target}.qml-smoke PROPERTIES
            ENVIRONMENT
                "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;QSG_RHI_BACKEND=software"
            TIMEOUT 10
        )
    endif()
endfunction()
