#!/bin/zsh
set -euo pipefail

# Wine/LLVM honor SOURCE_DATE_EPOCH for generated files and PE timestamps.
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1768262400}
export ZERO_AR_DATE=1
export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-15.0}

indie_root=${0:A:h:h}
indie_source_url="https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz"
indie_source_sha256="ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872"
indie_nettle_url="https://ftp.gnu.org/gnu/nettle/nettle-3.10.tar.gz"
indie_nettle_sha256="b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c"
indie_inotify_url="https://github.com/libinotify-kqueue/libinotify-kqueue/archive/refs/tags/20240724.tar.gz"
indie_inotify_sha256="120398ff95336d04f3ce7ac820e0490059625976264100dcc9af9d11e992b0ca"
indie_sdl_url="https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-2.32.10.tar.gz"
indie_sdl_sha256="5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165"
indie_runtime_version="11.0.2"
indie_output_dir=${INDIE_WINE_OUTPUT_DIR:-"$indie_root/dist/runtime"}
indie_work_root=${INDIE_WINE_BUILD_ROOT:-$(mktemp -d /tmp/indie-wine11.XXXXXX)}
indie_source_archive=${INDIE_WINE_SOURCE_ARCHIVE:-"$indie_work_root/crossover-sources-26.3.0.tar.gz"}
indie_nettle_archive=${INDIE_NETTLE_SOURCE_ARCHIVE:-"$indie_work_root/nettle-3.10.tar.gz"}
indie_inotify_archive=${INDIE_INOTIFY_SOURCE_ARCHIVE:-"$indie_work_root/libinotify-kqueue-20240724.tar.gz"}
indie_sdl_archive=${INDIE_SDL_SOURCE_ARCHIVE:-"$indie_work_root/SDL2-2.32.10.tar.gz"}
indie_extract_root="$indie_work_root/source"
indie_dependency_root="$indie_work_root/dependencies"
indie_freetype_build="$indie_work_root/freetype-build"
indie_gmp_build="$indie_work_root/gmp-build"
indie_nettle_source="$indie_work_root/nettle-3.10"
indie_nettle_build="$indie_work_root/nettle-build"
indie_inotify_source="$indie_work_root/libinotify-kqueue-20240724"
indie_sdl_source="$indie_work_root/SDL2-2.32.10"
indie_sdl_build="$indie_work_root/sdl2-build"
indie_gnutls_build="$indie_work_root/gnutls-build"
indie_wine_build="$indie_work_root/wine-build"
indie_wine_install="$indie_work_root/wine-install"
indie_stage_parent="$indie_work_root/package"
indie_stage="$indie_stage_parent/wine-runtime"
indie_archive="$indie_output_dir/indie-wine-$indie_runtime_version-macos-x86_64.tar.xz"

for indie_tool in autoreconf cmake curl make patch shasum tar xcrun; do
  if ! command -v "$indie_tool" >/dev/null 2>&1; then
    print -u2 "缺少构建工具：$indie_tool"
    print -u2 "建议安装：brew install cmake bison flex llvm lld"
    exit 2
  fi
done

indie_bison="/opt/homebrew/opt/bison/bin/bison"
indie_flex="/opt/homebrew/opt/flex/bin/flex"
indie_mingw_x64="/opt/homebrew/bin/x86_64-w64-mingw32-gcc"
indie_mingw_x86="/opt/homebrew/bin/i686-w64-mingw32-gcc"
indie_llvm_strip="/opt/homebrew/opt/llvm/bin/llvm-strip"
if [[ ! -x "$indie_bison" || ! -x "$indie_flex" || ! -x "$indie_mingw_x64" ||
      ! -x "$indie_mingw_x86" || ! -x "$indie_llvm_strip" ]]; then
  print -u2 "需要 Homebrew bison、flex、LLVM 与 MinGW：brew install bison flex llvm mingw-w64"
  exit 2
fi
indie_build_path="/opt/homebrew/opt/llvm/bin:/opt/homebrew/opt/lld/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH="$indie_build_path"

mkdir -p "$indie_work_root" "$indie_output_dir"
if [[ ! -f "$indie_source_archive" ]]; then
  curl --fail --location --retry 3 --output "$indie_source_archive" "$indie_source_url"
fi

if [[ ! -f "$indie_nettle_archive" ]]; then
  curl --fail --location --retry 3 --output "$indie_nettle_archive" "$indie_nettle_url"
fi
if [[ ! -f "$indie_inotify_archive" ]]; then
  curl --fail --location --retry 3 --output "$indie_inotify_archive" "$indie_inotify_url"
fi
if [[ ! -f "$indie_sdl_archive" ]]; then
  curl --fail --location --retry 3 --output "$indie_sdl_archive" "$indie_sdl_url"
fi

indie_actual_sha256=$(shasum -a 256 "$indie_source_archive" | awk '{print $1}')
if [[ "$indie_actual_sha256" != "$indie_source_sha256" ]]; then
  print -u2 "Wine 上游源码校验失败：期望 $indie_source_sha256，实际 $indie_actual_sha256"
  exit 3
fi
indie_nettle_actual_sha256=$(shasum -a 256 "$indie_nettle_archive" | awk '{print $1}')
if [[ "$indie_nettle_actual_sha256" != "$indie_nettle_sha256" ]]; then
  print -u2 "Nettle 上游源码校验失败：期望 $indie_nettle_sha256，实际 $indie_nettle_actual_sha256"
  exit 3
fi
indie_inotify_actual_sha256=$(shasum -a 256 "$indie_inotify_archive" | awk '{print $1}')
if [[ "$indie_inotify_actual_sha256" != "$indie_inotify_sha256" ]]; then
  print -u2 "libinotify-kqueue 上游源码校验失败：期望 $indie_inotify_sha256，实际 $indie_inotify_actual_sha256"
  exit 3
fi
indie_sdl_actual_sha256=$(shasum -a 256 "$indie_sdl_archive" | awk '{print $1}')
if [[ "$indie_sdl_actual_sha256" != "$indie_sdl_sha256" ]]; then
  print -u2 "SDL2 上游源码校验失败：期望 $indie_sdl_sha256，实际 $indie_sdl_actual_sha256"
  exit 3
fi

mkdir -p "$indie_extract_root"
tar -xf "$indie_source_archive" -C "$indie_extract_root"
indie_wine_source="$indie_extract_root/sources/wine"
indie_freetype_source="$indie_extract_root/sources/freetype"
indie_gmp_source="$indie_extract_root/sources/gnutls/gmp"
indie_gnutls_source="$indie_extract_root/sources/gnutls/gnutls"
if [[ ! -f "$indie_wine_source/configure" || ! -f "$indie_freetype_source/CMakeLists.txt" ||
      ! -f "$indie_gmp_source/configure" || ! -f "$indie_gnutls_source/configure" ]]; then
  print -u2 "源码包结构与锁定清单不一致"
  exit 4
fi

for indie_patch in "$indie_root"/patches/wine11/*.patch(N); do
  patch -d "$indie_wine_source" -p1 < "$indie_patch"
done

tar -xf "$indie_nettle_archive" -C "$indie_work_root"
tar -xf "$indie_inotify_archive" -C "$indie_work_root"
tar -xf "$indie_sdl_archive" -C "$indie_work_root"
if [[ ! -f "$indie_nettle_source/configure" ]]; then
  print -u2 "Nettle 源码包结构与锁定清单不一致"
  exit 4
fi
if [[ ! -f "$indie_inotify_source/configure.ac" ]]; then
  print -u2 "libinotify-kqueue 源码包结构与锁定清单不一致"
  exit 4
fi
if [[ ! -f "$indie_sdl_source/CMakeLists.txt" ]]; then
  print -u2 "SDL2 源码包结构与锁定清单不一致"
  exit 4
fi

cmake -S "$indie_freetype_source" -B "$indie_freetype_build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
  -DCMAKE_INSTALL_PREFIX="$indie_dependency_root" \
  -DCMAKE_INSTALL_NAME_DIR="$indie_dependency_root/lib" \
  -DBUILD_SHARED_LIBS=ON \
  -DFT_DISABLE_BROTLI=TRUE \
  -DFT_DISABLE_BZIP2=TRUE \
  -DFT_DISABLE_HARFBUZZ=TRUE \
  -DFT_DISABLE_PNG=TRUE
cmake --build "$indie_freetype_build" --parallel "$(sysctl -n hw.logicalcpu)"
cmake --install "$indie_freetype_build"

mkdir -p "$indie_gmp_build"
cd "$indie_gmp_build"
arch -x86_64 /usr/bin/env \
  CC=/usr/bin/clang CXX=/usr/bin/clang++ \
  CFLAGS="-O2 -arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" CXXFLAGS="-O2 -arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
  LDFLAGS="-arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
  "$indie_gmp_source/configure" \
    --prefix="$indie_dependency_root" --enable-shared --disable-static --disable-cxx
arch -x86_64 make -j"$(sysctl -n hw.logicalcpu)"
arch -x86_64 make install

mkdir -p "$indie_nettle_build"
cd "$indie_nettle_build"
arch -x86_64 /usr/bin/env \
  CC=/usr/bin/clang \
  CFLAGS="-O2 -arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
  CPPFLAGS="-I$indie_dependency_root/include" \
  LDFLAGS="-arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -L$indie_dependency_root/lib" \
  PATH="$indie_build_path" \
  "$indie_nettle_source/configure" \
    --prefix="$indie_dependency_root" --enable-shared --disable-static --disable-documentation
arch -x86_64 make -j"$(sysctl -n hw.logicalcpu)"
arch -x86_64 make install

cd "$indie_inotify_source"
autoreconf -fvi
arch -x86_64 /usr/bin/env \
  CC=/usr/bin/clang \
  CFLAGS="-O2 -arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
  LDFLAGS="-arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
  ac_cv_func_fdclosedir=no \
  ./configure --prefix="$indie_dependency_root" --enable-shared --disable-static
make -j"$(sysctl -n hw.logicalcpu)" install

cmake -S "$indie_sdl_source" -B "$indie_sdl_build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
  -DCMAKE_INSTALL_PREFIX="$indie_dependency_root" \
  -DCMAKE_INSTALL_NAME_DIR="$indie_dependency_root/lib" \
  -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF \
  -DSDL_HIDAPI=ON -DSDL_HIDAPI_JOYSTICK=ON
cmake --build "$indie_sdl_build" --parallel "$(sysctl -n hw.logicalcpu)"
cmake --install "$indie_sdl_build"

mkdir -p "$indie_gnutls_build"
cd "$indie_gnutls_build"
arch -x86_64 /usr/bin/env \
  CC=/usr/bin/clang CXX=/usr/bin/clang++ \
  CFLAGS="-O2 -arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" CXXFLAGS="-O2 -arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
  CPPFLAGS="-I$indie_dependency_root/include" \
  LDFLAGS="-arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -L$indie_dependency_root/lib" \
  PKG_CONFIG=/opt/homebrew/bin/pkg-config \
  PKG_CONFIG_LIBDIR="$indie_dependency_root/lib/pkgconfig" \
  DYLD_LIBRARY_PATH="$indie_dependency_root/lib" \
  NETTLE_CFLAGS="-I$indie_dependency_root/include" NETTLE_LIBS="-lnettle" \
  HOGWEED_CFLAGS="-I$indie_dependency_root/include" HOGWEED_LIBS="-lhogweed" \
  GMP_CFLAGS="-I$indie_dependency_root/include" GMP_LIBS="-lgmp" \
  PATH="$indie_build_path" \
  "$indie_gnutls_source/configure" \
    --prefix="$indie_dependency_root" --enable-shared --disable-static \
    --disable-doc --disable-tools --disable-cxx --disable-tests --disable-gost \
    --with-included-libtasn1 --with-included-unistring \
    --without-idn --without-p11-kit --without-tpm --without-tpm2 \
    --without-zlib --without-brotli --without-zstd
DYLD_LIBRARY_PATH="$indie_dependency_root/lib" make -j"$(sysctl -n hw.logicalcpu)" install

mkdir -p "$indie_wine_build"
cd "$indie_wine_build"
arch -x86_64 /usr/bin/env \
  CC=/usr/bin/clang CXX=/usr/bin/clang++ OBJC=/usr/bin/clang \
  CFLAGS="-O2 -arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
  CXXFLAGS="-O2 -arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
  OBJCFLAGS="-O2 -arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
  CPPFLAGS="-I$indie_dependency_root/include -I$indie_dependency_root/include/freetype2" \
  LDFLAGS="-arch x86_64 -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -L$indie_dependency_root/lib" \
  PKG_CONFIG=/opt/homebrew/bin/pkg-config \
  PKG_CONFIG_LIBDIR="$indie_dependency_root/lib/pkgconfig" \
  PATH="$indie_build_path" \
  "$indie_wine_source/configure" \
    --prefix="$indie_wine_install" \
    --enable-archs=i386,x86_64 \
    --with-inotify --without-x --without-wayland --without-vulkan --without-gstreamer \
    --with-gnutls --with-freetype --without-fontconfig --without-cups \
    --without-dbus --without-krb5 --without-opencl --without-pcap \
    --without-pulse --without-sane --with-sdl --without-udev \
    --without-usb --without-v4l2

DYLD_LIBRARY_PATH="$indie_dependency_root/lib" make -j"$(sysctl -n hw.logicalcpu)" install

mkdir -p "$indie_stage/bin" "$indie_stage/lib" "$indie_stage/share" "$indie_stage/licenses"
ditto "$indie_wine_install/bin/wine" "$indie_stage/bin/wine"
ditto "$indie_wine_install/bin/wineserver" "$indie_stage/bin/wineserver"
ditto "$indie_wine_install/lib/wine" "$indie_stage/lib/wine"
ditto "$indie_wine_install/share/wine" "$indie_stage/share/wine"
# `make install` also installs SDK import archives. They are useful to
# developers but never loaded at runtime and account for more than 1 GB.
find "$indie_stage/lib/wine" -type f -name '*.a' -delete
find "$indie_stage/lib/wine/i386-windows" "$indie_stage/lib/wine/x86_64-windows" -type f -print0 | while IFS= read -r -d '' indie_pe; do
  if file "$indie_pe" | grep -q "PE32"; then
    "$indie_llvm_strip" --strip-all "$indie_pe"
  fi
done
find "$indie_stage/bin" "$indie_stage/lib/wine" -type f -print0 | while IFS= read -r -d '' indie_macho; do
  if file "$indie_macho" | grep -q "Mach-O"; then
    /usr/bin/strip -S -x "$indie_macho"
  fi
done
for indie_library in \
  libfreetype.6.20.2.dylib libgmp.10.dylib libnettle.8.9.dylib \
  libhogweed.6.9.dylib libgnutls.30.dylib libinotify.0.dylib libSDL2-2.0.0.dylib; do
  ditto "$indie_dependency_root/lib/$indie_library" "$indie_stage/lib/$indie_library"
done
ln -s libfreetype.6.20.2.dylib "$indie_stage/lib/libfreetype.6.dylib"
ln -s libfreetype.6.dylib "$indie_stage/lib/libfreetype.dylib"
ln -s libgmp.10.dylib "$indie_stage/lib/libgmp.dylib"
ln -s libnettle.8.9.dylib "$indie_stage/lib/libnettle.8.dylib"
ln -s libnettle.8.dylib "$indie_stage/lib/libnettle.dylib"
ln -s libhogweed.6.9.dylib "$indie_stage/lib/libhogweed.6.dylib"
ln -s libhogweed.6.dylib "$indie_stage/lib/libhogweed.dylib"
ln -s libgnutls.30.dylib "$indie_stage/lib/libgnutls.dylib"
ln -s libinotify.0.dylib "$indie_stage/lib/libinotify.dylib"
ln -s libSDL2-2.0.0.dylib "$indie_stage/lib/libSDL2.dylib"

typeset -A indie_library_ids=(
  libfreetype.6.20.2.dylib libfreetype.6.dylib
  libgmp.10.dylib libgmp.10.dylib
  libnettle.8.9.dylib libnettle.8.dylib
  libhogweed.6.9.dylib libhogweed.6.dylib
  libgnutls.30.dylib libgnutls.30.dylib
  libinotify.0.dylib libinotify.0.dylib
  libSDL2-2.0.0.dylib libSDL2-2.0.0.dylib
)
for indie_library in ${(k)indie_library_ids}; do
  install_name_tool -id "@rpath/${indie_library_ids[$indie_library]}" "$indie_stage/lib/$indie_library"
done
find "$indie_stage/bin" "$indie_stage/lib" -type f -print0 | while IFS= read -r -d '' indie_macho; do
  if file "$indie_macho" | grep -q "Mach-O"; then
    for indie_old_dependency in ${(f)$(otool -L "$indie_macho" | awk -v root="$indie_dependency_root/lib/" 'index($1, root) == 1 { print $1 }')}; do
      install_name_tool -change "$indie_old_dependency" "@rpath/${indie_old_dependency:t}" "$indie_macho"
    done
  fi
done
ditto "$indie_wine_source/COPYING.LIB" "$indie_stage/licenses/Wine-LGPL-2.1.txt"
ditto "$indie_freetype_source/LICENSE.TXT" "$indie_stage/licenses/FreeType-License.txt"
ditto "$indie_gmp_source/COPYING.LESSERv3" "$indie_stage/licenses/GMP-LGPL-3.0.txt"
ditto "$indie_nettle_source/COPYING.LESSERv3" "$indie_stage/licenses/Nettle-LGPL-3.0.txt"
ditto "$indie_gnutls_source/LICENSE" "$indie_stage/licenses/GnuTLS-License.txt"
ditto "$indie_inotify_source/LICENSE" "$indie_stage/licenses/libinotify-kqueue-MIT.txt"
ditto "$indie_sdl_source/LICENSE.txt" "$indie_stage/licenses/SDL2-Zlib.txt"
ditto "$indie_root/runtime/indie-wine11/source.lock.json" "$indie_stage/source.lock.json"
print "$indie_runtime_version" > "$indie_stage/runtime-version.txt"

DYLD_LIBRARY_PATH="$indie_stage/lib" "$indie_stage/bin/wine" --version | grep -q "wine-11.0"
# Normalize archive metadata so the same locked sources and toolchain produce
# the same runtime checksum on different developer machines.
find "$indie_stage" -exec touch -h -t 202601130000.00 {} +
(
  cd "$indie_stage_parent"
  find wine-runtime -print0 | LC_ALL=C sort -z | \
    COPYFILE_DISABLE=1 tar -cJf "$indie_archive" \
      --uid 0 --gid 0 --uname root --gname wheel --no-recursion --null -T -
)

indie_archive_size=$(stat -f %z "$indie_archive")
indie_archive_sha256=$(shasum -a 256 "$indie_archive" | awk '{print $1}')
print "构建完成：$indie_archive"
print "SHA-256：$indie_archive_sha256"
print "大小：$indie_archive_size"
