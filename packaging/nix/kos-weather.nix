{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  go,
  kdePackages,
  # Fixed-output source of NextKde/kos-apps, never the core desktop tree.
  src,
  version ? "0.2.0",
}:

stdenv.mkDerivation {
  pname = "kos-weather";
  inherit src version;

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    go
    kdePackages.extra-cmake-modules
    kdePackages.qttools
    kdePackages.wrapQtAppsHook
  ];

  buildInputs = [
    kdePackages.qtbase
    kdePackages.qtdeclarative
    kdePackages.qtsvg
    kdePackages.kwindowsystem
  ];

  # The exported project needs CMake >=3.25, Qt >=6.8 and Go >=1.22.
  # Its stdlib-only backend builds offline and installs bin/kos-weather-backend;
  # no core data service, user unit or D-Bus activation file belongs to this app.
  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DKOS_APPS=weather"
    "-DBUILD_TESTING=OFF"
  ];

  # Go's build cache must be writable inside the Nix sandbox.
  preBuild = ''
    export GOCACHE="$TMPDIR/go-cache"
  '';

  meta = with lib; {
    description = "KOS Weather - standalone Qt Quick forecast application";
    homepage = "https://github.com/NextKde/kos-apps";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
