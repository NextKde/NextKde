{ lib, stdenv, cmake, ninja, pkg-config, python3, kdePackages, sdl3, freetype, libGL, wayland, src }:
let
  forma = builtins.fetchGit {
    url = "https://github.com/skjsbsnq/Forma.git";
    rev = "5bdb550a3d42535ea026ee04070bc0dd97774ef3";
  };
in stdenv.mkDerivation {
  pname = "kos-forma-network";
  version = "unstable";
  src = "${src}/shell/native/forma-network";
  nativeBuildInputs = [ cmake ninja pkg-config python3 kdePackages.qtshadertools ];
  buildInputs = [ kdePackages.qtbase kdePackages.qtdeclarative kdePackages.qtshadertools sdl3 freetype libGL wayland ];
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DKOS_FORMA_SOURCE_DIR=${forma}"
  ];
  dontWrapQtApps = true;
  meta = {
    description = "Original Forma C++ network components embedded in Qt Quick";
    license = lib.licenses.gpl3;
    platforms = lib.platforms.linux;
  };
}
