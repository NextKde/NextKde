{
  lib,
  stdenv,
  cmake,
  kdePackages,
  src,
}:

stdenv.mkDerivation {
  pname = "kwin-kos-decoration";
  version = lib.removeSuffix "\n" (builtins.readFile "${src}/VERSION");
  # Keep the sibling kos-bridge sources used by this plugin available.
  inherit src;
  sourceRoot = "source/kwin/kos-decoration";

  nativeBuildInputs = [
    cmake
    kdePackages.extra-cmake-modules
  ];

  buildInputs = [
    kdePackages.kdecoration
    kdePackages.kcoreaddons
    kdePackages.qtbase
  ];

  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];
  dontWrapQtApps = true;

  meta = with lib; {
    description = "KOS window decoration for KWin - draws the title bar and no buttons";
    homepage = "https://gitee.com/xiaoyintx_ciallo/test";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
