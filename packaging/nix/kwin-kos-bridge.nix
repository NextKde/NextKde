{
  lib,
  stdenv,
  cmake,
  pkg-config,
  wayland,
  libxcb,
  wayland-scanner,
  kdePackages,
  src,
}:

stdenv.mkDerivation {
  pname = "kwin-kos-bridge";
  version = lib.removeSuffix "\n" (builtins.readFile "${src}/VERSION");
  # Keep the shared Wayland protocol under shell/native available.
  inherit src;
  sourceRoot = "source/kwin/kos-bridge";

  nativeBuildInputs = [
    cmake
    pkg-config
    wayland-scanner
    kdePackages.extra-cmake-modules
  ];

  buildInputs = [
    wayland
    libxcb
    kdePackages.kwin
    kdePackages.qtbase
    kdePackages.qttools
  ];

  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];
  dontWrapQtApps = true;

  meta = with lib; {
    description = "KOS Bridge KWin effect - draws window buttons on CSD windows";
    homepage = "https://gitee.com/xiaoyintx_ciallo/test";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
