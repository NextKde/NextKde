find_package(Qt6 6.5 REQUIRED COMPONENTS Concurrent DBus QuickDialogs2 Sql)
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
kos_add_application(kos-music
    URI Kos.Apps.Music
    DISPLAY_NAME "KOS Music"
    DESKTOP_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-music.desktop.in
    ICON_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/kos-music.svg
    METAINFO_FILE ${CMAKE_CURRENT_SOURCE_DIR}/data/org.nextkde.Kos.Music.metainfo.xml
    SOURCES
        src/main.cpp
        ${KOS_MUSIC_CORE_SOURCES}
    QML_SOURCES
        src/MusicController.cpp
        src/MusicController.h
        src/TrackListModel.cpp
        src/TrackListModel.h
    QML_FILES
        qml/Artwork.qml
        qml/Main.qml
        qml/MusicGroupGrid.qml
        qml/TrackListView.qml
    LINK_LIBRARIES
        Qt6::Concurrent
        Qt6::DBus
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
    qt_add_executable(kos-music-core-test
        tests/MusicCoreTest.cpp
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
        Qt6::Sql
        Qt6::Test
        PkgConfig::KOS_MUSIC_TAGLIB
    )
    add_test(NAME kos-music.core COMMAND kos-music-core-test)
    set_tests_properties(kos-music.core PROPERTIES TIMEOUT 20 LABELS data)

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
    )
    add_test(NAME kos-music.engine COMMAND kos-music-engine-test)
    set_tests_properties(kos-music.engine PROPERTIES
        ENVIRONMENT "G_DEBUG=fatal-criticals;KOS_MUSIC_FAKE_AUDIO=1"
        TIMEOUT 30
        LABELS data
    )

    find_program(DBUS_RUN_SESSION_EXECUTABLE dbus-run-session)
    if(DBUS_RUN_SESSION_EXECUTABLE)
        qt_add_executable(kos-music-mpris-test
            tests/MusicMprisTest.cpp
            ${KOS_MUSIC_CORE_SOURCES}
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
            Qt6::Qml
            Qt6::Sql
            Qt6::Test
            PkgConfig::KOS_MUSIC_GSTREAMER
            PkgConfig::KOS_MUSIC_TAGLIB
        )
        add_test(NAME kos-music.mpris
            COMMAND ${DBUS_RUN_SESSION_EXECUTABLE} -- $<TARGET_FILE:kos-music-mpris-test>
        )
        set_tests_properties(kos-music.mpris PROPERTIES
            ENVIRONMENT "G_DEBUG=fatal-criticals;KOS_MUSIC_FAKE_AUDIO=1"
            TIMEOUT 30
            LABELS data
        )
    endif()
endif()
