{
  lib,
  stdenv,
  cmake,
  kdePackages,
  src,
}:

stdenv.mkDerivation {
  pname = "kwin-stage-animation";
  version = "unstable";
  src = "${src}/kwin/kwin-effects-stageanim";

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
    description = "Stage sidebar window animation for KWin";
    homepage = "https://gitee.com/xiaoyintx_ciallo/test";
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
  };
}
