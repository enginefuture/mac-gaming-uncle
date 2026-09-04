<div align="center">
  <img src="Assets/MacGamingUncleIcon.png" width="144" alt="Mac Gaming Uncle 图标">
  <h1>Mac Gaming Uncle</h1>
  <p><strong>在 Apple Silicon Mac 上运行你拥有的 Windows 游戏。</strong></p>
  <p>原生 SwiftUI · Wine · Apple D3DMetal · MetalFX · DXVK</p>
  <p><a href="README.en.md">English</a> · 简体中文</p>
</div>

<p align="center">
  <img src="Assets/MacGamingUncleHero.png" width="100%" alt="叔叔没有选错，只是选得太早。">
</p>

> [!IMPORTANT]
> Mac Gaming Uncle 是开源兼容性研究项目，不是虚拟机，也不包含 Windows、Steam、游戏或 Apple D3DMetal。Apple 组件只能由用户从 Apple 官方开发者页面获取并在本机导入。

## 为什么做这个项目

过去，“用 Mac 玩游戏”常被当成一句调侃。我们想把它变成一件普通而简单的事：安装应用、登录 Steam、下载游戏、点击开始。用户不应该先学会 Wine、Bottle、图形转译和启动参数，才有资格玩自己已经购买的游戏。

Mac Gaming Uncle 的长期目标，是在 Mac 上提供接近 SteamOS 的体验——由系统吸收兼容层的复杂度，让游戏安装、配置、更新和启动尽可能自动完成。它不是 SteamOS 的移植，也不隶属于 Valve；我们学习的是它“把复杂技术藏在简单体验之后”的产品方向。

### 永久非商业化承诺

Mac Gaming Uncle 官方项目和官方发行将永久保持非商业化：不推出收费版、订阅、广告、付费兼容名单、游戏抽成或用户数据交易。兼容配方、问题记录和关键实现继续公开，项目的成功标准是让更多 Mac 用户更容易玩到自己合法拥有的游戏，而不是收入。

> 本承诺约束官方项目的运营方向。源代码继续使用 Apache License 2.0；该开源许可证允许第三方在遵守许可证的前提下使用和再分发代码，官方项目不会借“非商业化”之名限制正常的开源协作。

## 项目状态

Mac Gaming Uncle 目前处于 `0.1.0` 研究预览阶段，面向 Apple Silicon 与 macOS 15 及以上版本。应用已经打通环境准备、Windows 版 Steam 安装、Steam 游戏扫描和 D3DMetal 启动闭环。

实机验证环境：Apple M3 Max、macOS 26.6.2、GPTK 4.0 beta 2、Mac Gaming Uncle Wine 11.0.1。`Grim Dawn 1.3.0.8 (x64)` 已验证完整中文 UI、Steam 集成与 Apple 官方 Metal HUD（D3D11，实测约 114 FPS）；`Ruins of Dawn` 已验证进入主菜单。

## 已实现

- 原生 SwiftUI/AppKit 界面，全中文新手引导。
- 从 Valve 官方 CDN 下载并安装 Windows 版 Steam。
- 打开 Apple 官方下载页，监测 GPTK 4 下载并自动完成 DMG、SHA-256 与 Apple 签名验证。
- 导入完整 D3DMetal framework、Wine PE Bridge 与 Unix Bridge，不重新分发 Apple 二进制。
- 从公开对应源码构建并安装 Mac Gaming Uncle Wine 11（GCC 15 MinGW、新 WoW64、MSync、Steam CEF 补丁与原生 D3DMetal Bridge 路径）。
- Steam CEF 兼容包装器、中文字体注册与 DirectWrite 字体链接。
- 解析目标 x64/`*-Win64-Shipping.exe`，再通过 Steam `-applaunch` 创建游戏进程，保证 SteamAPI、渲染器和 HUD 环境完整继承。
- D3DMetal 原生 PE Bridge 按版本安装到 Bottle，覆盖前自动备份；Steam 更新覆盖 CEF 包装器后会在下次启动自动修复。
- 按 GPTK 版本、安装包哈希、MetalFX、DXR、Metal 4、macOS 和游戏参数管理着色器缓存。
- Steam AppID/EXE 双重匹配的可审计游戏配方系统。
- PE 架构、DirectX 导入和反作弊静态检测；内核级反作弊会在启动前阻断。
- Apple Metal Performance HUD：由同一个 Mac Gaming Uncle Wine 11 游戏进程启用，直接显示在游戏画面内。
- SQLite 状态存储、Bottle 隔离、可恢复备份、CLI 诊断和自动化测试。

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

Mac Gaming Uncle 负责组合、验证和启动这些层。它不会修改游戏内容，也不会绕过 DRM、授权或反作弊。

## 快速开始

### 要求

- Apple Silicon Mac
- macOS 15 或更高版本
- Xcode 26，或兼容 Swift 6 的完整开发工具链
- 用于首次获取 D3DMetal 的 Apple Developer 登录
- 合法拥有的 Steam 账户和游戏

### 从源码构建

```bash
git clone https://github.com/enginefuture/mac-gaming-uncle.git
cd mac-gaming-uncle
scripts/build-app.sh
open "dist/Mac Gaming Uncle.app"
```

生成经过挂载验证的 DMG：

```bash
scripts/build-dmg.sh
```

当前开源研究预览使用 ad-hoc 签名，尚未公证。若 Gatekeeper 阻止打开，从 GitHub Release 下载并确认来源后可执行：

```bash
xattr -dr com.apple.quarantine "/Applications/Mac Gaming Uncle.app"
```

开发构建使用 ad-hoc 签名。正式分发时设置 Developer ID：

```bash
MAC_GAMING_UNCLE_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  scripts/build-app.sh
```

### 第一次使用

1. 点击“一键准备环境”，安装 Mac Gaming Uncle 自行构建的开源 Wine 11 运行环境。
2. 点击“一键安装 GPTK 4”。Mac Gaming Uncle 会打开 Apple 官方页面；用户登录并点击下载后，其余验证和导入自动完成。
3. 点击“安装 Steam”，在 Wine 安装窗口中完成 Windows 版 Steam 安装并登录。
4. 从 Steam 安装游戏，返回 Mac Gaming Uncle 的“游戏库”并点击“扫描 Steam”。
5. 点击游戏旁的“智能启动”。Mac Gaming Uncle 会按游戏配方选择 D3DMetal、DXMT 或 WineD3D；首次图形缓存构建可能需要几分钟。

MetalFX/DLSS 映射是实验功能且默认关闭。只有游戏本身提供 DLSS 时才可能生效；游戏配方可以强制禁用它。`Grim Dawn` 不使用 DLSS，Mac Gaming Uncle 会忽略全局 MetalFX 开关，避免 NVNGX 显卡伪装导致 UI 消失。

“优先使用 Metal 4”默认开启，但会先通过当前 `MTLDevice` 查询硬件和系统支持；不支持时自动回退，个别游戏异常时也可在高级设置中手动关闭。D3DMetal 版本、游戏 Direct3D 版本和 Metal 提交路径是三个不同维度，例如 HUD 显示 `Game Porting Toolkit 4.0b2 · D3D11` 完全正常。

“显示 Apple Metal HUD”会经 Steam 把 Apple HUD 环境变量传给目标游戏；不切换到 Apple Evaluation Wine，也不会跳过 Steam。HUD 只会在实际使用 D3DMetal 或 DXMT 的游戏中出现。`Grim Dawn 1.3` 配方优先选择 x64 主程序与 D3DMetal 4，按 Mac 屏幕的逻辑点尺寸同步游戏分辨率，并自动备份 `options.txt`、启用经典 HUD；该游戏还会关闭 MSync 与 Steam Overlay，避免 UI 漏绘和鼠标命中区域错位。

## 开发与测试

```bash
swift test
swift build -c release
swift run macgamingunclectl --json doctor
scripts/check.sh
scripts/build-indie-wine11.sh
```

常用 CLI：

```text
macgamingunclectl doctor
macgamingunclectl pe <game.exe>
macgamingunclectl steam-scan <steamapps-directory>
macgamingunclectl recipes validate <recipes-directory>
macgamingunclectl gptk import <apple-gptk.dmg|mounted-directory>
macgamingunclectl wine latest
macgamingunclectl wine gaming-install
macgamingunclectl wine local-install <runtime-root>
macgamingunclectl dxvk install <bottle-root>
macgamingunclectl dxmt install
macgamingunclectl steam repair <bottle-root> [wrapper.exe]
macgamingunclectl fonts repair <bottle-root> <runtime-root>
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
- Mac Gaming Uncle 不隶属于 Apple、Valve、CodeWeavers 或任何游戏发行商。

## 参与贡献

欢迎提交可复现的兼容性报告、游戏配方、测试和代码改进。Issue 请至少包含：Mac 型号、macOS 版本、GPTK/D3DMetal 版本、Steam AppID、启动参数以及去除个人信息后的相关日志。

请勿提交游戏文件、账户凭据、Apple 下载介质、D3DMetal 二进制或用于绕过 DRM/反作弊的内容。

## 许可证

Mac Gaming Uncle 源代码使用 [Apache License 2.0](LICENSE)。第三方组件继续受各自许可证或使用条款约束，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
