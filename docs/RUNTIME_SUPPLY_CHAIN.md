# 运行时供应链

## 正式运行时

正式 Wine 制品必须从 WineHQ 或 CodeWeavers 发布的 LGPL 对应源码构建，不从不明网盘或现有应用包中提取。每个 Release 同时发布：

- 源码 URL、精确 commit/tag、Mac Gaming Uncle 补丁集和完整构建命令；
- x86_64 macOS Wine 制品、SHA-256、体积与最低 macOS；
- SPDX/CycloneDX SBOM、第三方许可证、动态链接依赖清单；
- Ed25519 签名的 `RuntimeManifest`；
- DXMT 所需 `winemac.drv` 导出符号验证结果、新 WoW64 和 MSync 冒烟测试。

Manifest Schema 位于 `Schemas/runtime-manifest.schema.json`。签名内容是移除 `signature` 字段后，通过 `IndieJSON` sorted-keys 编码得到的字节。Release 私钥不得进入仓库或 CI 日志；客户端只内置公钥。

当前研究预览默认使用 `scripts/build-indie-wine11.sh` 生成的 Mac Gaming Uncle Wine 11 运行时。输入锁定为 CodeWeavers CrossOver 26.3.0 对应 FOSS 源码包（其中 Wine 为 11.0）、Nettle 3.10、SDL2 2.32.10 官方源码和仓库内的三项可审计补丁；不从 CrossOver 应用程序中提取或分发任何二进制。运行时包含新 WoW64、MSync、FreeType、GnuTLS、GMP、Nettle 与 SDL2 winebus 手柄桥接，不包含 D3DMetal。Release URL、体积和 SHA-256 固定在 `CommunityIndieWineBootstrapper` 中，安装前逐项验证。

仓库补丁实现两项原本由产品集成层完成的功能：移除专有 `cxcompatdb.so` 加载入口；让开源 Wine 的加载器原生读取 `WINEDLLPATH_PREPEND`，从而在内置 Wine DLL 之前选择用户本机导入的 D3DMetal Wine Bridge。Steam WebHelper 的 CEF 参数兼容由仓库内可重编译的小型 wrapper 完成。上述实现不复制 CodeWeavers 专有模块。

## D3DMetal

D3DMetal 不进入 Git、Release、缓存服务器或 Runtime Manifest。导入器只接受用户选择的 Apple GPTK：

1. 先用 `hdiutil verify` 校验镜像，再以 `hdiutil attach -readonly -nobrowse` 挂载外层 DMG；
2. 必要时继续挂载其中的 Windows Evaluation Environment DMG；
3. 找到 `D3DMetal.framework`、`libd3dshared.dylib` 和 GPTK 4 的完整 Wine Bridge；
4. `codesign --verify --deep --strict`，并检查 Apple 证书链与 D3DMetal 标识；
5. 记录版本、源镜像 SHA-256、导入时间并原子写入用户私有目录；
6. 无论成功失败都卸载临时 Volume。

在公开发布前仍需对所使用 GPTK 版本的最终许可证文本进行法律复核；代码层面保持“用户提供、仅本地导入、从不再分发”的边界。

## 开源图形层

DXMT、DXVK 和 VKD3D 以独立 Overlay 存放，不能修改已安装 Runtime。导入时检查其关键 DLL；正式 Catalog 还必须提供哈希、源码与许可证。MoltenVK 的 Vulkan 能力不是完全等同于原生 Vulkan，因此 DXVK/VKD3D 始终作为回退或实验路径。

## 签名与公证

取得 Developer ID 后，`scripts/build-app.sh` 使用 `INDIE_CODESIGN_IDENTITY` 签名。正式流水线必须启用 Hardened Runtime、执行 `notarytool submit --wait`、`stapler staple`、`spctl --assess`，再生成 DMG。主应用不申请 JIT 或关闭 Library Validation；若 Wine 运行时确需例外，只对 Wine 可执行文件使用经测试的最小 entitlement。
