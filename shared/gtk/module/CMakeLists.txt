cmake_minimum_required(VERSION 3.21)
project(kos-gtk-window-controls LANGUAGES C)
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK3 REQUIRED IMPORTED_TARGET gtk+-3.0)
pkg_check_modules(WAYLAND_CLIENT REQUIRED IMPORTED_TARGET wayland-client)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)
set(protocol ${CMAKE_CURRENT_SOURCE_DIR}/../../../shell/native/surface-shape/kos-window-controls-v1.xml)
add_custom_command(OUTPUT controls-client.h controls-protocol.c
    COMMAND ${WAYLAND_SCANNER} client-header ${protocol} controls-client.h
    COMMAND ${WAYLAND_SCANNER} private-code ${protocol} controls-protocol.c
    DEPENDS ${protocol})
add_library(kos-gtk-window-controls MODULE module.c controls-protocol.c controls-client.h)
set_target_properties(kos-gtk-window-controls PROPERTIES AUTOMOC OFF)
target_include_directories(kos-gtk-window-controls PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(kos-gtk-window-controls PRIVATE PkgConfig::GTK3 PkgConfig::WAYLAND_CLIENT)
install(TARGETS kos-gtk-window-controls LIBRARY DESTINATION lib/gtk-3.0/modules)
