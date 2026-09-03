<div align="center">
  <img src="Assets/IndieIcon.png" width="144" alt="Indie 图标">
  <h1>Indie</h1>
  <p><strong>在 Apple Silicon Mac 上运行你拥有的 Windows 游戏。</strong></p>
  <p>原生 SwiftUI · Wine · Apple D3DMetal · MetalFX · DXVK</p>
  <p><a href="README.en.md">English</a> · 简体中文</p>
</div>

> [!IMPORTANT]
> Indie 是开源兼容性研究项目，不是虚拟机，也不包含 Windows、Steam、游戏或 Apple D3DMetal。Apple 组件只能由用户从 Apple 官方开发者页面获取并在本机导入。

## 项目状态

Indie 目前处于 `0.1.0` 研究预览阶段，面向 Apple Silicon 与 macOS 15 及以上版本。应用已经打通环境准备、Windows 版 Steam 安装、Steam 游戏扫描和 D3DMetal 启动闭环。

实机验证环境：Apple M3 Max、macOS 26.6.2、GPTK 4.0 beta 2、Sikarugir Wine 10。`Ruins of Dawn` 已验证进入主菜单并启用 Steam 集成。

## 已实现

- 原生 SwiftUI/AppKit 界面，全中文新手引导。
- 从 Valve 官方 CDN 下载并安装 Windows 版 Steam。
- 打开 Apple 官方下载页，监测 GPTK 4 下载并自动完成 DMG、SHA-256 与 Apple 签名验证。
- 导入完整 D3DMetal framework、Wine PE Bridge 与 Unix Bridge，不重新分发 Apple 二进制。
- 安装固定版本和哈希的 Sikarugir Wine 游戏运行时与 DXVK macOS Overlay。
- Steam CEF 兼容包装器、中文字体注册与 DirectWrite 字体链接。
- 等待 Steam 登录后解析并启动真实的 `*-Win64-Shipping.exe`。
- 按 GPTK 版本、安装包哈希、MetalFX、DXR、Metal 4、macOS 和游戏参数管理着色器缓存。
- Steam AppID/EXE 双重匹配的可审计游戏配方系统。
- PE 架构、DirectX 导入和反作弊静态检测；内核级反作弊会在启动前阻断。
- SQLite 状态存储、Bottle 隔离、可恢复备份、CLI 诊断和 30 项自动化测试。

## 工作原理

```text
Windows 游戏
     │
     ├─ Win32 / Win64 API ───────────────→ Wine
     ├─ x86_64 指令 ─────────────────────→ Rosetta 2
     └─ Direct3D 11 / 12 ─→ D3DMetal ───→ Metal
                           └→ DXVK/MoltenVK（回退路径）

Steam AppManifest → 游戏扫描 → 兼容配方 → 不可变 LaunchPlan → 独立 Bottle
```

Indie 负责组合、验证和启动这些层。它不会修改游戏内容，也不会绕过 DRM、授权或反作弊。

## 快速开始

### 要求

- Apple Silicon Mac
- macOS 15 或更高版本
- Xcode 26，或兼容 Swift 6 的完整开发工具链
- 用于首次获取 D3DMetal 的 Apple Developer 登录
- 合法拥有的 Steam 账户和游戏

### 从源码构建

```bash
git clone https://github.com/enginefuture/indie.git
cd indie
scripts/build-app.sh
open dist/Indie.app
```

开发构建使用 ad-hoc 签名。正式分发时设置 Developer ID：

```bash
INDIE_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  scripts/build-app.sh
```

### 第一次使用

1. 点击“一键准备环境”，安装开源 Wine 运行环境。
2. 点击“一键安装 GPTK 4”。Indie 会打开 Apple 官方页面；用户登录并点击下载后，其余验证和导入自动完成。
3. 点击“安装 Steam”，在 Wine 安装窗口中完成 Windows 版 Steam 安装并登录。
4. 从 Steam 安装游戏，返回 Indie 的“游戏库”并点击“扫描 Steam”。
5. 点击游戏旁的“D3DMetal 启动”。首次图形缓存构建可能需要几分钟。

MetalFX/DLSS 映射是实验功能且默认关闭。只有游戏本身提供 DLSS 时才可能生效；遇到黑屏或 GPU Timeout 时应保持关闭。

## 开发与测试

```bash
swift test
swift build -c release
swift run indiectl --json doctor
scripts/check.sh
```

常用 CLI：

```text
indiectl doctor
indiectl pe <game.exe>
indiectl steam-scan <steamapps-directory>
indiectl recipes validate <recipes-directory>
indiectl gptk import <apple-gptk.dmg|mounted-directory>
indiectl wine latest
indiectl wine gaming-install
indiectl dxvk install <bottle-root>
indiectl steam repair <bottle-root> [wrapper.exe]
indiectl fonts repair <bottle-root> <runtime-root>
```

更多资料：

- [架构说明](docs/ARCHITECTURE.md)
- [运行时供应链](docs/RUNTIME_SUPPLY_CHAIN.md)
- [测试指南](docs/TESTING.md)
- [第三方声明](THIRD_PARTY_NOTICES.md)

## 兼容性边界

- Wine 是兼容层，不是安全沙箱；Windows 进程仍以当前 macOS 用户权限运行。
- 内核级反作弊、Windows 驱动、UWP、部分 DRM 和依赖 AVX-512 的程序通常无法运行。
- 32 位游戏、D3D9/10/11、启动器和视频播放的兼容性仍因游戏而异。
- D3DMetal、Steam 和游戏受各自条款约束，本仓库不提供这些二进制文件。
- Indie 不隶属于 Apple、Valve、CodeWeavers 或任何游戏发行商。

## 参与贡献

欢迎提交可复现的兼容性报告、游戏配方、测试和代码改进。Issue 请至少包含：Mac 型号、macOS 版本、GPTK/D3DMetal 版本、Steam AppID、启动参数以及去除个人信息后的相关日志。

请勿提交游戏文件、账户凭据、Apple 下载介质、D3DMetal 二进制或用于绕过 DRM/反作弊的内容。

## 许可证

Indie 源代码使用 [Apache License 2.0](LICENSE)。第三方组件继续受各自许可证或使用条款约束，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
