{
  lib,
  stdenv,
  pkgs,
  src,
  quickshell ? pkgs.quickshell,
  buildWeather ? false,
}:

let
  shell-data-service = pkgs.callPackage ./shell-data-service.nix { inherit src; };
  kos-settings = pkgs.callPackage ./kos-settings.nix {
    inherit src;
    quickshell = if quickshell != null then quickshell else pkgs.quickshell;
  };
  kos-platform = pkgs.callPackage ./kos-platform.nix { inherit src; };
  kos-surface-shape = pkgs.callPackage ./kos-surface-shape.nix { inherit src; };
  kos-spatial3d = pkgs.callPackage ./kos-spatial3d.nix { inherit src; };
  kwin-dock-window-animation = pkgs.callPackage ./kwin-dock-window-animation.nix { inherit src; };
  kwin-stage-animation = pkgs.callPackage ./kwin-stage-animation.nix { inherit src; };
  kwin-context-menu-input = pkgs.callPackage ./kwin-context-menu-input.nix { inherit src; };
  kwin-effects-glass = pkgs.callPackage ./kwin-effects-glass.nix { inherit src; };
  kwin-kos-bridge = pkgs.callPackage ./kwin-kos-bridge.nix { inherit src; };
  kosctl = pkgs.callPackage ./kosctl.nix { inherit src; };
  kwin-kos-decoration = pkgs.callPackage ./kwin-kos-decoration.nix { inherit src; };
  kos-weather = if buildWeather then pkgs.callPackage ./kos-weather.nix { inherit src; } else null;

  qs_bin = if quickshell != null then "${quickshell}/bin/quickshell" else "/run/current-system/sw/bin/quickshell";

  patched-platform-service = stdenv.mkDerivation {
    name = "kos-platform.service";
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/systemd/user
      sed 's|%h/.local/libexec/kos-platform|${kos-platform}/libexec/kos-platform|g' \
        ${src}/packaging/systemd/kos-platform.service \
        > $out/lib/systemd/user/kos-platform.service
      runHook postInstall
    '';
  };

  patched-data-service = shell-data-service.passthru.patched-service;

  patched-shell-service = stdenv.mkDerivation {
    name = "kos-shell.service";
    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/systemd/user
      sed 's|@QS_EXEC@|${qs_bin}|g' \
        ${src}/packaging/systemd/kos-shell.service.in \
        > $out/lib/systemd/user/kos-shell.service
      sed -i 's|^Environment=QML2_IMPORT_PATH=.*|Environment=QML2_IMPORT_PATH=%h/.config/quickshell/kos:${kos-spatial3d}/lib/qt6/qml:${pkgs.kdePackages.qtquick3d}/lib/qt-6/qml:${pkgs.kdePackages.qt5compat}/lib/qt-6/qml|' $out/lib/systemd/user/kos-shell.service
      sed -i '/^Environment=QML2_IMPORT_PATH=/a Environment=QT_PLUGIN_PATH=${pkgs.kdePackages.qtsvg}/lib/qt-6/plugins:${pkgs.kdePackages.qtimageformats}/lib/qt-6/plugins' $out/lib/systemd/user/kos-shell.service
      runHook postInstall
    '';
  };
in
stdenv.mkDerivation {
  pname = "kos-desktop";
  version = "unstable";
  inherit src;

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # --- Binaries ---
    mkdir -p $out/libexec
    ln -s ${kos-platform}/libexec/kos-platform $out/libexec/kos-platform
    ln -s ${kos-platform}/libexec/kos-ai-worker $out/libexec/kos-ai-worker
    ln -s ${shell-data-service}/libexec/kos-data-service $out/libexec/kos-data-service

    mkdir -p $out/bin
    ln -s ${kos-settings}/bin/kos-settings $out/bin/kos-settings

    # --- Weather app (optional) ---
    if [ -n "${if buildWeather then "1" else ""}" ]; then
      ln -s ${kos-weather}/bin/kos-weather $out/bin/kos-weather
    fi

    # --- Shared QML / Shell ---
    mkdir -p $out/share/kos-desktop
    cp -r shell/ $out/share/kos-desktop/
    cp -r shared/ $out/share/kos-desktop/
    cp shell/shell.qml $out/share/kos-desktop/shell.qml
    cp -r shell/desktop $out/share/kos-desktop/desktop

    # --- Settings QML (for reference; kos-settings binary embeds path) ---
    mkdir -p $out/share/kos/settings
    cp apps/settings/main.qml $out/share/kos/settings/main.qml
    cp apps/settings/Wallpaper*.qml apps/settings/ThemeWallpaperTile.qml \
      apps/settings/ServicesSettingsPage.qml $out/share/kos/settings/
    cp -r apps/settings/icons $out/share/kos/settings/
    mkdir -p $out/qml/Kos
    ln -s ${kos-spatial3d}/lib/qt6/qml/Kos/Spatial3D $out/qml/Kos/Spatial3D
    ln -s ${kos-surface-shape}/lib/qt6/qml/Kos/SurfaceShape $out/qml/Kos/SurfaceShape

    # --- KWin bridge script ---
    mkdir -p $out/share/kos/platform/kwin
    ln -s ${kos-platform}/share/kos/platform/kwin/window-bridge.js \
      $out/share/kos/platform/kwin/window-bridge.js

    # --- Shared QML ---
    # The whole tree, not just controls/: apps/settings is a separate process and
    # resolves `import "../../shared/qml/<dir>"` against its own installed
    # location, so controls/ alone leaves the colorize/ import unresolvable and
    # the window dies in QQmlApplicationEngine before it is ever shown. Build
    # files and tests must never reach the installed tree.
    mkdir -p $out/share/shared/qml
    cp -r shared/qml/. $out/share/shared/qml/
    find $out/share/shared/qml -maxdepth 1 \
        -name CMakeLists.txt -o -name 'test_*.mjs' | xargs -r rm -f

    # --- Desktop entries ---
    mkdir -p $out/share/applications
    substitute packaging/desktop/kos-settings.desktop.in \
      $out/share/applications/kos-settings.desktop \
      --replace-fail 'kos-settings' "${kos-settings}/bin/kos-settings"
    substitute packaging/desktop/org.kos.Platform.desktop.in \
      $out/share/applications/org.kos.Platform.desktop \
      --replace-fail '@KOS_PLATFORM_EXEC@' "${kos-platform}/libexec/kos-platform"

    # --- Systemd user services ---
    mkdir -p $out/lib/systemd/user
    cp ${patched-platform-service}/lib/systemd/user/kos-platform.service \
      $out/lib/systemd/user/
    cp ${patched-data-service}/lib/systemd/user/kos-data.service \
      $out/lib/systemd/user/
    cp ${patched-shell-service}/lib/systemd/user/kos-shell.service \
      $out/lib/systemd/user/

    runHook postInstall
  '';

  passthru = {
    inherit shell-data-service kos-settings kos-platform kos-spatial3d kos-surface-shape kosctl
            kwin-dock-window-animation kwin-stage-animation kwin-context-menu-input kwin-effects-glass
            kwin-kos-bridge kwin-kos-decoration;
    inherit patched-platform-service patched-shell-service;
    weather = if buildWeather then kos-weather else null;
  };

  meta = with lib; {
    description = "KOS Desktop Shell - iPadOS-style desktop for KDE Plasma 6";
    homepage = "https://gitee.com/xiaoyintx_ciallo/test";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
