{
    lib,
    stdenv,
    cmake,
    kdePackages,
    opencv,
    onnxruntime,
    python3,
    makeWrapper,
    src,
}:

stdenv.mkDerivation {
    pname = "kos-platform";
    version = lib.removeSuffix "\n" (builtins.readFile "${src}/VERSION");
    src = "${src}/platform";

    # The standalone AI library lives at `services/ai/` in the source
    # tree, while this derivation builds the platform subdirectory alone.
    postPatch = ''
      mkdir -p services
      cp -r ${src}/services/ai services/ai
    '';

    nativeBuildInputs = [
        cmake
        kdePackages.extra-cmake-modules
        makeWrapper
    ];

    buildInputs = [
        kdePackages.qtbase
        kdePackages.qtdeclarative
        kdePackages.kiconthemes
        kdePackages.kglobalaccel
        kdePackages.kio
        opencv
        onnxruntime
    ];

    cmakeFlags = [
        "-DCMAKE_BUILD_TYPE=Release"
        "-DKOS_SPATIAL_ENABLED=ON"
        "-DKOS_PLATFORM_KWIN_SCRIPT_SOURCE=${src}/kwin/window-bridge.js"
        "-DBUILD_TESTING=OFF"
    ];
    dontWrapQtApps = true;

    postInstall = ''
      wrapProgram $out/libexec/kos-platform \
        --set KOS_NOTIFICATION_PYTHON ${python3.withPackages (ps: [ ps.dbus-python ps.pygobject3 ])}/bin/python3
    '';

    meta = with lib; {
        description = "KOS platform integration daemon (D-Bus bridge for KWin, network, audio, etc.)";
        homepage = "https://gitee.com/xiaoyintx_ciallo/test";
        license = licenses.gpl3;
        platforms = platforms.linux;
    };
}
