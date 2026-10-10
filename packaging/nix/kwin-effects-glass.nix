{
  lib,
  stdenv,
  cmake,
  kdePackages,
  src,
}:

stdenv.mkDerivation {
  pname = "kwin-glass";
  version = "unstable";
  src = "${src}/kwin/glass-effect";

  nativeBuildInputs = [
    cmake
    kdePackages.extra-cmake-modules
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
    description = "Fork of the KWin Blur effect for KDE Plasma 6 with glass/refraction features";
    homepage = "https://gitee.com/xiaoyintx_ciallo/test";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
