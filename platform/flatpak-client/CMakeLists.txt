add_library(kos-flatpak-client STATIC
    FlatpakAppsClient.cpp
    FlatpakAppsClient.h
)
target_include_directories(kos-flatpak-client PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(kos-flatpak-client PUBLIC Qt6::Core)
