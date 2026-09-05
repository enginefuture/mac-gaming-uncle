#!/bin/zsh
set -euo pipefail
project_root=${0:A:h:h}
cd "$project_root"
bin_dir=$(swift build -c release --show-bin-path)
localization_test=$(mktemp -d /tmp/macgaminguncle-localization.XXXXXX)
trap 'rm -rf "$localization_test"' EXIT
test_app="$localization_test/LocalizationSmoke.app"
mkdir -p "$test_app/Contents/MacOS" "$test_app/Contents/Resources"
ditto Config/Info.plist "$test_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable LocalizationSmoke' "$test_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.enginefuture.localization-smoke' "$test_app/Contents/Info.plist"
ditto 'dist/Mac Gaming Uncle.app/Contents/Resources/MacGamingUncle_IndieCore.bundle' "$test_app/Contents/Resources/MacGamingUncle_IndieCore.bundle"
swiftc -parse-as-library -I "$bin_dir/Modules" -I Sources/CSQLite \
  Fixtures/macOS/LocalizationSmoke.swift "$bin_dir"/IndieCore.build/*.o \
  -o "$test_app/Contents/MacOS/LocalizationSmoke" -lsqlite3
"$test_app/Contents/MacOS/LocalizationSmoke"
