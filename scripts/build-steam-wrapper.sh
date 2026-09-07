#!/bin/zsh
set -euo pipefail

indie_root=${0:A:h:h}
indie_output="$indie_root/.build/runtime-support"
indie_compiler=${INDIE_MINGW_CC:-/opt/homebrew/bin/x86_64-w64-mingw32-gcc}
indie_prebuilt="$indie_root/RuntimeSupport/SteamWebHelperWrapper/steamwebhelper-wrapper.exe"
indie_prebuilt_sha256="7128a560c0347dd360a16697bc17abccdef5c3dac6769a058bf3196c40fe5b80"

if [[ ! -x "$indie_compiler" ]]; then
  indie_compiler=$(command -v x86_64-w64-mingw32-gcc || true)
fi
if [[ -z "$indie_compiler" || ! -x "$indie_compiler" ]]; then
  if [[ ! -f "$indie_prebuilt" ]]; then
    print -u2 "x86_64-w64-mingw32-gcc is unavailable and the verified prebuilt Steam CEF wrapper is missing"
    exit 1
  fi
  indie_actual_sha256=$(shasum -a 256 "$indie_prebuilt" | awk '{print $1}')
  if [[ "$indie_actual_sha256" != "$indie_prebuilt_sha256" ]]; then
    print -u2 "prebuilt Steam CEF wrapper failed SHA-256 verification"
    exit 1
  fi
  mkdir -p "$indie_output"
  ditto "$indie_prebuilt" "$indie_output/steamwebhelper-wrapper.exe"
  shasum -a 256 "$indie_output/steamwebhelper-wrapper.exe"
  exit 0
fi

mkdir -p "$indie_output"
"$indie_compiler" -municode -O2 -Wall -Wextra -static -lshell32 -mwindows -Wl,--no-insert-timestamp \
  "$indie_root/RuntimeSupport/SteamWebHelperWrapper/steamwebhelper-wrapper.c" \
  -o "$indie_output/steamwebhelper-wrapper.exe"
shasum -a 256 "$indie_output/steamwebhelper-wrapper.exe"
