#!/bin/bash
# Test fixture provisioning ONLY, inside an ephemeral CI container/VM as root.
# This is deliberately separate from the installer, which never installs packages.
set -euo pipefail
. /etc/os-release
if [[ "$ID" == arch ]]; then
    pacman -Syu --noconfirm --needed base-devel python git cmake pkgconf nodejs qt6-base qt6-declarative qt6-svg qt6-shadertools qt6-5compat qt6-wayland qtkeychain-qt6 qrencode taglib gstreamer gst-plugins-base gst-plugins-good gst-libav curl ca-certificates
else
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    if [[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]]; then
        apt-get install -y --no-install-recommends build-essential python3 git cmake pkg-config curl ca-certificates xz-utils qt6-base-dev qt6-declarative-dev
    else
    apt-get install -y --no-install-recommends build-essential python3 git cmake pkg-config curl ca-certificates xz-utils \
      qt6-base-dev qt6-declarative-dev qt6-svg-dev qt6-svg-plugins qt6-shadertools-dev qt6-5compat-dev qt6-wayland libqt6sql6-sqlite \
      qtkeychain-qt6-dev libqrencode-dev libtag1-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
      gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-libav \
      qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-dialogs qml6-module-qtquick-layouts \
      qml6-module-qtquick-window qml6-module-qtquick-templates qml6-module-qtqml-workerscript \
      qml6-module-qtquick-effects qml6-module-qt5compat-graphicaleffects qml6-module-qtcore
    fi
    # Debian's distro Node can be below the documented minimum. Provision a fixed
    # official Node for the success fixture; never silently change installer behavior.
    d=$(mktemp -d)
    curl -fL --retry 3 https://nodejs.org/dist/v22.19.0/SHASUMS256.txt -o "$d/sums"
    curl -fL --retry 3 https://nodejs.org/dist/v22.19.0/node-v22.19.0-linux-x64.tar.xz -o "$d/node-v22.19.0-linux-x64.tar.xz"
    (cd "$d"; grep ' node-v22.19.0-linux-x64.tar.xz$' sums | sha256sum -c -)
    tar -xJf "$d/node-v22.19.0-linux-x64.tar.xz" -C /usr/local --strip-components=1
    rm -rf "$d"
fi
