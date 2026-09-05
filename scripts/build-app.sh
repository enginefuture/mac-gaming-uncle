#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
build_configuration=${MAC_GAMING_UNCLE_CONFIGURATION:-${INDIE_CONFIGURATION:-release}}
app_destination="$project_root/dist/Mac Gaming Uncle.app"

cd "$project_root"
"$project_root/scripts/build-steam-wrapper.sh"
swift build -c "$build_configuration" --product MacGamingUncleApp
bin_dir=$(swift build -c "$build_configuration" --show-bin-path)

rm -rf "$app_destination"
mkdir -p "$app_destination/Contents/MacOS" "$app_destination/Contents/Resources"
ditto "$bin_dir/MacGamingUncleApp" "$app_destination/Contents/MacOS/MacGamingUncleApp"
ditto "$project_root/Config/Info.plist" "$app_destination/Contents/Info.plist"
ditto "$project_root/Assets/MacGamingUncle.icns" "$app_destination/Contents/Resources/MacGamingUncle.icns"

for resource_bundle in "$bin_dir"/MacGamingUncle_*.bundle(N); do
  ditto "$resource_bundle" "$app_destination/Contents/Resources/${resource_bundle:t}"
done

for resource_name in MacGamingUncle_IndieCore.bundle MacGamingUncle_IndieCatalog.bundle MacGamingUncle_MacGamingUncleApp.bundle; do
  test -d "$app_destination/Contents/Resources/$resource_name"
done

mkdir -p "$app_destination/Contents/Resources/RuntimeSupport"
ditto "$project_root/.build/runtime-support/steamwebhelper-wrapper.exe" "$app_destination/Contents/Resources/RuntimeSupport/steamwebhelper-wrapper.exe"
ditto "$project_root/RuntimeSupport/SteamWebHelperWrapper/LICENSE" "$app_destination/Contents/Resources/RuntimeSupport/steamwebhelper-wrapper.LICENSE"

signing_identity=${MAC_GAMING_UNCLE_CODESIGN_IDENTITY:-${INDIE_CODESIGN_IDENTITY:-}}
if [[ -n $signing_identity ]]; then
  codesign --force --timestamp --options runtime --entitlements "$project_root/Config/MacGamingUncle.entitlements" --sign "$signing_identity" "$app_destination"
else
  codesign --force --sign - "$app_destination"
  print -u2 "warning: created an ad-hoc signed development build; do not publish it"
fi

codesign --verify --deep --strict "$app_destination"
print "$app_destination"
