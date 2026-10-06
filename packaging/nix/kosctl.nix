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
}:

stdenv.mkDerivation {
  pname = "kosctl";
  version = "unstable";
  inherit src;

  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp tools/kosctl $out/bin/kosctl
    chmod +x $out/bin/kosctl

    # Wrap with runtime dependencies so kosctl works from any PATH
    wrapProgram $out/bin/kosctl \
      --prefix PATH : ${lib.makeBinPath [
        coreutils
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
