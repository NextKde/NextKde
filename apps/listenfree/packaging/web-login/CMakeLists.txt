# Also supports building/installing only the login component, without the audio SDK.
cmake_minimum_required(VERSION 3.28)
project(ListenFreeWebLogin LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 6.10 REQUIRED COMPONENTS Core Gui Widgets Network WebEngineWidgets)
find_package(OpenSSL REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(SECRET REQUIRED IMPORTED_TARGET libsecret-1)
set(app_root "${CMAKE_CURRENT_LIST_DIR}/../..")
add_executable(listenfree-web-login
    ${app_root}/src/app/web_login_main.cpp
    ${app_root}/src/app/web_login_dialog.cpp ${app_root}/src/app/web_login_dialog.h
    ${app_root}/src/qmlbridge/account_service.cpp ${app_root}/src/qmlbridge/account_service.h)
target_include_directories(listenfree-web-login PRIVATE ${app_root}/src ${app_root}/../../shared/i18n)
target_link_libraries(listenfree-web-login PRIVATE Qt6::WebEngineWidgets Qt6::Network OpenSSL::Crypto PkgConfig::SECRET)
# Default player installation never installs this optional component.
option(LISTENFREE_STRIP_INSTALL "Strip Release installations" ON)
if(LISTENFREE_STRIP_INSTALL)
    install(CODE "if(\"\${CMAKE_INSTALL_CONFIG_NAME}\" STREQUAL \"Release\")
    set(CMAKE_INSTALL_DO_STRIP TRUE)
endif()"
        COMPONENT listenfree-web-login EXCLUDE_FROM_ALL)
endif()
install(TARGETS listenfree-web-login RUNTIME DESTINATION opt/listenfree
    COMPONENT listenfree-web-login EXCLUDE_FROM_ALL)

qt_add_resources(listenfree-web-login login_translations
    PREFIX "/translations" BASE "${app_root}/music_player_desktop/translations"
    FILES "${app_root}/music_player_desktop/translations/en_US.json")
if(LISTENFREE_BUILD_TOOLS)
    add_executable(listenfree-account-browser-probe
        ${app_root}/tools/account_browser_probe.cpp
        ${app_root}/src/app/web_login_dialog.cpp ${app_root}/src/app/web_login_dialog.h
        ${app_root}/src/qmlbridge/account_service.cpp ${app_root}/src/qmlbridge/account_service.h)
    target_include_directories(listenfree-account-browser-probe PRIVATE ${app_root}/src)
    target_link_libraries(listenfree-account-browser-probe PRIVATE Qt6::WebEngineWidgets Qt6::Network OpenSSL::Crypto PkgConfig::SECRET)
endif()

# Extracted Debian/Ubuntu development prefixes keep opensslconf.h separately.
if(EXISTS "${OPENSSL_INCLUDE_DIR}/${CMAKE_LIBRARY_ARCHITECTURE}/openssl/opensslconf.h")
    foreach(target listenfree-web-login listenfree-account-browser-probe)
        if(TARGET ${target})
            target_include_directories(${target} PRIVATE "${OPENSSL_INCLUDE_DIR}/${CMAKE_LIBRARY_ARCHITECTURE}")
        endif()
    endforeach()
endif()
