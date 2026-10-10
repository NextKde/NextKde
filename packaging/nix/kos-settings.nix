{
    lib,
    stdenv,
    cmake,
    ninja,
    kdePackages,
    quickshell,
    src,
}:

stdenv.mkDerivation {
    pname = "kos-settings";
    version = "unstable";
    inherit src;

    nativeBuildInputs = [
        cmake
        ninja
        kdePackages.wrapQtAppsHook
    ];

    buildInputs = [ kdePackages.kconfig kdePackages.qtbase kdePackages.qtdeclarative
                    kdePackages.qtsvg kdePackages.qtimageformats kdePackages.qt5compat ];

    preFixup = ''
        qtWrapperArgs+=(--prefix PATH : ${lib.makeBinPath [ quickshell ]})
    '';

    dontBuild = true;
    dontConfigure = true;

    installPhase = ''
        runHook preInstall

        cmake -S apps/settings -B "$TMPDIR/build" -G Ninja \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX=$out
        cmake --build "$TMPDIR/build" --parallel
        cmake --install "$TMPDIR/build"

        # The whole tree has to be deployed beside the settings window, not just
        # controls/: it resolves `import "../../shared/qml/<dir>"` against its own
        # installed location, so shipping controls/ alone leaves the colorize/
        # import unresolvable and the window dies in QQmlApplicationEngine before
        # it is ever shown. Mirrors the shared/qml install rule in the top-level
        # CMakeLists.txt, which excludes the same two patterns.
        mkdir -p $out/share/shared/qml
        cp -r shared/qml/. $out/share/shared/qml/
        find $out/share/shared/qml -maxdepth 1 \
            -name CMakeLists.txt -o -name 'test_*.mjs' | xargs -r rm -f

        runHook postInstall
    '';

    meta = with lib; {
        description = "KOS Desktop Shell settings application";
        homepage = "https://gitee.com/xiaoyintx_ciallo/test";
        license = licenses.gpl3;
        platforms = platforms.linux;
    };
}
