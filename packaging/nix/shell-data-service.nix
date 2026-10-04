{
  lib,
  stdenv,
  buildGoModule,
  runCommand,
  src,
}:

let
  go-service = buildGoModule {
    pname = "shell-data-service";
    version = "unstable";
    src = "${src}/services/data-service";
    vendorHash = "sha256-Gt+D69n3xUiZDkV6yClL3mJFIAELl9JWPF49JYTdLH0=";
    subPackages = [ "." ];
    ldflags = [ "-s" "-w" ];
    preBuild = ''
      export GOPROXY=https://goproxy.cn,direct
    '';
    postInstall = ''
      mkdir -p $out/libexec
      if [ -f "$out/bin/data-service" ]; then
        mv "$out/bin/data-service" $out/libexec/kos-data-service
      fi
      rm -rf $out/bin
    '';
  };

  patched-service = runCommand "kos-data.service" { } ''
    mkdir -p $out/lib/systemd/user
    # The template lives next to the service it starts; packaging/ used to
    # carry a second copy that drifted from this one.
    sed 's|@CMAKE_INSTALL_FULL_LIBEXECDIR@|${go-service}/libexec|g' \
      ${src}/services/data-service/systemd/kos-data.service.in \
      > $out/lib/systemd/user/kos-data.service
  '';
in
stdenv.mkDerivation {
  pname = "kos-shell-data-service";
  version = "unstable";
  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec $out/lib/systemd/user
    ln -s ${go-service}/libexec/kos-data-service $out/libexec/kos-data-service
    cp ${patched-service}/lib/systemd/user/kos-data.service \
      $out/lib/systemd/user/

    runHook postInstall
  '';

  passthru = {
    inherit go-service patched-service;
    service = patched-service;
  };

  meta = with lib; {
    description = "KOS shared data service";
    homepage = "https://gitee.com/xiaoyintx_ciallo/test";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
