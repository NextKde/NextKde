{
  lib,
  stdenv,
  cmake,
  kdePackages,
  src,
}:

stdenv.mkDerivation {
  pname = "kwin-dock-window-animation";
  version = lib.removeSuffix "\n" (builtins.readFile "${src}/VERSION");
  # Keep the sibling kos-bridge sources used by this plugin available.
  inherit src;
  sourceRoot = "source/kwin/dock-window-animation";

  nativeBuildInputs = [
    cmake
    kdePackages.extra-cmake-modules
  ];

  buildInputs = [
    kdePackages.kwin
    kdePackages.kconfig
    kdePackages.qtbase
  ];

  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];
  dontWrapQtApps = true;

  meta = with lib; {
    description = "iPadOS-style scale/genie window animation for KWin";
    homepage = "https://gitee.com/xiaoyintx_ciallo/test";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
