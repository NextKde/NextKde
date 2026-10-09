# Official prebuilt x64 distribution, pinned to the GitHub release digest.
set(_winsparkle_version "0.9.4")
set(_winsparkle_archive_root "${_listenfree_vendor}/winsparkle-${_winsparkle_version}")
set(LISTENFREE_WINSPARKLE_ROOT "${_winsparkle_archive_root}/WinSparkle-${_winsparkle_version}" CACHE PATH "Official WinSparkle binary distribution")
if(NOT EXISTS "${LISTENFREE_WINSPARKLE_ROOT}/x64/Release/WinSparkle.dll")
    file(MAKE_DIRECTORY "${_winsparkle_archive_root}")
    file(DOWNLOAD
        "https://github.com/vslavik/winsparkle/releases/download/v${_winsparkle_version}/WinSparkle-${_winsparkle_version}.zip"
        "${_winsparkle_archive_root}/package.zip"
        TLS_VERIFY ON
        EXPECTED_HASH SHA256=6037df37fc263bd1650a1c4949681a9d40ffe991d01f35892a406cb5d103c976
        STATUS _download)
    list(GET _download 0 _error)
    if(NOT _error EQUAL 0)
        message(FATAL_ERROR "Cannot download WinSparkle: ${_download}; set LISTENFREE_WINSPARKLE_ROOT to an extracted official 0.9.4 distribution")
    endif()
    file(ARCHIVE_EXTRACT INPUT "${_winsparkle_archive_root}/package.zip" DESTINATION "${_winsparkle_archive_root}")
endif()
add_library(listenfree_updates STATIC src/app/update_service.cpp src/app/update_service.h src/app/update_public_key.h)
target_include_directories(listenfree_updates PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src" PRIVATE "${LISTENFREE_WINSPARKLE_ROOT}/include")
target_link_libraries(listenfree_updates PUBLIC Qt6::Core)
# QLibrary loads the DLL only on manual update checks; no startup import.
target_link_libraries(listenfree PRIVATE listenfree_updates)
add_custom_command(TARGET listenfree POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${LISTENFREE_WINSPARKLE_ROOT}/x64/Release/WinSparkle.dll" "$<TARGET_FILE_DIR:listenfree>/WinSparkle.dll")
if(LISTENFREE_BUILD_TESTS)
    add_executable(listenfree_update_tests tests/update_service_tests.cpp)
    target_link_libraries(listenfree_update_tests PRIVATE listenfree_updates Qt6::Test Qt6::Network)
    add_custom_command(TARGET listenfree_update_tests POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${LISTENFREE_WINSPARKLE_ROOT}/x64/Release/WinSparkle.dll" "$<TARGET_FILE_DIR:listenfree_update_tests>/WinSparkle.dll")
    target_compile_definitions(listenfree_update_tests PRIVATE UPDATE_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures/updater")
    # WinSparkle's wxWidgets application is initialized once per process.
    foreach(case IN ITEMS missingLibrary currentVersion newerVersion signedDownload invalidSignature cancelledDownload installerArguments)
        add_test(NAME listenfree_update_${case} COMMAND listenfree_update_tests ${case})
        set_tests_properties(listenfree_update_${case} PROPERTIES TIMEOUT 45 RUN_SERIAL TRUE)
    endforeach()
endif()
