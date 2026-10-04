{ lib, stdenv, cmake, kdePackages, opencv, src }:
stdenv.mkDerivation {
  pname = "kos-spatial3d";
  version = "unstable";
  src = "${src}/qml-plugins/spatial3d";
  nativeBuildInputs = [ cmake ];
  buildInputs = [ kdePackages.qtbase kdePackages.qtdeclarative kdePackages.qtquick3d opencv ];
  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" "-DCMAKE_INSTALL_LIBDIR=lib" ];
  dontWrapQtApps = true;
  meta = {
    description = "Depth mesh renderer for KOS spatial wallpapers";
    license = lib.licenses.gpl3;
    platforms = lib.platforms.linux;
  };
}
