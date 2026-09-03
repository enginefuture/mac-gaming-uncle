#!/bin/zsh
set -euo pipefail

indie_root=${0:A:h:h}
cd "$indie_root"
swift test
swift build -c release --product IndieApp
swift build -c release --product indiectl
"$indie_root/scripts/build-steam-wrapper.sh"
"$indie_root/scripts/build-windows-fixtures.sh"
