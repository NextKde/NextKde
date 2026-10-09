# Header-only, official Microsoft projection. No runtime is added to the package.
set(_cppwinrt_version "2.0.250303.1")
set(_cppwinrt_root "${CMAKE_CURRENT_SOURCE_DIR}/../_vendor/cppwinrt-${_cppwinrt_version}")
set(LISTENFREE_CPPWINRT_INCLUDE "${_cppwinrt_root}/include" CACHE PATH "Generated Microsoft C++/WinRT headers")
if(NOT EXISTS "${LISTENFREE_CPPWINRT_INCLUDE}/winrt/Windows.Media.h")
    file(MAKE_DIRECTORY "${_cppwinrt_root}")
    if(NOT EXISTS "${_cppwinrt_root}/bin/cppwinrt.exe")
        file(DOWNLOAD
            "https://api.nuget.org/v3-flatcontainer/microsoft.windows.cppwinrt/${_cppwinrt_version}/microsoft.windows.cppwinrt.${_cppwinrt_version}.nupkg"
            "${_cppwinrt_root}/package.nupkg" TLS_VERIFY ON STATUS _download)
        list(GET _download 0 _error)
        if(NOT _error EQUAL 0)
            message(FATAL_ERROR "Cannot download C++/WinRT: ${_download}; set LISTENFREE_CPPWINRT_INCLUDE to existing generated headers")
        endif()
        file(ARCHIVE_EXTRACT INPUT "${_cppwinrt_root}/package.nupkg" DESTINATION "${_cppwinrt_root}")
    endif()
    execute_process(COMMAND "${_cppwinrt_root}/bin/cppwinrt.exe"
        -input "$ENV{SystemRoot}/System32/WinMetadata"
        -output "${LISTENFREE_CPPWINRT_INCLUDE}"
        -include Windows.Media Windows.Storage.Streams Windows.Foundation
        RESULT_VARIABLE _projection)
    if(NOT _projection EQUAL 0)
        message(FATAL_ERROR "C++/WinRT projection generation failed: ${_projection}")
    endif()
endif()
add_library(listenfree_windows_media STATIC src/app/windows_media_session.cpp src/app/windows_media_session.h)
target_include_directories(listenfree_windows_media SYSTEM PRIVATE "${LISTENFREE_CPPWINRT_INCLUDE}")
target_link_libraries(listenfree_windows_media PRIVATE listenfree_portable runtimeobject ole32 oleaut32 shcore shlwapi shell32 propsys uuid)
target_link_libraries(listenfree PRIVATE listenfree_windows_media)
if(LISTENFREE_BUILD_TESTS)
    add_executable(listenfree_windows_media_tests tests/windows_media_session_tests.cpp)
    target_include_directories(listenfree_windows_media_tests SYSTEM PRIVATE "${LISTENFREE_CPPWINRT_INCLUDE}")
    target_link_libraries(listenfree_windows_media_tests PRIVATE listenfree_windows_media listenfree_portable Qt6::Test runtimeobject ole32 oleaut32)
    add_test(NAME listenfree_windows_media_tests COMMAND listenfree_windows_media_tests)
    set_tests_properties(listenfree_windows_media_tests PROPERTIES TIMEOUT 60)
endif()
