{
  lib,
  stdenv,
  cmake,
  kdePackages,
  src,
}:

let
  go-service = kdePackages.callPackage ./shell-data-service.nix { inherit src; };
in
stdenv.mkDerivation {
  pname = "kos-weather";
  version = "unstable";
  inherit src;

  nativeBuildInputs = [
    cmake
    kdePackages.extra-cmake-modules
    kdePackages.wrapQtAppsHook
  ];

  buildInputs = [
    kdePackages.qtbase
    kdePackages.qtdeclarative
  ];

  # Patch out the Go data-service build from CMake.
  # The real data service is built separately via buildGoModule (shell-data-service.nix).
  postPatch = ''
    # Root CMakeLists.txt: skip data-service subdirectory
    substituteInPlace CMakeLists.txt \
      --replace-fail 'add_subdirectory(services/data-service)' '# skipped: data-service built separately'

    # apps/weather/CMakeLists.txt: remove dependency on data-service build target
    substituteInPlace apps/weather/CMakeLists.txt \
      --replace-fail 'add_dependencies(kos-weather kos-data-service-build)' '# skipped: data-service built separately'
    substituteInPlace apps/weather/CMakeLists.txt \
      --replace-fail 'target_compile_definitions(kos-weather PRIVATE' 'target_compile_definitions(kos-weather PRIVATE'
  '';

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DKOS_BUILD_PLATFORM=OFF"
    "-DKOS_BUILD_KWIN_PLUGINS=OFF"
    "-DKOS_BUILD_CALENDAR=OFF"
    "-DKOS_BUILD_TODO=OFF"
    "-DKOS_BUILD_WEATHER=ON"
    "-DKOS_BUILD_MUSIC=OFF"
    "-DBUILD_TESTING=OFF"
  ];

  # Install the pre-built data service alongside the weather binary
  postInstall = ''
    mkdir -p $out/libexec
    ln -s ${go-service}/libexec/kos-data-service $out/libexec/kos-data-service
  '';

  meta = with lib; {
    description = "KOS Weather - standalone Qt Quick forecast application";
    homepage = "https://gitee.com/xiaoyintx_ciallo/test";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
