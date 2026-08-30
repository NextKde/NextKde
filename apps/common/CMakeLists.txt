add_library(kos_app_core STATIC
    src/ApplicationRunner.cpp
)

add_library(Kos::AppCore ALIAS kos_app_core)

target_include_directories(kos_app_core
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>
)

target_link_libraries(kos_app_core PUBLIC
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
)

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(kos_app_core PRIVATE
        -Wall
        -Wextra
        -Wpedantic
    )
endif()
