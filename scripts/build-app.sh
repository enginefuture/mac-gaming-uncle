#!/bin/zsh
set -euo pipefail

indie_root=${0:A:h:h}
indie_configuration=${INDIE_CONFIGURATION:-release}
indie_destination="$indie_root/dist/Indie.app"

cd "$indie_root"
"$indie_root/scripts/build-steam-wrapper.sh"
swift build -c "$indie_configuration" --product IndieApp
indie_bin_dir=$(swift build -c "$indie_configuration" --show-bin-path)

rm -rf "$indie_destination"
mkdir -p "$indie_destination/Contents/MacOS" "$indie_destination/Contents/Resources"
ditto "$indie_bin_dir/IndieApp" "$indie_destination/Contents/MacOS/IndieApp"
ditto "$indie_root/Config/Info.plist" "$indie_destination/Contents/Info.plist"
ditto "$indie_root/Assets/Indie.icns" "$indie_destination/Contents/Resources/Indie.icns"

for indie_bundle in "$indie_bin_dir"/Indie_*.bundle(N); do
  ditto "$indie_bundle" "$indie_destination/Contents/Resources/${indie_bundle:t}"
done

mkdir -p "$indie_destination/Contents/Resources/RuntimeSupport"
ditto "$indie_root/.build/runtime-support/steamwebhelper-wrapper.exe" "$indie_destination/Contents/Resources/RuntimeSupport/steamwebhelper-wrapper.exe"
ditto "$indie_root/RuntimeSupport/SteamWebHelperWrapper/LICENSE" "$indie_destination/Contents/Resources/RuntimeSupport/steamwebhelper-wrapper.LICENSE"

if [[ -n ${INDIE_CODESIGN_IDENTITY:-} ]]; then
  codesign --force --timestamp --options runtime --entitlements "$indie_root/Config/Indie.entitlements" --sign "$INDIE_CODESIGN_IDENTITY" "$indie_destination"
else
  codesign --force --sign - "$indie_destination"
  print -u2 "warning: created an ad-hoc signed development build; do not publish it"
fi

codesign --verify --deep --strict "$indie_destination"
print "$indie_destination"
