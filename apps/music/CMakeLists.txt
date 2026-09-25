find_package(Qt6 6.5 REQUIRED COMPONENTS Concurrent DBus Network Qml QuickDialogs2 Sql)
find_package(PkgConfig REQUIRED)
# The root project may already have resolved these (it does when it adds this
# directory purely to reach the tests below). Reuse that result when present so
# the version constraint is stated once and the two lookups cannot drift.
if(NOT TARGET PkgConfig::KOS_MUSIC_GSTREAMER)
    pkg_check_modules(KOS_MUSIC_GSTREAMER QUIET IMPORTED_TARGET
        gstreamer-1.0
        gstreamer-audio-1.0
        gstreamer-pbutils-1.0
    )
endif()
if(NOT TARGET PkgConfig::KOS_MUSIC_TAGLIB)
    pkg_check_modules(KOS_MUSIC_TAGLIB QUIET IMPORTED_TARGET taglib>=1.12)
endif()
if(NOT (TARGET PkgConfig::KOS_MUSIC_GSTREAMER AND TARGET PkgConfig::KOS_MUSIC_TAGLIB))
    message(FATAL_ERROR
        "KOS Music needs gstreamer-1.0 (audio, pbutils) and taglib>=1.12")
endif()

set(KOS_MUSIC_CORE_SOURCES
    src/AudioCache.cpp
    src/AudioCache.h
    src/MetadataScanner.cpp
    src/MetadataScanner.h
    src/MusicDatabase.cpp
    src/MusicDatabase.h
    src/MusicTypes.h
    src/MprisService.cpp
    src/MprisService.h
    src/PlaybackEngine.cpp
    src/PlaybackEngine.h
    src/Transcoder.cpp
    src/Transcoder.h
)

# KOS_MUSIC_TESTS_ONLY is set by the root project when it descends here only to
# build the test targets below. kos-music is a full QML application that links
# Kos::Ui, which is itself gated behind the app flags, so building it from a
# test-only descent would fail. Skipping it keeps the tests independent of the
# application's own dependencies.
if(NOT KOS_MUSIC_TESTS_ONLY)
qt_add_executable(kos-music-lx-source-host
    src/LxSourceHostMain.cpp
)
configure_file(src/LxSourceHost.js kos-music-lx-source-host.js COPYONLY)
target_link_libraries(kos-music-lx-source-host PRIVATE
    Qt6::Core
    Qt6::Network
    Qt6::Qml
)
install(TARGETS kos-music-lx-source-host
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
install(PROGRAMS src/LxSourceHost.js
    DESTINATION ${CMAKE_INSTALL_BINDIR}
    RENAME kos-music-lx-source-host.js
)

kos_add_application(kos-music
    URI Kos.Apps.Music
    DISPLAY_NAME "KOS Music"
    DESKTOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-music.desktop.in
    ICON_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-music.svg
    METAINFO_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/org.nextkde.Kos.Music.metainfo.xml
    SOURCES
        src/main.cpp
        src/LxSourceService.cpp
        src/LxSourceService.h
        src/LyricsService.cpp
        src/LyricsService.h
        src/OnlineMusicProvider.cpp
        src/OnlineMusicProvider.h
        ${KOS_MUSIC_CORE_SOURCES}
    QML_SOURCES
        src/MusicController.cpp
        src/MusicController.h
        src/TrackListModel.cpp
        src/TrackListModel.h
    QML_FILES
        qml/Artwork.qml
        qml/Main.qml
        qml/MiniPlayer.qml
        qml/MusicGroupGrid.qml
        qml/MusicSourcePage.qml
        qml/NowPlayingPage.qml
        qml/OnlineSearchPage.qml
        qml/TrackListView.qml
    LINK_LIBRARIES
        Qt6::Concurrent
        Qt6::DBus
        Qt6::Network
        Qt6::QuickDialogs2
        Qt6::Sql
        PkgConfig::KOS_MUSIC_GSTREAMER
        PkgConfig::KOS_MUSIC_TAGLIB
)

target_include_directories(kos-music PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
)
endif()

if(BUILD_TESTING)
    qt_add_executable(kos-music-cache-test
        tests/AudioCacheTest.cpp
        src/AudioCache.cpp
        src/AudioCache.h
    )
    target_include_directories(kos-music-cache-test PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    target_link_libraries(kos-music-cache-test PRIVATE Qt6::Core Qt6::Network Qt6::Test)
    add_test(NAME kos-music.cache COMMAND kos-music-cache-test)
    set_tests_properties(kos-music.cache PROPERTIES TIMEOUT 20 LABELS data)

    qt_add_executable(kos-music-core-test
        tests/MusicCoreTest.cpp
        src/LyricsService.cpp
        src/LyricsService.h
        src/OnlineMusicProvider.cpp
        src/OnlineMusicProvider.h
        src/MetadataScanner.cpp
        src/MetadataScanner.h
        src/MusicDatabase.cpp
        src/MusicDatabase.h
        src/MusicTypes.h
        src/TrackListModel.cpp
        src/TrackListModel.h
    )
    target_include_directories(kos-music-core-test PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    target_link_libraries(kos-music-core-test PRIVATE
        Qt6::Core
        Qt6::Qml
        Qt6::Network
        Qt6::Sql
        Qt6::Test
        PkgConfig::KOS_MUSIC_TAGLIB
    )
    add_test(NAME kos-music.core COMMAND kos-music-core-test)
    set_tests_properties(kos-music.core PROPERTIES TIMEOUT 20 LABELS data)

    if(TARGET kos-music-lx-source-host)
        qt_add_executable(kos-music-source-host-test
            tests/LxSourceHostTest.cpp
        )
        target_link_libraries(kos-music-source-host-test PRIVATE
            Qt6::Core
            Qt6::Network
            Qt6::Test
        )
        add_test(NAME kos-music.source-host
            COMMAND ${CMAKE_COMMAND} -E env
                KOS_MUSIC_SOURCE_HOST_TEST=$<TARGET_FILE:kos-music-lx-source-host>
                $<TARGET_FILE:kos-music-source-host-test>
        )
        set_tests_properties(kos-music.source-host PROPERTIES
            TIMEOUT 15
            LABELS data
        )

        qt_add_executable(kos-music-source-service-test
            tests/LxSourceServiceTest.cpp
            src/LxSourceService.cpp
            src/LxSourceService.h
            src/MusicTypes.h
        )
        target_include_directories(kos-music-source-service-test PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/src
        )
        target_link_libraries(kos-music-source-service-test PRIVATE
            Qt6::Core
            Qt6::Network
            Qt6::Test
        )
        add_test(NAME kos-music.source-service
            COMMAND ${CMAKE_COMMAND} -E env
                KOS_MUSIC_SOURCE_HOST=$<TARGET_FILE:kos-music-lx-source-host>
                $<TARGET_FILE:kos-music-source-service-test>
        )
        set_tests_properties(kos-music.source-service PROPERTIES
            TIMEOUT 20
            LABELS data
        )
    endif()

    qt_add_executable(kos-music-engine-test
        tests/MusicEngineTest.cpp
        src/MetadataScanner.cpp
        src/MetadataScanner.h
        src/MusicTypes.h
        src/PlaybackEngine.cpp
        src/PlaybackEngine.h
        src/Transcoder.cpp
        src/Transcoder.h
    )
    target_include_directories(kos-music-engine-test PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    target_link_libraries(kos-music-engine-test PRIVATE
        Qt6::Core
        Qt6::Test
        PkgConfig::KOS_MUSIC_GSTREAMER
        PkgConfig::KOS_MUSIC_TAGLIB
        Qt6::Network
    )
    add_test(NAME kos-music.engine COMMAND kos-music-engine-test)
    set_tests_properties(kos-music.engine PROPERTIES
        ENVIRONMENT "G_DEBUG=fatal-criticals;KOS_MUSIC_FAKE_AUDIO=1"
        TIMEOUT 30
        LABELS data
    )

    if(TARGET kos-music-lx-source-host)
        qt_add_executable(kos-music-live-source-check
            tests/MusicLiveSourceCheck.cpp
            src/LxSourceService.cpp
            src/LxSourceService.h
            src/LyricsService.cpp
            src/LyricsService.h
            src/OnlineMusicProvider.cpp
            src/OnlineMusicProvider.h
            src/PlaybackEngine.cpp
            src/PlaybackEngine.h
            src/MusicTypes.h
        )
        target_include_directories(kos-music-live-source-check PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/src
        )
        target_link_libraries(kos-music-live-source-check PRIVATE
            Qt6::Core
            Qt6::Network
            PkgConfig::KOS_MUSIC_GSTREAMER
        )
    endif()

    find_program(DBUS_RUN_SESSION_EXECUTABLE dbus-run-session)
    if(DBUS_RUN_SESSION_EXECUTABLE)
        qt_add_executable(kos-music-mpris-test
            tests/MusicMprisTest.cpp
            ${KOS_MUSIC_CORE_SOURCES}
            src/LxSourceService.cpp
            src/LxSourceService.h
            src/LyricsService.cpp
            src/LyricsService.h
            src/OnlineMusicProvider.cpp
            src/OnlineMusicProvider.h
            src/MusicController.cpp
            src/MusicController.h
            src/TrackListModel.cpp
            src/TrackListModel.h
        )
        target_include_directories(kos-music-mpris-test PRIVATE
            ${CMAKE_CURRENT_SOURCE_DIR}/src
        )
        target_link_libraries(kos-music-mpris-test PRIVATE
            Qt6::Concurrent
            Qt6::Core
            Qt6::DBus
            Qt6::Network
            Qt6::Qml
            Qt6::Sql
            Qt6::Test
            PkgConfig::KOS_MUSIC_GSTREAMER
            PkgConfig::KOS_MUSIC_TAGLIB
        )
        add_test(NAME kos-music.mpris
            COMMAND ${DBUS_RUN_SESSION_EXECUTABLE}
                --config-file=${CMAKE_CURRENT_SOURCE_DIR}/tests/session-bus.conf
                -- $<TARGET_FILE:kos-music-mpris-test>
        )
        set_tests_properties(kos-music.mpris PROPERTIES
            ENVIRONMENT "G_DEBUG=fatal-criticals;KOS_MUSIC_FAKE_AUDIO=1"
            TIMEOUT 90
            LABELS data
        )
    endif()
endif()
