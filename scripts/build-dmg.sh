#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
app="$project_root/dist/Mac Gaming Uncle.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_root/Config/Info.plist")
artifact="$project_root/dist/Mac-Gaming-Uncle-$version-macOS-arm64.dmg"
checksum="$artifact.sha256"
staging=$(mktemp -d "${TMPDIR:-/tmp}/mac-gaming-uncle-dmg.XXXXXX")
mount_point=$(mktemp -d "${TMPDIR:-/tmp}/mac-gaming-uncle-mount.XXXXXX")

cleanup() {
  /usr/bin/hdiutil detach "$mount_point" >/dev/null 2>&1 || true
  /bin/rm -rf "$staging" "$mount_point"
}
trap cleanup EXIT

"$project_root/scripts/build-app.sh"
/usr/bin/ditto "$app" "$staging/Mac Gaming Uncle.app"
/bin/ln -s /Applications "$staging/Applications"
/bin/rm -f "$artifact" "$checksum"

/usr/bin/hdiutil create \
  -volname "Mac Gaming Uncle $version" \
  -srcfolder "$staging" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$artifact"
/usr/bin/hdiutil verify "$artifact"

/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$mount_point" "$artifact" >/dev/null
/usr/bin/codesign --verify --deep --strict "$mount_point/Mac Gaming Uncle.app"
/bin/test -L "$mount_point/Applications"
/usr/bin/hdiutil detach "$mount_point" >/dev/null

digest=$(/usr/bin/shasum -a 256 "$artifact" | /usr/bin/awk '{print $1}')
/usr/bin/printf '%s  %s\n' "$digest" "${artifact:t}" > "$checksum"
/usr/bin/printf '%s\n%s\n' "$artifact" "$checksum"
