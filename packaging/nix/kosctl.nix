{
  lib,
  stdenv,
  src,
  bash,
  makeWrapper,
  coreutils,
  systemd,
  kdePackages,
  quickshell,
  python3,
}:

stdenv.mkDerivation {
  pname = "kosctl";
  version = lib.removeSuffix "\n" (builtins.readFile "${src}/VERSION");
  inherit src;

  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp tools/kosctl $out/bin/kosctl
    chmod +x $out/bin/kosctl
    mkdir -p $out/tools
    cp tools/source-release.py tools/deploy-runtime.py $out/tools/
    cp VERSION $out/VERSION
    # The control tool's version is not proof that the desktop is installed.
    # Read the core package's system-profile record; standalone wrappers report
    # unknown unless KOS_RELEASE_RECORD explicitly selects another deployment.
    # Wrap with runtime dependencies so kosctl works from any PATH
    wrapProgram $out/bin/kosctl \
      --set-default KOS_RELEASE_RECORD "/run/current-system/sw/share/kos/release.json" \
      --prefix PATH : ${lib.makeBinPath [
        coreutils
        python3
        quickshell
        systemd
        kdePackages.kconfig
      ]}

    runHook postInstall
  '';

  meta = with lib; {
    description = "KOS Desktop Shell control tool";
    homepage = "https://gitee.com/xiaoyintx_ciallo/test";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
