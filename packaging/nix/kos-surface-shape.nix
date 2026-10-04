{ lib, stdenv, cmake, pkg-config, kdePackages, wayland, wayland-scanner, src }:
stdenv.mkDerivation {
  pname = "kos-surface-shape";
  version = "unstable";
  src = "${src}/qml-plugins/surface-shape";
  nativeBuildInputs = [ cmake pkg-config kdePackages.extra-cmake-modules wayland-scanner ];
  buildInputs = [ kdePackages.qtbase kdePackages.qtdeclarative kdePackages.qtwayland wayland ];
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DKOS_SURFACE_PROTOCOL_FILE=${src}/qml-plugins/surface-shape/kos-surface-shape-v1.xml"
  ];
  dontWrapQtApps = true;
  meta = {
    description = "Wayland surface shape QML extension for the KOS shell";
    license = lib.licenses.gpl3;
    platforms = lib.platforms.linux;
  };
}
