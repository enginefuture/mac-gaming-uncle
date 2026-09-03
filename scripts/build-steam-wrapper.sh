#!/bin/zsh
set -euo pipefail

indie_root=${0:A:h:h}
indie_output="$indie_root/.build/runtime-support"
indie_compiler=${INDIE_MINGW_CC:-/opt/homebrew/bin/x86_64-w64-mingw32-gcc}

if [[ ! -x "$indie_compiler" ]]; then
  indie_compiler=$(command -v x86_64-w64-mingw32-gcc || true)
fi
if [[ -z "$indie_compiler" || ! -x "$indie_compiler" ]]; then
  print -u2 "x86_64-w64-mingw32-gcc is required to build the Steam CEF wrapper"
  exit 1
fi

mkdir -p "$indie_output"
"$indie_compiler" -municode -O2 -Wall -Wextra -static -lshell32 -mwindows -Wl,--no-insert-timestamp \
  "$indie_root/RuntimeSupport/SteamWebHelperWrapper/steamwebhelper-wrapper.c" \
  -o "$indie_output/steamwebhelper-wrapper.exe"
shasum -a 256 "$indie_output/steamwebhelper-wrapper.exe"
