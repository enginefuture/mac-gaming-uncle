<div align="center">
  <img src="Assets/MacGamingUncleIcon.png" width="144" alt="Mac Gaming Uncle 图标">
  <h1>Mac Gaming Uncle</h1>
  <p><strong>在 Apple Silicon Mac 上运行你拥有的 Windows 游戏。</strong></p>
  <p>原生 SwiftUI · Wine · Apple D3DMetal · MetalFX · DXVK</p>
  <p><a href="https://github.com/enginefuture/mac-gaming-uncle/releases/download/v0.3.0/Mac-Gaming-Uncle-0.3.0-macOS-arm64.dmg">下载 0.3.0 DMG</a> · <a href="https://github.com/enginefuture/mac-gaming-uncle/releases/tag/v0.3.0">版本说明</a></p>
  <p><a href="README.md">English</a> · 简体中文</p>
</div>

<p align="center">
  <img src="Assets/MacGamingUncleHero.png" width="100%" alt="叔叔没有选错，只是选得太早。">
</p>

> [!IMPORTANT]
> Mac Gaming Uncle 是开源兼容性研究项目，不是虚拟机。应用包不包含 Windows、Steam、游戏或 Apple D3DMetal。首次引导通过独立 R2 下载通道自动获取原始 GPTK 镜像并验证、导入；Apple 组件保留原始许可，按非商业条款分发。详见 [GPTK 下载说明](docs/GPTK_DISTRIBUTION.md)。

## 新手下载安装指南

普通用户只需下载安装包，不需要编程、Xcode 或自行编译。

### 1. 确认你的 Mac 可以使用

点击屏幕左上角 ** → 关于本机**：需要 Apple Silicon（M 系列芯片）和 **macOS 15 或更高版本**，暂不支持 Intel Mac。准备好网络连接和自己的 Steam 账户，并为运行组件和要安装的游戏预留磁盘空间。

### 2. 下载应用安装包

点击 **[下载 Mac Gaming Uncle 0.3.0（DMG）](https://github.com/enginefuture/mac-gaming-uncle/releases/download/v0.3.0/Mac-Gaming-Uncle-0.3.0-macOS-arm64.dmg)**。

也可以打开 [Release 页面](https://github.com/enginefuture/mac-gaming-uncle/releases/tag/v0.3.0)，在 **Assets（资源）** 中选择 `Mac-Gaming-Uncle-0.3.0-macOS-arm64.dmg`。不要选择 `Source code`、`.sha256` 或 Wine 的 `.tar.xz`：它们分别是源码、校验文件和由应用自动安装的运行时。

### 3. 安装到“应用程序”并打开

1. 在 Finder 的“下载”目录中双击刚下载的 `.dmg`。
2. 将 **Mac Gaming Uncle** 图标拖到窗口中的 **Applications（应用程序）** 文件夹图标上，等待复制完成。
3. 从 Finder 的“应用程序”中打开 **Mac Gaming Uncle**，不要一直从 DMG 窗口运行。
4. 安装完成后，可以在 Finder 侧栏推出安装磁盘。

当前是尚未公证的研究预览版。如果 macOS 提示无法验证开发者，先确认安装包来自上面的官方仓库；决定信任该来源后，在尝试打开应用后前往 **系统设置 → 隐私与安全性 → 安全性 → 仍要打开**，按提示确认。具体界面以 [Apple 官方说明](https://support.apple.com/zh-cn/102445) 为准。若提示包含恶意软件或文件已损坏，请先停止安装、重新下载并反馈，不要关闭系统安全保护。

### 4. 选择界面语言，等待环境安装并登录 Steam

应用默认跟随系统语言，支持英文和简体中文，其他系统语言使用英文。在引导卡片或 **高级设置 → 偏好设置** 的 **Language / 语言** 中选择 **System / 跟随系统**、**English** 或 **简体中文**，重新打开应用后生效。该设置会改变应用界面和请求的商店文本，不会修改已运行游戏或 Steam 客户端的语言。

第一次打开时会自动出现两步引导：

1. **安装游戏环境**：自动检查并安装 Rosetta、Wine、手柄及图形组件。保持应用打开并等待；出错时查看卡片提示，点击“重试并继续”，已完成的组件会保留。
2. **登录 Steam**：环境就绪后，应用自动安装并更新 Windows 版 Steam，随后打开 Steam 官方登录窗口。使用手机 Steam 扫码，或输入 Steam 账号、密码及所需验证码。此窗口单独出现是正常现象。

首次 Steam 客户端更新可能需要几分钟。登录成功后，回到 Mac Gaming Uncle，应用会自动同步游戏库。Mac 上已有的原生 Steam 登录不等于这里的 Windows Steam 已登录。

### 5. 安装并开始游戏

打开顶部 **游戏库**，选择自己拥有的游戏，点击 **安装**，按 Steam 提示完成下载。安装完成后点击 **开始游戏**。在“商店”浏览或看到某款游戏并不代表已经拥有它，需要先在 Steam 获得相应授权。

第一次游玩先保留默认配置；需要调整分辨率、HUD 或手柄时，再打开 **游戏设置**。手柄请先与 macOS 连接，再到顶部手柄入口检查。首次游戏启动可能需要构建图形缓存，请耐心等待。能显示在游戏库中不代表该游戏已验证兼容。

### 遇到问题怎么办

| 现象 | 可以这样处理 |
| --- | --- |
| 已登录，但主页或游戏库还是空的 | 等待 Steam 写入账户缓存，再点主页“同步游戏库”或游戏库“刷新”；确认登录的是本应用打开的 Windows Steam。当前列表依赖 Steam 本地缓存，可能不是账户全部已购游戏。 |
| 安装组件失败 | 检查网络、磁盘空间和卡片错误信息，再点“重试并继续”。 |
| 游戏启动失败或画面异常 | 记录游戏名称、错误提示和所用图形后端，到 [Issues](https://github.com/enginefuture/mac-gaming-uncle/issues) 反馈。不要附上密码、验证码或登录文件。 |
| 想升级应用 | 先退出游戏和 Mac Gaming Uncle，再下载新 DMG，将应用拖入“应用程序”并选择替换；不要删除应用数据目录，已有组件和游戏可继续保留。 |

退出 Mac Gaming Uncle 会联动退出其管理的 Steam。请先保存并退出游戏，再关闭应用。

## 为什么做这个项目

过去，“用 Mac 玩游戏”常被当成一句调侃。我们想把它变成一件普通而简单的事：安装应用、登录 Steam、下载游戏、点击开始。用户不应该先学会 Wine、Bottle、图形转译和启动参数，才有资格玩自己已经购买的游戏。

Mac Gaming Uncle 的长期目标，是在 Mac 上提供接近 SteamOS 的体验——由系统吸收兼容层的复杂度，让游戏安装、配置、更新和启动尽可能自动完成。它不是 SteamOS 的移植，也不隶属于 Valve；我们学习的是它“把复杂技术藏在简单体验之后”的产品方向。

### 永久非商业化承诺

Mac Gaming Uncle 官方项目和官方发行将永久保持非商业化：不推出收费版、订阅、广告、付费兼容名单、游戏抽成或用户数据交易。兼容配方、问题记录和关键实现继续公开，项目的成功标准是让更多 Mac 用户更容易玩到自己合法拥有的游戏，而不是收入。

> 本承诺约束官方项目的运营方向。源代码继续使用 Apache License 2.0；该开源许可证允许第三方在遵守许可证的前提下使用和再分发代码，官方项目不会借“非商业化”之名限制正常的开源协作。

## 项目状态

Mac Gaming Uncle 目前处于 `0.3.0` 研究预览阶段，面向 Apple Silicon 与 macOS 15 及以上版本。应用已经打通 Steam 客户端式外壳、原生商店与游戏库、每游戏独立配置、全局 Steam 会话以及 SDL/XInput 手柄启动闭环。

实机验证环境：Apple M3 Max、macOS 26.6.2、GPTK 4.0 beta 2、Mac Gaming Uncle Wine 11.0.2。`Grim Dawn 1.3.0.8 (x64)` 已验证完整中文 UI、Steam 集成、XInput 手柄与 Apple 官方 Metal HUD（D3D11，实测约 114 FPS）；`Ruins of Dawn` 已验证进入主菜单。

## 实际界面

以下截图来自 Mac Gaming Uncle 0.2.0 实机运行界面。

<table>
  <tr>
    <td width="50%"><strong>主页与最近游戏</strong><br><a href="docs/screenshots/0.2.0/home.png"><img src="docs/screenshots/0.2.0/home.png" width="100%" alt="Mac Gaming Uncle 主页"></a></td>
    <td width="50%"><strong>原生 Steam 商店</strong><br><a href="docs/screenshots/0.2.0/store.png"><img src="docs/screenshots/0.2.0/store.png" width="100%" alt="Mac Gaming Uncle 原生 Steam 商店"></a></td>
  </tr>
  <tr>
    <td width="50%"><strong>账户游戏库与游戏详情</strong><br><a href="docs/screenshots/0.2.0/library.png"><img src="docs/screenshots/0.2.0/library.png" width="100%" alt="Mac Gaming Uncle 游戏库"></a></td>
    <td width="50%"><strong>从游戏库进入独立设置</strong><br><a href="docs/screenshots/0.2.0/library-settings-entry.png"><img src="docs/screenshots/0.2.0/library-settings-entry.png" width="100%" alt="Mac Gaming Uncle 游戏设置入口"></a></td>
  </tr>
  <tr>
    <td width="50%"><strong>每游戏独立设置</strong><br><a href="docs/screenshots/0.2.0/per-game-settings.png"><img src="docs/screenshots/0.2.0/per-game-settings.png" width="100%" alt="Mac Gaming Uncle 每游戏独立设置"></a></td>
    <td width="50%"><strong>手柄中心</strong><br><a href="docs/screenshots/0.2.0/controller-center.png"><img src="docs/screenshots/0.2.0/controller-center.png" width="100%" alt="Mac Gaming Uncle 手柄中心"></a></td>
  </tr>
</table>

## 已实现

- 原生 SwiftUI/AppKit 中英文界面，覆盖首次引导、游戏设置、手柄管理、诊断及状态和错误提示。
- 像素游戏品牌视觉：疲惫胡子叔叔应用图标、手柄上的完整苹果标记，以及启动按钮的透明像素苹果；无咬痕或播放三角形。
- 顶层导航聚焦主页、商店和游戏库；手柄、下载与运行环境作为辅助工具，不设置独立社区频道。
- Steam 客户端式外壳：原生商店首页/分类/搜索、账户游戏库、封面详情、安装和启动均在同一窗口完成。
- 商店公开浏览无需网页登录；愿望单、购买和账户操作才进入明确标识的 `store.steampowered.com` 安全页面，不复制 Steam CEF 的加密登录 Cookie。
- 账户游戏库直接读取本机 Steam `localconfig.vdf` 的 AppID、游玩时长和最近记录；不读取或上传认证令牌，并在本地缓存官方商店元数据。
- 从 Valve 官方 CDN 下载并安装 Windows 版 Steam。
- 从项目的 Cloudflare R2 下载 GPTK 4 原始镜像，自动完成大小、SHA-256、DMG 与 Apple 签名验证。
- 导入完整 D3DMetal framework、Wine PE Bridge 与 Unix Bridge，原始镜像和许可独立保留。
- 从公开对应源码构建并安装 Mac Gaming Uncle Wine 11（GCC 15 MinGW、新 WoW64、MSync、SDL2 winebus/XInput、Steam CEF 补丁与原生 D3DMetal Bridge 路径）。
- Steam CEF 兼容包装器、中文字体注册与 DirectWrite 字体链接。
- 解析目标 x64/`*-Win64-Shipping.exe`，再通过 Steam `-applaunch` 创建游戏进程，保证 SteamAPI、渲染器和 HUD 环境完整继承。
- 全局 Steam 会话会保持登录并在兼容配置相同时直接复用；只有渲染器、HUD、同步方式或虚拟桌面发生冲突时才安全重启。
- D3DMetal 原生 PE Bridge 按版本安装到 Bottle，覆盖前自动备份；Steam 更新覆盖 CEF 包装器后会在下次启动自动修复。
- 按 GPTK 版本、安装包哈希、MetalFX、DXR、Metal 4、macOS 和游戏参数管理着色器缓存。
- Steam AppID/EXE 双重匹配的可审计游戏配方系统。
- PE 架构、DirectX 导入和反作弊静态检测；内核级反作弊会在启动前阻断。
- Apple Metal Performance HUD：由同一个 Mac Gaming Uncle Wine 11 游戏进程启用，直接显示在游戏画面内。
- 每游戏独立配置：固定虚拟桌面分辨率、渲染后端、同步方式、Metal HUD、MetalFX、Metal 4 与启动参数分别持久化，Steam 重新扫描后仍会保留。
- 独立“手柄中心”：搜索蓝牙手柄、查看设备/电量/能力、分配玩家编号、实时测试输入与震动，并可按游戏启用 SDL HIDAPI 增强兼容。
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
- 可访问组件下载服务器的网络连接
- 合法拥有的 Steam 账户和游戏

### 从源码构建

以下仅供开发者使用，需要 Xcode 26 或兼容 Swift 6 的完整开发工具链。普通用户请按上方“新手下载安装指南”安装 DMG。

不需要开发环境时，可直接下载经过挂载和签名结构验证的 [Mac Gaming Uncle 0.3.0 DMG](https://github.com/enginefuture/mac-gaming-uncle/releases/download/v0.3.0/Mac-Gaming-Uncle-0.3.0-macOS-arm64.dmg)，并用同目录的 [SHA-256 文件](https://github.com/enginefuture/mac-gaming-uncle/releases/download/v0.3.0/Mac-Gaming-Uncle-0.3.0-macOS-arm64.dmg.sha256) 校验。

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

### 游戏设置说明

MetalFX/DLSS 映射是实验功能且默认关闭。只有游戏本身提供 DLSS 时才可能生效；游戏配方可以强制禁用它。`Grim Dawn` 不使用 DLSS，Mac Gaming Uncle 会忽略全局 MetalFX 开关，避免 NVNGX 显卡伪装导致 UI 消失。

“优先使用 Metal 4”默认开启，但会先通过当前 `MTLDevice` 查询硬件和系统支持；不支持时自动回退，个别游戏异常时也可在高级设置中手动关闭。D3DMetal 版本、游戏 Direct3D 版本和 Metal 提交路径是三个不同维度，例如 HUD 显示 `Game Porting Toolkit 4.0b2 · D3D11` 完全正常。

“显示 Apple Metal HUD”会经 Steam 把 Apple HUD 环境变量传给目标游戏；不切换到 Apple Evaluation Wine，也不会跳过 Steam。HUD 只会在实际使用 D3DMetal 或 DXMT 的游戏中出现。`Grim Dawn 1.3` 配方优先选择 x64 主程序与 D3DMetal 4，按 Mac 屏幕的逻辑点尺寸同步游戏分辨率，并自动备份 `options.txt`、启用经典 HUD与原生手柄支持；该游戏还会关闭 MSync 与 Steam Overlay，避免 UI 漏绘和鼠标命中区域错位。

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
