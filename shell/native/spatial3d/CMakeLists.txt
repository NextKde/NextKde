cmake_minimum_required(VERSION 3.21)
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    project(KosSpatial3D LANGUAGES CXX)
    set(CMAKE_CXX_STANDARD 20)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    set(CMAKE_AUTOMOC ON)
endif()
include(GNUInstallDirs)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Qml Quick3D)
find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs)

add_library(kos_spatial3d MODULE
    depthmeshgeometry.cpp
    depthmeshgeometry.h
    spatial3dplugin.cpp
)
target_include_directories(kos_spatial3d PRIVATE ${OpenCV_INCLUDE_DIRS})
target_link_libraries(kos_spatial3d PRIVATE
    Qt6::Core Qt6::Qml Qt6::Quick3D ${OpenCV_LIBS})
set_target_properties(kos_spatial3d PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml/Kos/Spatial3D")

configure_file(qmldir "${CMAKE_BINARY_DIR}/qml/Kos/Spatial3D/qmldir" COPYONLY)

install(TARGETS kos_spatial3d LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/Kos/Spatial3D)
install(FILES qmldir DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml/Kos/Spatial3D)
