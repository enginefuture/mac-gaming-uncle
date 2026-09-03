# Indie Wine 11 patch set

These patches are applied, in lexical order, to the Wine tree in CodeWeavers'
published CrossOver 26.3.0 corresponding-source archive. That tree reports
Wine 11.0 and contains the LGPL macOS driver, MSync, new WoW64, and the public
D3DMetal integration hooks. Indie does not copy binaries from CrossOver.app.

1. `0001-allow-d3dmetal-build-without-vulkan.patch` keeps the public D3DMetal
   integration buildable when the optional Vulkan backend is disabled.
2. `0002-remove-proprietary-compatdb-loader.patch` removes the optional runtime
   lookup for CodeWeavers' closed `cxcompatdb.so` product module.
3. `0003-native-winedllpath-prepend.patch` implements the required DLL search
   precedence directly in Wine: paths in `WINEDLLPATH_PREPEND` are searched
   before Wine's built-in DLL directory. This lets a user-imported Apple
   D3DMetal PE/Unix bridge load without the proprietary compatibility database.

Steam's current CEF process flags are handled outside Wine by the auditable
wrapper in `RuntimeSupport/SteamWebHelperWrapper`.

The exact source URLs and checksums are in
`runtime/indie-wine11/source.lock.json`. Run `scripts/build-indie-wine11.sh`
to verify the archives, apply this series, build all open-source dependencies,
and create the redistributable runtime archive.
