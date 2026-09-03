#!/bin/zsh
set -euo pipefail

indie_root=${0:A:h:h}
indie_output="$indie_root/.build/windows-fixtures"
mkdir -p "$indie_output"

x86_64-w64-mingw32-g++ -std=c++20 -O2 -municode -static -static-libgcc -static-libstdc++ \
  "$indie_root/Fixtures/Windows/win32-smoke.cpp" -lgdi32 -o "$indie_output/indie-smoke-x64.exe"
i686-w64-mingw32-g++ -std=c++20 -O2 -municode -static -static-libgcc -static-libstdc++ \
  "$indie_root/Fixtures/Windows/win32-smoke.cpp" -lgdi32 -o "$indie_output/indie-smoke-x86.exe"
x86_64-w64-mingw32-g++ -std=c++20 -O2 -municode -static -static-libgcc -static-libstdc++ \
  "$indie_root/Fixtures/Windows/d3d11-clear.cpp" -ld3d11 -ldxgi -ldxguid -lgdi32 -o "$indie_output/indie-d3d11-fixture.exe"
x86_64-w64-mingw32-g++ -std=c++20 -O2 -municode -static -static-libgcc -static-libstdc++ \
  "$indie_root/Fixtures/Windows/d3d12-clear.cpp" -ld3d12 -ldxgi -ldxguid -lgdi32 -o "$indie_output/indie-d3d12-fixture.exe"

for indie_fixture in "$indie_output"/*.exe; do
  shasum -a 256 "$indie_fixture"
done
