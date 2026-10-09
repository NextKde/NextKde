# ListenFree is the installed music application; legacy source stays in the repository.
set(_listenfree_install_dir opt/listenfree)
set_target_properties(listenfree listenfree-sourcehost PROPERTIES INSTALL_RPATH "$ORIGIN/lib")
install(TARGETS listenfree listenfree-sourcehost RUNTIME DESTINATION ${_listenfree_install_dir})
get_filename_component(_listenfree_library_dir "${LISTENFREE_QMMP_LIBRARY}" DIRECTORY)
file(GLOB _listenfree_private_libraries
    "${_listenfree_library_dir}/libqmmp.so*" "${_listenfree_library_dir}/libqmmpui.so*"
    "${_listenfree_library_dir}/libtag.so*" "${_listenfree_library_dir}/libopusfile.so*")
install(FILES ${_listenfree_private_libraries} DESTINATION ${_listenfree_install_dir}/lib)
install(DIRECTORY "${LISTENFREE_QMMP_PLUGIN_ROOT}/" DESTINATION ${_listenfree_install_dir}/qmmp)
install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/licenses/" DESTINATION ${_listenfree_install_dir}/licenses)
foreach(_license
    "${LISTENFREE_QMMP_SOURCE_ROOT}/COPYING"
    "${KOS_LISTENFREE_SDK}/vendor/taglib-2.3.1/COPYING.LGPL"
    "${KOS_LISTENFREE_SDK}/vendor/quickjs-0.16.2/LICENSE")
    if(EXISTS "${_license}")
        get_filename_component(_license_dir "${_license}" DIRECTORY)
        get_filename_component(_license_name "${_license_dir}" NAME)
        install(FILES "${_license}" DESTINATION ${_listenfree_install_dir}/licenses RENAME "${_license_name}-LICENSE.txt")
    endif()
endforeach()
configure_file(packaging/linux/listenfree.in "${CMAKE_CURRENT_BINARY_DIR}/listenfree-launcher" @ONLY)
configure_file(packaging/linux/listenfree.desktop.in "${CMAKE_CURRENT_BINARY_DIR}/listenfree.desktop" @ONLY)
install(PROGRAMS "${CMAKE_CURRENT_BINARY_DIR}/listenfree-launcher" DESTINATION bin RENAME listenfree)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/listenfree.desktop" DESTINATION share/applications)
install(FILES music_player_desktop/assets/icons/nextkde-music.svg
    DESTINATION share/icons/hicolor/scalable/apps RENAME listenfree.svg)

install(FILES "${KOS_LISTENFREE_SDK}/deps/usr/share/doc/libopusfile0/copyright"
    DESTINATION ${_listenfree_install_dir}/licenses RENAME Opusfile-copyright.txt OPTIONAL)
