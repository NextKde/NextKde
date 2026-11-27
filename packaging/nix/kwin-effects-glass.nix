{
  lib,
  stdenv,
  cmake,
  kdePackages,
  wayland-scanner,
  src,
}:

stdenv.mkDerivation {
  pname = "kwin-glass";
  version = lib.removeSuffix "\n" (builtins.readFile "${src}/VERSION");
  # Keep the sibling kwin/common headers used by glass.cpp available.
  inherit src;
  sourceRoot = "source/kwin/glass";

  nativeBuildInputs = [
    cmake
    kdePackages.extra-cmake-modules
    wayland-scanner
  ];

  buildInputs = [
    kdePackages.kwin
    kdePackages.qttools
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DKOS_SURFACE_SHAPE_PROTOCOL=${src}/shell/native/surface-shape/kos-surface-shape-v1.xml"
  ];
  dontWrapQtApps = true;

  meta = with lib; {
    description = "KOS KWin glass effect (liquid/soft materials over kos_surface_shape_v1)";
    homepage = "https://gitee.com/xiaoyintx_ciallo/test";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
