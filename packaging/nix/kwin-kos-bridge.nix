{
  lib,
  stdenv,
  cmake,
  kdePackages,
  src,
}:

stdenv.mkDerivation {
  pname = "kwin-kos-bridge";
  version = "unstable";
  src = "${src}/kwin/kos-bridge";

  nativeBuildInputs = [
    cmake
    kdePackages.extra-cmake-modules
  ];

  buildInputs = [
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
