#!/bin/bash
# Root entrypoint for disposable CI containers ONLY.
set -euo pipefail
source_dir=$1
revision=$2
suite=$3
results=$4
mkdir -p "$results"
. /etc/os-release
if [[ "$ID" == arch ]]; then
    pacman -Sy --noconfirm --needed python shadow
else
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends python3 passwd
fi
useradd -m -s /bin/bash installer-test
chown -R installer-test:installer-test "$results"
export KMUSIC_SOURCE_DIR="$source_dir"
runuser -u installer-test -- python3 -m unittest discover -s "$suite" -p test_kmusic_installer.py -v > "$results/unit.log" 2>&1
runuser -u installer-test -- python3 "$suite/run_kmusic_installation.py" --source "$source_dir" --revision "$revision" --mode missing --results "$results/missing"
bash "$suite/provision-kmusic-ci.sh" > "$results/provision.log" 2>&1
mode=full
if [[ "$ID" == ubuntu && "$VERSION_ID" == 24.04 ]]; then mode=old; fi
runuser -u installer-test -- python3 "$suite/run_kmusic_installation.py" --source "$source_dir" --revision "$revision" --mode "$mode" --results "$results/$mode"
