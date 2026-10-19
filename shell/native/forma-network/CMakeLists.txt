cmake_minimum_required(VERSION 3.21)
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    project(KosFormaNetwork LANGUAGES C CXX)
    set(CMAKE_CXX_STANDARD 20)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    set(CMAKE_AUTOMOC ON)
endif()
include(GNUInstallDirs)
find_package(Qt6 6.7 REQUIRED COMPONENTS Core Gui GuiPrivate Qml Quick ShaderTools)
find_package(Python3 REQUIRED COMPONENTS Interpreter)

# Build the real Forma library. A developer checkout can replace the pinned
# dependency, without copying controls or depending on another tree's binaries.
set(KOS_FORMA_SOURCE_DIR "" CACHE PATH "Existing Forma source checkout")
if(NOT KOS_FORMA_SOURCE_DIR AND EXISTS "$ENV{HOME}/Projects/Forma/include/mayonnaise/widget.hpp")
    set(KOS_FORMA_SOURCE_DIR "$ENV{HOME}/Projects/Forma")
endif()
set(MAYONNAISE_BUILD_APPS OFF CACHE BOOL "" FORCE)
set(MAYONNAISE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(MAYONNAISE_USE_SYSTEM_DEPS ON CACHE BOOL "" FORCE)
# Qt owns the Vulkan/OpenGL device; Forma's SDL backends are not used.
set(MAYONNAISE_VULKAN OFF CACHE BOOL "" FORCE)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# The QML plugin must carry its native controls when deployed independently;
# do not inherit NextKde/KDE's BUILD_SHARED_LIBS preference for this dependency.
set(BUILD_SHARED_LIBS OFF)
include(FetchContent)
if(KOS_FORMA_SOURCE_DIR)
    FetchContent_Declare(forma SOURCE_DIR "${KOS_FORMA_SOURCE_DIR}")
else()
    FetchContent_Declare(forma
        GIT_REPOSITORY https://github.com/skjsbsnq/Forma.git
        GIT_TAG 5bdb550a3d42535ea026ee04070bc0dd97774ef3)
endif()
FetchContent_MakeAvailable(forma)
set(generated "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${generated}")
execute_process(COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/prepare.py"
    "${forma_SOURCE_DIR}" "${generated}" COMMAND_ERROR_IS_FATAL ANY)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    prepare.py "${forma_SOURCE_DIR}/src/render/renderer2d.cpp"
    "${forma_SOURCE_DIR}/src/render/renderer2d.hpp"
    "${forma_SOURCE_DIR}/shaders/ui.vert" "${forma_SOURCE_DIR}/shaders/ui.frag"
    "${forma_SOURCE_DIR}/shaders/fullscreen.vert" "${forma_SOURCE_DIR}/shaders/blur_down.frag"
    "${forma_SOURCE_DIR}/shaders/blur_up.frag")

add_library(kos_forma_network_core STATIC
    networkview.cpp networkview.h networkscene.cpp networkscene.h
    qrhidevice.cpp qrhidevice.h "${generated}/renderer2d.cpp")
target_include_directories(kos_forma_network_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}"
    PRIVATE "${generated}" "${forma_SOURCE_DIR}/src" "${forma_SOURCE_DIR}/src/render")
target_link_libraries(kos_forma_network_core PUBLIC Qt6::Quick Qt6::GuiPrivate mayonnaise::mayonnaise)
qt_add_shaders(kos_forma_network_core forma_network_shaders
    PREFIX /kos/forma BASE "${generated}"
    FILES "${generated}/ui.vert" "${generated}/ui.frag"
          "${generated}/fullscreen.vert" "${generated}/blur_down.frag" "${generated}/blur_up.frag")

add_library(kos_forma_network MODULE plugin.cpp)
target_link_libraries(kos_forma_network PRIVATE kos_forma_network_core)
set_target_properties(kos_forma_network PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml/Kos/FormaNetwork")
configure_file(qmldir "${CMAKE_BINARY_DIR}/qml/Kos/FormaNetwork/qmldir" COPYONLY)
install(TARGETS kos_forma_network DESTINATION "${CMAKE_INSTALL_LIBDIR}/qt6/qml/Kos/FormaNetwork" COMPONENT kwin_plugins)
install(FILES qmldir DESTINATION "${CMAKE_INSTALL_LIBDIR}/qt6/qml/Kos/FormaNetwork" COMPONENT kwin_plugins)
install(FILES "${forma_SOURCE_DIR}/LICENSE.txt" "${forma_SOURCE_DIR}/assets/fonts/Inter-LICENSE.txt" Stats-LICENSE
    DESTINATION "${CMAKE_INSTALL_DATADIR}/licenses/kos-forma-network" COMPONENT kwin_plugins)

add_executable(kos-forma-network-check check.cpp)
target_link_libraries(kos-forma-network-check PRIVATE kos_forma_network_core)
