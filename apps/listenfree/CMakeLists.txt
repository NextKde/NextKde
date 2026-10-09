cmake_minimum_required(VERSION 3.28)
project(ListenFree VERSION 0.3.8 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

option(LISTENFREE_BUILD_TESTS "Build ListenFree tests" ON)
option(LISTENFREE_SEGMENT_HEAP "Use Windows 10 2004+ Segment Heap" ON)
option(LISTENFREE_BUILD_MPV_PROBE "Build the optional libmpv capability probe" OFF)
option(LISTENFREE_BUILD_MPV_BACKEND "Build the optional libmpv playback backend" OFF)
set(LISTENFREE_MPV_ROOT "" CACHE PATH "Root of an extracted libmpv development package")
option(LISTENFREE_BUILD_QMMP_BACKEND "Build the Qmmp application audio backend" ON)
set(_listenfree_vendor "${CMAKE_CURRENT_SOURCE_DIR}/../_vendor")
set(LISTENFREE_QMMP_SOURCE_ROOT "${_listenfree_vendor}/qmmp-2.4.1" CACHE PATH "Root of the Qmmp source tree")
set(LISTENFREE_QMMP_LIBRARY "${_listenfree_vendor}/qmmp-stage-qt/libqmmp.dll.a" CACHE FILEPATH "Qmmp import library")
set(LISTENFREE_QMMP_RUNTIME "${_listenfree_vendor}/qmmp-stage-qt/libqmmp.dll" CACHE FILEPATH "Qmmp runtime DLL")
set(LISTENFREE_QMMP_UI_LIBRARY "${_listenfree_vendor}/qmmp-build-qt/src/qmmpui/libqmmpui.dll.a" CACHE FILEPATH "Qmmp UI import library")
set(LISTENFREE_QMMP_PLUGIN_ROOT "${_listenfree_vendor}/qmmp-stage-qt" CACHE PATH "Staged Qmmp plugin root used by tests")
if(NOT LISTENFREE_BUILD_QMMP_BACKEND)
    message(FATAL_ERROR "The portable application requires LISTENFREE_BUILD_QMMP_BACKEND=ON")
endif()

# Qt Creator projects do not always load CMakePresets.json or the vcpkg
# toolchain automatically. Keep the checked-in dependency prefix discoverable
# in that case so Configure can resolve TagLib without manual cache surgery.
if(NOT DEFINED VCPKG_TARGET_TRIPLET OR VCPKG_TARGET_TRIPLET STREQUAL "")
    set(VCPKG_TARGET_TRIPLET "x64-mingw-dynamic")
endif()
set(_listenfree_vcpkg_prefix "${CMAKE_CURRENT_SOURCE_DIR}/.vcpkg_installed/${VCPKG_TARGET_TRIPLET}")
if(EXISTS "${_listenfree_vcpkg_prefix}")
    list(PREPEND CMAKE_PREFIX_PATH "${_listenfree_vcpkg_prefix}")
endif()

find_package(Qt6 6.11.2 REQUIRED COMPONENTS Core Gui Qml Quick QuickDialogs2 Sql Multimedia Network Concurrent Test Widgets ShaderTools)
find_package(TagLib 2.3.1 CONFIG REQUIRED)
find_package(ZLIB REQUIRED)
find_package(qjs CONFIG REQUIRED)
qt_standard_project_setup(REQUIRES 6.11)

add_library(listenfree_domain INTERFACE)
target_include_directories(listenfree_domain INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/src)
target_compile_features(listenfree_domain INTERFACE cxx_std_20)

add_library(listenfree_application STATIC
    src/application/ports.h
    src/application/playback_service.h
    src/application/playback_service.cpp
    src/application/application_facade.h
    src/application/application_facade.cpp
)
target_link_libraries(listenfree_application PUBLIC listenfree_domain Qt6::Core)
target_include_directories(listenfree_application PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

add_library(listenfree_database STATIC
    src/infrastructure/database/database.h
    src/infrastructure/database/database.cpp
    src/infrastructure/database/repositories.h
    src/infrastructure/database/repositories.cpp
)
target_link_libraries(listenfree_database PUBLIC listenfree_domain Qt6::Core Qt6::Sql)
target_include_directories(listenfree_database PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

add_library(listenfree_library STATIC
    src/infrastructure/library/library_directory_watcher.h
    src/infrastructure/library/library_directory_watcher.cpp
    src/infrastructure/library/library_scanner.h
    src/infrastructure/library/library_scanner.cpp
    src/infrastructure/library/library_scan_writer.h
    src/infrastructure/library/library_scan_writer.cpp
)
target_link_libraries(listenfree_library PUBLIC listenfree_domain listenfree_database Qt6::Core Qt6::Concurrent PRIVATE TagLib::tag)
target_include_directories(listenfree_library PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

add_library(listenfree_media STATIC
    src/media/playback_state_machine.h
    src/media/playback_state_machine.cpp
    src/media/qt_audio_player.h
    src/media/qt_audio_player.cpp
)
target_link_libraries(listenfree_media PUBLIC listenfree_domain Qt6::Core PRIVATE Qt6::Multimedia)
target_include_directories(listenfree_media PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

if(LISTENFREE_BUILD_MPV_BACKEND)
    if(MSVC)
        set(_listenfree_mpv_library_candidates
            "${LISTENFREE_MPV_ROOT}/mpv.lib"
            "${LISTENFREE_MPV_ROOT}/libmpv.lib")
    else()
        set(_listenfree_mpv_library_candidates "${LISTENFREE_MPV_ROOT}/libmpv.dll.a")
    endif()
    set(_listenfree_mpv_library "")
    foreach(_candidate IN LISTS _listenfree_mpv_library_candidates)
        if(EXISTS "${_candidate}")
            set(_listenfree_mpv_library "${_candidate}")
            break()
        endif()
    endforeach()
    if(NOT LISTENFREE_MPV_ROOT OR
       NOT EXISTS "${LISTENFREE_MPV_ROOT}/include/mpv/client.h" OR
       NOT EXISTS "${LISTENFREE_MPV_ROOT}/libmpv-2.dll" OR
       NOT _listenfree_mpv_library)
        message(FATAL_ERROR "LISTENFREE_MPV_ROOT must point to a libmpv development package when LISTENFREE_BUILD_MPV_BACKEND=ON")
    endif()
    target_sources(listenfree_media PRIVATE
        src/media/mpv_audio_player.h
        src/media/mpv_audio_player.cpp
    )
    target_compile_definitions(listenfree_media PUBLIC LISTENFREE_HAS_MPV=1)
    target_include_directories(listenfree_media PRIVATE ${LISTENFREE_MPV_ROOT}/include)
    target_link_libraries(listenfree_media PRIVATE "${_listenfree_mpv_library}")
endif()

function(listenfree_copy_mpv_runtime target)
    if(LISTENFREE_BUILD_MPV_BACKEND)
        add_custom_command(TARGET ${target} POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                ${LISTENFREE_MPV_ROOT}/libmpv-2.dll
                $<TARGET_FILE_DIR:${target}>/libmpv-2.dll)
    endif()
endfunction()

if(LISTENFREE_BUILD_QMMP_BACKEND)
    find_path(LISTENFREE_QMMP_INCLUDE_ROOT
        NAMES qmmp/soundcore.h
        HINTS ${LISTENFREE_QMMP_SOURCE_ROOT}/src
        REQUIRED)
    if(NOT EXISTS "${LISTENFREE_QMMP_LIBRARY}")
        message(FATAL_ERROR "LISTENFREE_QMMP_LIBRARY must name the built Qmmp import library")
    endif()
    add_library(listenfree_qmmp_import SHARED IMPORTED GLOBAL)
    set_target_properties(listenfree_qmmp_import PROPERTIES
        IMPORTED_IMPLIB "${LISTENFREE_QMMP_LIBRARY}"
        INTERFACE_INCLUDE_DIRECTORIES "${LISTENFREE_QMMP_INCLUDE_ROOT}")
    if(EXISTS "${LISTENFREE_QMMP_RUNTIME}")
        set_target_properties(listenfree_qmmp_import PROPERTIES
            IMPORTED_LOCATION "${LISTENFREE_QMMP_RUNTIME}")
    endif()
    add_library(listenfree_qmmp_media STATIC
        src/media/qmmp_audio_player.h
        src/media/qmmp_audio_player.cpp)
    target_link_libraries(listenfree_qmmp_media
        PUBLIC listenfree_application listenfree_domain Qt6::Core
        PRIVATE Qt6::Gui
        PRIVATE listenfree_qmmp_import)
    target_include_directories(listenfree_qmmp_media PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
    if(WIN32)
        target_link_libraries(listenfree_qmmp_media PRIVATE ole32 propsys)
    endif()
    add_library(listenfree_sound_dsp STATIC src/media/sound_effects.cpp src/media/sound_effects.h)
    target_include_directories(listenfree_sound_dsp PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_link_libraries(listenfree_sound_dsp PUBLIC Qt6::Core)
    add_library(listenfree_sound MODULE src/media/sound_effect_plugin.cpp)
    target_link_libraries(listenfree_sound PRIVATE listenfree_sound_dsp listenfree_qmmp_import Qt6::Core)
    set_target_properties(listenfree_sound PROPERTIES PREFIX "" OUTPUT_NAME "listenfree_sound"
        RUNTIME_OUTPUT_DIRECTORY "${LISTENFREE_QMMP_PLUGIN_ROOT}/Effect"
        LIBRARY_OUTPUT_DIRECTORY "${LISTENFREE_QMMP_PLUGIN_ROOT}/Effect")
    add_dependencies(listenfree_qmmp_media listenfree_sound)
    if(LISTENFREE_BUILD_TESTS AND LISTENFREE_QMMP_PLUGIN_ROOT)
        add_executable(listenfree_qmmp_media_tests tests/qmmp_audio_player_tests.cpp)
        target_link_libraries(listenfree_qmmp_media_tests PRIVATE
            listenfree_qmmp_media Qt6::Test Qt6::Network)
        target_include_directories(listenfree_qmmp_media_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
        if(EXISTS "${LISTENFREE_QMMP_RUNTIME}")
            add_custom_command(TARGET listenfree_qmmp_media_tests POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${LISTENFREE_QMMP_RUNTIME}"
                    "$<TARGET_FILE_DIR:listenfree_qmmp_media_tests>")
        endif()
        add_test(NAME listenfree_qmmp_media_tests COMMAND listenfree_qmmp_media_tests -o -,txt)
        set_tests_properties(listenfree_qmmp_media_tests PROPERTIES
            TIMEOUT 30
            ENVIRONMENT "QMMP_PLUGINS=${LISTENFREE_QMMP_PLUGIN_ROOT};LISTENFREE_QMMP_OUTPUT=null")
    endif()
endif()

add_library(listenfree_source_protocol STATIC
    src/sourcehost/source_protocol.h
    src/sourcehost/source_protocol.cpp
)
target_link_libraries(listenfree_source_protocol PUBLIC Qt6::Core)
target_include_directories(listenfree_source_protocol PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

add_library(listenfree_plugin_runtime STATIC
    src/sourcehost/plugin_runtime.h
    src/sourcehost/plugin_runtime.cpp
)
target_link_libraries(listenfree_plugin_runtime PUBLIC listenfree_source_protocol Qt6::Core Qt6::Network ZLIB::ZLIB qjs)
qt_add_resources(listenfree_plugin_runtime sourcehost_browser
    PREFIX "/sourcehost"
    BASE "src/third_party/sourcehost_browser"
    FILES src/third_party/sourcehost_browser/browser.js)
target_include_directories(listenfree_plugin_runtime PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
if(WIN32)
    target_link_libraries(listenfree_plugin_runtime PRIVATE bcrypt crypt32)
endif()

add_executable(listenfree-sourcehost src/sourcehost/sourcehost_main.cpp)
target_link_libraries(listenfree-sourcehost PRIVATE listenfree_plugin_runtime Qt6::Core)

# Local-only, non-destructive scanner experiment. It defaults to an in-memory
# database and is intentionally separate from the GUI executable.
add_executable(listenfree-library-scan-probe tools/library_scan_probe.cpp)
target_link_libraries(listenfree-library-scan-probe PRIVATE listenfree_library listenfree_database Qt6::Core Qt6::Sql)
target_include_directories(listenfree-library-scan-probe PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

# Phase 2.1 gate benchmark: production scan pipeline (controller + scan writer
# thread) with main-thread lag probing and linear extrapolation to the target
# library size.
add_executable(listenfree-scan-bench tools/scan_bench.cpp)
target_link_libraries(listenfree-scan-bench PRIVATE listenfree_qmlbridge listenfree_library listenfree_database listenfree_application listenfree_domain TagLib::tag Qt6::Core Qt6::Sql)
target_include_directories(listenfree-scan-bench PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

if(LISTENFREE_BUILD_MPV_PROBE)
    if(NOT LISTENFREE_MPV_ROOT)
        message(FATAL_ERROR "LISTENFREE_MPV_ROOT is required when LISTENFREE_BUILD_MPV_PROBE=ON")
    endif()
    add_executable(listenfree-mpv-core-probe tools/mpv_core_probe.cpp)
    target_include_directories(listenfree-mpv-core-probe PRIVATE ${LISTENFREE_MPV_ROOT}/include)
    target_link_libraries(listenfree-mpv-core-probe PRIVATE
        ${LISTENFREE_MPV_ROOT}/libmpv.dll.a Qt6::Core)
    add_custom_command(TARGET listenfree-mpv-core-probe POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${LISTENFREE_MPV_ROOT}/libmpv-2.dll
            $<TARGET_FILE_DIR:listenfree-mpv-core-probe>/libmpv-2.dll)
endif()

add_library(listenfree_source_client STATIC
    src/sourcehost/sourcehost_client.h
    src/sourcehost/sourcehost_client.cpp
)
target_link_libraries(listenfree_source_client PUBLIC listenfree_domain listenfree_source_protocol Qt6::Core)
target_include_directories(listenfree_source_client PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

add_library(listenfree_online STATIC
    src/online/apple_hls.h
    src/online/apple_hls.cpp
    src/online/apple_music_token.h
    src/online/apple_music_token.cpp
    src/online/apple_dynamic_artwork_provider.h
    src/online/apple_dynamic_artwork_provider.cpp
    src/online/mock_online_provider.h
    src/online/mock_online_provider.cpp
)
target_link_libraries(listenfree_online PUBLIC listenfree_domain Qt6::Core Qt6::Network)
target_include_directories(listenfree_online PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
add_executable(listenfree-artist-visual-probe tools/artist_visual_probe.cpp)
target_link_libraries(listenfree-artist-visual-probe PRIVATE listenfree_online Qt6::Core Qt6::Network Qt6::Gui)

add_executable(listenfree-apple-cover-probe tools/apple_cover_probe.cpp)
target_link_libraries(listenfree-apple-cover-probe PRIVATE listenfree_online Qt6::Core Qt6::Network Qt6::Multimedia)
target_include_directories(listenfree-apple-cover-probe PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

add_library(listenfree_qmlbridge STATIC
    src/qmlbridge/list_models.h
    src/qmlbridge/list_models.cpp
    src/qmlbridge/controllers.h
    src/qmlbridge/controllers.cpp
    src/qmlbridge/wallpaper_library.h
    src/qmlbridge/wallpaper_library.cpp
)
target_link_libraries(listenfree_qmlbridge
    PUBLIC listenfree_application listenfree_database listenfree_library listenfree_online Qt6::Core Qt6::Qml
    PRIVATE listenfree_media
)
target_include_directories(listenfree_qmlbridge PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)
if(LISTENFREE_BUILD_MPV_BACKEND)
    target_compile_definitions(listenfree_qmlbridge PRIVATE LISTENFREE_HAS_MPV=1)
endif()

if(LISTENFREE_BUILD_QMMP_BACKEND)
    set(LISTENFREE_QMMP_UI_LIBRARY "" CACHE FILEPATH "Qmmp UI import library")
    add_library(listenfree_qmmp_ui SHARED IMPORTED)
    set_target_properties(listenfree_qmmp_ui PROPERTIES IMPORTED_IMPLIB "${LISTENFREE_QMMP_UI_LIBRARY}" INTERFACE_INCLUDE_DIRECTORIES "${LISTENFREE_QMMP_SOURCE_ROOT}/src")
    add_library(listenfree_portable STATIC src/online/platform_catalog.cpp src/online/platform_catalog.h src/qmlbridge/download_service.h src/qmlbridge/download_service.cpp src/qmlbridge/collection_service.h src/qmlbridge/collection_service.cpp src/qmlbridge/portable_session.h src/qmlbridge/portable_session.cpp src/qmlbridge/lyric_matching.cpp src/qmlbridge/source_controller.h src/qmlbridge/source_controller.cpp src/media/media_stream_proxy.h src/media/media_stream_proxy.cpp)
    target_sources(listenfree_portable PRIVATE src/qmlbridge/audio_effects.cpp src/qmlbridge/equalizer_presets.h)
    target_sources(listenfree_portable PRIVATE src/online/bilibili_client.cpp src/online/bilibili_client.h)
    target_link_libraries(listenfree_portable PUBLIC listenfree_sound_dsp)
    target_link_libraries(listenfree_portable PUBLIC listenfree_qmmp_media listenfree_qmlbridge listenfree_source_client listenfree_qmmp_ui listenfree_qmmp_import Qt6::Widgets Qt6::Network Qt6::Concurrent TagLib::tag ZLIB::ZLIB)
    target_sources(listenfree_portable PRIVATE src/qmlbridge/fume_layout.h src/qmlbridge/folia_scene.h src/qmlbridge/folia_scene.cpp src/qmlbridge/immersive_controller.h src/qmlbridge/immersive_controller.cpp)
    target_link_libraries(listenfree_portable PUBLIC Qt6::Multimedia Qt6::Quick)
    add_executable(listenfree-source-catalog-probe EXCLUDE_FROM_ALL tools/source_catalog_probe.cpp)
    target_link_libraries(listenfree-source-catalog-probe PRIVATE listenfree_portable)
    add_executable(listenfree-source-import-probe EXCLUDE_FROM_ALL tools/source_import_probe.cpp)
    target_link_libraries(listenfree-source-import-probe PRIVATE listenfree_portable)
    target_sources(listenfree_portable PRIVATE src/qmlbridge/smart_mix.cpp src/media/audio_tail_probe.h src/media/audio_tail_probe.cpp)
    target_sources(listenfree_portable PRIVATE src/media/mv_frame_stream.h src/media/mv_frame_stream.cpp)
    target_sources(listenfree_portable PRIVATE src/media/artwork_video.h src/media/artwork_video.cpp)
    target_sources(listenfree_portable PRIVATE src/online/lyric_sources.cpp src/online/lyric_sources.h src/third_party/qqmusic_des/des.cpp)
    target_sources(listenfree_portable PRIVATE src/online/lyric_search.cpp src/online/lyric_search.h)
    target_sources(listenfree_portable PRIVATE src/online/radio_catalog.h src/online/radio_catalog.cpp src/qmlbridge/radio_service.h src/qmlbridge/radio_service.cpp src/media/live_stream_relay.h src/media/live_stream_relay.cpp)
    set(LISTENFREE_LIVE_FFMPEG_ROOT "${_listenfree_vendor}/qmmp-vcpkg-installed-qt/x64-mingw-dynamic" CACHE PATH "FFmpeg already shipped with the Qmmp decoder")
    find_path(LISTENFREE_LIVE_FFMPEG_INCLUDE libavformat/avformat.h HINTS "${LISTENFREE_LIVE_FFMPEG_ROOT}/include" REQUIRED)
    target_include_directories(listenfree_portable PRIVATE "${LISTENFREE_LIVE_FFMPEG_INCLUDE}")
    foreach(part avformat avcodec avutil)
        find_library(LISTENFREE_LIVE_${part} NAMES ${part} HINTS "${LISTENFREE_LIVE_FFMPEG_ROOT}/lib" REQUIRED)
        target_link_libraries(listenfree_portable PRIVATE "${LISTENFREE_LIVE_${part}}")
    endforeach()
    if(LISTENFREE_BUILD_TESTS)
        add_executable(listenfree_audio_effects_tests tests/audio_effects_tests.cpp)
        target_link_libraries(listenfree_audio_effects_tests PRIVATE listenfree_sound_dsp listenfree_qmmp_import Qt6::Test)
        add_dependencies(listenfree_audio_effects_tests listenfree_sound)
        add_test(NAME listenfree_audio_effects_tests COMMAND listenfree_audio_effects_tests -o -,txt)
        add_executable(listenfree_immersive_tests tests/immersive_tests.cpp)
        target_link_libraries(listenfree_immersive_tests PRIVATE listenfree_portable Qt6::Test)
        add_executable(listenfree_smart_mix_tests tests/smart_mix_tests.cpp "${LISTENFREE_QMMP_SOURCE_ROOT}/src/plugins/Effect/crossfade/crossfadeplugin.cpp")
        target_link_libraries(listenfree_smart_mix_tests PRIVATE listenfree_portable Qt6::Test)
        add_executable(listenfree_radio_tests tests/radio_tests.cpp)
        target_link_libraries(listenfree_radio_tests PRIVATE listenfree_portable Qt6::Test)
        add_executable(listenfree_portable_tests tests/portable_session_tests.cpp)
        add_executable(listenfree_collection_tests tests/collection_tests.cpp)
        target_link_libraries(listenfree_collection_tests PRIVATE listenfree_portable Qt6::Test)
        if(WIN32)
            target_link_libraries(listenfree_collection_tests PRIVATE psapi)
        endif()
        add_test(NAME listenfree_collection_tests COMMAND listenfree_collection_tests -o -,txt)
        add_executable(listenfree_resource_tests tests/resource_ownership_tests.cpp)
        target_link_libraries(listenfree_resource_tests PRIVATE listenfree_portable Qt6::Test Qt6::Quick)
        target_compile_definitions(listenfree_resource_tests PRIVATE LISTENFREE_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}")
        add_test(NAME listenfree_resource_tests COMMAND listenfree_resource_tests)
        add_executable(listenfree_lyric_search_tests tests/lyric_search_tests.cpp)
        target_link_libraries(listenfree_lyric_search_tests PRIVATE listenfree_portable Qt6::Test)
        add_test(NAME listenfree_lyric_search_tests COMMAND listenfree_lyric_search_tests)
        add_executable(listenfree_bilibili_tests tests/bilibili_source_tests.cpp)
        target_link_libraries(listenfree_bilibili_tests PRIVATE listenfree_portable Qt6::Test)
        add_test(NAME listenfree_bilibili_tests COMMAND listenfree_bilibili_tests -o -,txt)
        set_tests_properties(listenfree_bilibili_tests PROPERTIES ENVIRONMENT "QMMP_PLUGINS=${LISTENFREE_QMMP_PLUGIN_ROOT};QT_QPA_PLATFORM=offscreen")
        target_link_libraries(listenfree_portable_tests PRIVATE listenfree_portable Qt6::Test Qt6::Quick)
        add_dependencies(listenfree_portable_tests listenfree-sourcehost)
    endif()
endif()
qt_add_executable(listenfree WIN32 src/app/listenfree.rc src/app/main.cpp src/app/platform_settings.h src/app/platform_settings.cpp src/app/shortcut_service.h src/app/shortcut_service.cpp src/qmlbridge/spring_value.h src/qmlbridge/lyric_text_metrics.h src/qmlbridge/background_contrast.h src/qmlbridge/album_mosaic_model.h)
if(WIN32 AND LISTENFREE_BUILD_QMMP_BACKEND)
    include(cmake/WindowsMediaSession.cmake)
    include(cmake/WinSparkle.cmake)
endif()
if(WIN32 AND LISTENFREE_SEGMENT_HEAP)
    # The OS chooses the allocator before DLL initialization; unsupported Windows
    # versions ignore heapType. Keep this switch for reproducible legacy-heap A/B.
    target_sources(listenfree PRIVATE src/app/segment_heap.rc)
    set_source_files_properties(src/app/segment_heap.rc PROPERTIES
        OBJECT_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/app/segment_heap.manifest")
    foreach(test_target IN ITEMS listenfree_portable_tests listenfree_immersive_tests listenfree_bilibili_tests)
        if(TARGET ${test_target})
            target_sources(${test_target} PRIVATE src/app/segment_heap.rc)
        endif()
    endforeach()
endif()
target_sources(listenfree_portable PRIVATE src/qmlbridge/account_service.h src/qmlbridge/account_service.cpp src/qmlbridge/duplicate_service.h src/qmlbridge/duplicate_service.cpp src/qmlbridge/settings_transfer.h src/qmlbridge/settings_transfer.cpp)
target_link_libraries(listenfree_portable PRIVATE advapi32 crypt32 bcrypt)
if(LISTENFREE_BUILD_TESTS)
    add_executable(listenfree_integration_tests tests/integration_completion_tests.cpp)
    target_link_libraries(listenfree_integration_tests PRIVATE listenfree_portable Qt6::Test)
    add_test(NAME listenfree_integration_tests COMMAND listenfree_integration_tests)
endif()
target_link_libraries(listenfree PRIVATE dwmapi)
qt_add_resources(listenfree listenfree_translations PREFIX "/translations" BASE "music_player_desktop/translations" FILES music_player_desktop/translations/en_US.json)
# windres does not reliably track the ICON file referenced inside the .rc.
# Recompile the native resource whenever the supplied application icon changes.
set_source_files_properties(src/app/listenfree.rc PROPERTIES
    OBJECT_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/music_player_desktop/assets/icons/app.ico")
set_source_files_properties(
    music_player_desktop/components/AppTheme.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)
qt_add_qml_module(listenfree
    URI ListenFree.Bootstrap
    VERSION 1.0
    QML_FILES ui/bootstrap/Main.qml
        music_player_desktop/AppShell.qml
        music_player_desktop/components/WindowChrome.qml
        music_player_desktop/components/WindowTrafficButton.qml
        music_player_desktop/components/AppTheme.qml
        music_player_desktop/components/GlassSurface.qml
        music_player_desktop/components/IconGlyph.qml
        music_player_desktop/components/RoundIconButton.qml
        music_player_desktop/components/ProgressBar.qml
        music_player_desktop/components/LiveWave.qml
        music_player_desktop/components/CoverArt.qml
        music_player_desktop/components/FloatingPlayer.qml
        music_player_desktop/components/UiButton.qml
        music_player_desktop/components/AlertDialog.qml
        music_player_desktop/components/SettingsTransferDialog.qml
        music_player_desktop/components/WallpaperPickerPopup.qml
        music_player_desktop/components/ScrollPosition.qml
        music_player_desktop/components/SegmentedTabBar.qml
        music_player_desktop/components/ArtworkTile.qml
        music_player_desktop/components/SongTable.qml
        music_player_desktop/components/SongRow.qml
        music_player_desktop/components/ContextMenu.qml
        music_player_desktop/components/SongContextMenu.qml
        music_player_desktop/components/QueuePanel.qml
        music_player_desktop/components/ImmersiveDiscQueue.qml
        music_player_desktop/components/QueueDiscSector.qml
        music_player_desktop/components/DownloadPanel.qml
        music_player_desktop/components/CommentsPanel.qml
        music_player_desktop/components/ArtworkBackground.qml
        music_player_desktop/components/NavigationCache.qml
        music_player_desktop/components/GlobalBackground.qml
    music_player_desktop/components/ArtistBackdrop.qml
        music_player_desktop/components/EqualizerPopup.qml
        music_player_desktop/components/LyricsMatchPopup.qml
        music_player_desktop/components/MetadataMatchPopup.qml
        music_player_desktop/components/ColorPickerPopup.qml
        music_player_desktop/components/FoliaLyrics.qml
        music_player_desktop/components/FoliaComposition.qml
        music_player_desktop/components/FoliaComposition.js
        music_player_desktop/components/FumeLyrics.qml
        music_player_desktop/components/ImmersiveSettingsPopup.qml
        music_player_desktop/components/ImmersiveSourcesPopup.qml
        music_player_desktop/components/ImmersiveStage.qml
        music_player_desktop/components/LyricsPanel.qml
        music_player_desktop/components/SettingsSwitch.qml
        music_player_desktop/components/SettingsCheckBox.qml
        music_player_desktop/components/SettingsSelect.qml
        music_player_desktop/components/SettingsRow.qml
        music_player_desktop/components/SettingsGroup.qml
        music_player_desktop/pages/LibraryPage.qml
        music_player_desktop/pages/AlbumMosaicPage.qml
        music_player_desktop/pages/MyListsPage.qml
        music_player_desktop/pages/CollectionPage.qml
        music_player_desktop/pages/SettingsPage.qml
        music_player_desktop/pages/NowPlayingPage.qml
        music_player_desktop/pages/MusicEditorDialog.qml
        music_player_desktop/pages/DiscoverPage.qml
        music_player_desktop/pages/PlaylistPage.qml
        music_player_desktop/pages/RadioPage.qml
        music_player_desktop/pages/SearchPage.qml
        music_player_desktop/models/MockCatalog.qml
        music_player_desktop/services/AppFacade.qml
    RESOURCES
        music_player_desktop/assets/background-pastel.svg
        music_player_desktop/assets/background-grain.svg
        music_player_desktop/assets/icons/app.svg
        music_player_desktop/assets/icons/app.png
        music_player_desktop/assets/icons/sidebar.svg
        music_player_desktop/assets/icons/playNext.svg
        music_player_desktop/assets/icons/heartFilled.svg
        music_player_desktop/assets/icons/chevronDown.svg
        music_player_desktop/assets/icons/chevronRight.svg
        music_player_desktop/assets/icons/chevronUp.svg
        music_player_desktop/assets/icons/close.svg
        music_player_desktop/assets/icons/comments.svg
        music_player_desktop/assets/icons/compass.svg
        music_player_desktop/assets/icons/download.svg
        music_player_desktop/assets/icons/expand.svg
        music_player_desktop/assets/icons/filter.svg
        music_player_desktop/assets/icons/folder.svg
        music_player_desktop/assets/icons/globe.svg
        music_player_desktop/assets/icons/heart.svg
        music_player_desktop/assets/icons/immersive.svg
        music_player_desktop/assets/icons/equalizer.svg
        music_player_desktop/assets/icons/adjustments.svg
        music_player_desktop/assets/icons/sourceSwap.svg
        music_player_desktop/assets/icons/lyrics.svg
        music_player_desktop/assets/icons/moon.svg
        music_player_desktop/assets/icons/more.svg
        music_player_desktop/assets/icons/music.svg
        music_player_desktop/assets/icons/navAlbums.svg
        music_player_desktop/assets/icons/navArtists.svg
        music_player_desktop/assets/icons/navDiscover.svg
        music_player_desktop/assets/icons/navPlaylists.svg
        music_player_desktop/assets/icons/navSongs.svg
        music_player_desktop/assets/icons/radio.svg
        music_player_desktop/assets/icons/next.svg
        music_player_desktop/assets/icons/pause.svg
        music_player_desktop/assets/icons/play.svg
        music_player_desktop/assets/icons/plus.svg
        music_player_desktop/assets/icons/previous.svg
        music_player_desktop/assets/icons/queue.svg
        music_player_desktop/assets/icons/repeat.svg
        music_player_desktop/assets/icons/infinity.svg
        music_player_desktop/assets/icons/repeatOne.svg
        music_player_desktop/assets/icons/search.svg
        music_player_desktop/assets/icons/sequential.svg
        music_player_desktop/assets/icons/settings.svg
        music_player_desktop/assets/icons/gear.svg
        music_player_desktop/assets/icons/info.svg
        music_player_desktop/assets/icons/stop.svg
        music_player_desktop/assets/icons/star.svg
        music_player_desktop/assets/icons/shuffle.svg
        music_player_desktop/assets/icons/sun.svg
        music_player_desktop/assets/icons/volume0.svg
        music_player_desktop/assets/icons/volume1.svg
        music_player_desktop/assets/icons/volume2.svg
        music_player_desktop/assets/album_Cover_1.png
        music_player_desktop/assets/album_Cover_2.png
        music_player_desktop/assets/album_Cover_2@2x.png
        music_player_desktop/assets/album_Cover_3.png
        music_player_desktop/assets/album_Cover_4.png
        music_player_desktop/assets/album_Cover_5.png
        music_player_desktop/assets/album_Cover_6.png
        music_player_desktop/assets/album_Cover_7.png
        music_player_desktop/assets/freeListen_wordmark.svg
        music_player_desktop/assets/freeListen_wordmark_dark.svg
)
qt_add_shaders(listenfree listenfree_background_shaders
    PREFIX "/shaders"
    BASE "music_player_desktop/shaders"
    FILES music_player_desktop/shaders/frosted-glass.frag
        music_player_desktop/shaders/window-transparency.frag
        music_player_desktop/shaders/artist-backdrop.frag
        music_player_desktop/shaders/artist-list-mask.frag
        music_player_desktop/shaders/mix-status.frag
        music_player_desktop/shaders/immersive-atmosphere.frag
    FILES music_player_desktop/shaders/artwork-gaussian.frag music_player_desktop/shaders/lyric-word.frag music_player_desktop/shaders/lyric-grapheme.frag music_player_desktop/shaders/artwork-mesh.vert music_player_desktop/shaders/artwork-tone.frag music_player_desktop/shaders/artwork-flow.frag music_player_desktop/shaders/artwork-palette.frag music_player_desktop/shaders/artwork-kawase.frag music_player_desktop/shaders/artwork-flow-tint.frag
)
# Shared native scene-graph shaders, including the real GPU render check.
foreach(_target listenfree listenfree_immersive_tests)
    if(TARGET ${_target})
        qt_add_shaders(${_target} ${_target}_diorama_shaders
            PREFIX "/shaders"
            BASE "music_player_desktop/shaders"
            GLSL "150,300es"
            FILES music_player_desktop/shaders/diorama-particles.vert
                  music_player_desktop/shaders/diorama-particles.frag)
    endif()
endforeach()
qt_add_shaders(listenfree listenfree_cover_shaders
    PREFIX "/shaders"
    BASE "music_player_desktop/shaders"
    GLSL "150,300es"
    FILES music_player_desktop/shaders/cover-rounded.frag
)
if(TARGET listenfree_resource_tests)
    qt_add_resources(listenfree_resource_tests resource_test_shaders PREFIX "/shaders"
        BASE "${CMAKE_CURRENT_BINARY_DIR}/.qsb"
        FILES "${CMAKE_CURRENT_BINARY_DIR}/.qsb/cover-rounded.frag.qsb")
endif()

target_link_libraries(listenfree PRIVATE ole32 uuid Qt6::Multimedia listenfree_qmlbridge Qt6::Gui Qt6::Quick Qt6::Qml Qt6::QuickDialogs2)
if(LISTENFREE_BUILD_QMMP_BACKEND)
    target_link_libraries(listenfree PRIVATE listenfree_portable TagLib::tag)
    target_compile_definitions(listenfree PRIVATE LISTENFREE_PORTABLE=1)
    get_filename_component(_qmmp_ui_binary_dir "${LISTENFREE_QMMP_UI_LIBRARY}" DIRECTORY)
    foreach(_target listenfree listenfree_portable_tests)
        if(TARGET ${_target})
            add_custom_command(TARGET ${_target} POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                    "${LISTENFREE_QMMP_RUNTIME}" "${_qmmp_ui_binary_dir}/libqmmpui.dll"
                    "$<TARGET_FILE_DIR:${_target}>")
        endif()
    endforeach()
endif()
listenfree_copy_mpv_runtime(listenfree)

if(LISTENFREE_BUILD_TESTS)
    enable_testing()
    add_executable(listenfree_shortcut_tests tests/shortcut_tests.cpp src/app/shortcut_service.cpp src/app/shortcut_service.h)
    target_link_libraries(listenfree_shortcut_tests PRIVATE listenfree_qmlbridge Qt6::Widgets Qt6::Test)
    target_include_directories(listenfree_shortcut_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    add_test(NAME listenfree_shortcut_tests COMMAND listenfree_shortcut_tests)
    add_executable(listenfree_tests tests/backend_tests.cpp)
    target_link_libraries(listenfree_tests PRIVATE listenfree_qmlbridge listenfree_source_protocol listenfree_source_client TagLib::tag Qt6::Test Qt6::Sql Qt6::Network)
    target_include_directories(listenfree_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    listenfree_copy_mpv_runtime(listenfree_tests)
    add_test(NAME listenfree_tests COMMAND listenfree_tests)
    add_executable(listenfree_playback_tests tests/playback_tests.cpp)
    target_link_libraries(listenfree_playback_tests PRIVATE listenfree_media listenfree_application Qt6::Test Qt6::Network Qt6::Multimedia)
    target_include_directories(listenfree_playback_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    listenfree_copy_mpv_runtime(listenfree_playback_tests)
    add_test(NAME listenfree_playback_tests COMMAND listenfree_playback_tests -o -,txt)
    set_tests_properties(listenfree_playback_tests PROPERTIES TIMEOUT 240)
    add_executable(listenfree_playback_service_tests tests/playback_service_tests.cpp)
    target_link_libraries(listenfree_playback_service_tests PRIVATE listenfree_qmlbridge Qt6::Test)
    target_include_directories(listenfree_playback_service_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    listenfree_copy_mpv_runtime(listenfree_playback_service_tests)
    add_test(NAME listenfree_playback_service_tests COMMAND listenfree_playback_service_tests)
    add_executable(listenfree-sourcehost-fault-host tests/sourcehost_fault_host.cpp)
    target_link_libraries(listenfree-sourcehost-fault-host PRIVATE listenfree_source_protocol Qt6::Core)
    target_include_directories(listenfree-sourcehost-fault-host PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    add_dependencies(listenfree_tests listenfree-sourcehost listenfree-sourcehost-fault-host)
    if(TARGET listenfree_portable_tests)
        add_dependencies(listenfree_portable_tests listenfree-sourcehost-fault-host)
    endif()
    add_executable(listenfree_sourcehost_fault_tests tests/sourcehost_fault_tests.cpp)
    target_link_libraries(listenfree_sourcehost_fault_tests PRIVATE listenfree_source_client listenfree_source_protocol Qt6::Test)
    target_include_directories(listenfree_sourcehost_fault_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    add_dependencies(listenfree_sourcehost_fault_tests listenfree-sourcehost-fault-host)
    add_test(NAME listenfree_sourcehost_fault_tests COMMAND listenfree_sourcehost_fault_tests)
    set_tests_properties(listenfree_sourcehost_fault_tests PROPERTIES TIMEOUT 60)
    add_test(NAME listenfree_smoke COMMAND listenfree --smoke -platform offscreen)
    set_tests_properties(listenfree_smoke PROPERTIES TIMEOUT 10)

    if(LISTENFREE_BUILD_MPV_BACKEND)
        add_executable(listenfree_mpv_backend_tests tests/mpv_backend_tests.cpp)
        target_link_libraries(listenfree_mpv_backend_tests PRIVATE listenfree_media Qt6::Test Qt6::Network)
        target_include_directories(listenfree_mpv_backend_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
        listenfree_copy_mpv_runtime(listenfree_mpv_backend_tests)
        add_test(NAME listenfree_mpv_backend_tests COMMAND listenfree_mpv_backend_tests)
        set_tests_properties(listenfree_mpv_backend_tests PROPERTIES TIMEOUT 30)
    endif()
endif()

if(MSVC)
    target_compile_options(listenfree_domain INTERFACE /W4 /permissive- /Zc:__cplusplus)
else()
    target_compile_options(listenfree_domain INTERFACE -Wall -Wextra -Wpedantic -Wconversion -Wshadow)
endif()

if(LISTENFREE_BUILD_TESTS)
    add_library(listenfree_pcm_output MODULE tests/pcm_output/outputnull.h tests/pcm_output/outputnull.cpp tests/pcm_output/outputnullfactory.h tests/pcm_output/outputnullfactory.cpp)
    target_link_libraries(listenfree_pcm_output PRIVATE listenfree_qmmp_import Qt6::Widgets)
endif()
