{ lib, writeShellScript, coreutils, findutils, kos }:

# Both the user unit and kos-ctl deploy this exact package and module set.
writeShellScript "kos-shell-init" ''
  set -euo pipefail
  export PATH=${lib.makeBinPath [ coreutils findutils ]}:"$PATH"

  # The optional destination lets CI exercise deployment in its build sandbox.
  shell_config="''${1:-$HOME/.config/quickshell/kos}"

  # Check the selected package before removing the previous deployment.
  test -f ${kos}/share/kos-desktop/shell/shell.qml
  test -d ${kos}/share/shared/qml
  test -d ${kos}/qml/Kos/Spatial3D
  test -d ${kos}/qml/Kos/SurfaceShape

  if [[ -d "$shell_config" ]]; then
    find "$shell_config" -type d -exec chmod u+w {} + 2>/dev/null || true
    find "$shell_config" -type f -exec chmod u+w {} + 2>/dev/null || true
    rm -rf "$shell_config"
  fi

  mkdir -p "$shell_config/shared/qml" "$shell_config/Kos"
  cp -rL --no-preserve=mode ${kos}/share/kos-desktop/shell/. "$shell_config/"
  cp -rL --no-preserve=mode ${kos}/share/shared/qml/. "$shell_config/shared/qml/"
  cp -rL --no-preserve=mode \
    ${kos}/qml/Kos/Spatial3D ${kos}/qml/Kos/SurfaceShape "$shell_config/Kos/"
''
