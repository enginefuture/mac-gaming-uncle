#!/bin/zsh
set -euo pipefail

indie_root=${0:A:h:h}
cd "$indie_root"
swift test
swift build -c release --product MacGamingUncleApp
swift build -c release --product macgamingunclectl
"$indie_root/scripts/build-steam-wrapper.sh"
"$indie_root/scripts/build-windows-fixtures.sh"
