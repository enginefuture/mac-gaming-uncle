# 测试指南

## 自动化

```bash
scripts/check.sh
```

该命令运行 Swift 单元测试、Release 构建以及四个 Windows 测试程序的交叉编译。当前测试覆盖：

- 模型 JSON 往返、SemVer、SQLite 持久化；
- Ed25519 Manifest 验签、渲染器优先级、内核反作弊阻断；
- VDF、Steam AppManifest、PE 架构/DirectX/反作弊分析；
- 内置配方的加载和身份优先级；
- GPTK 下载监测、D3DMetal 缓存指纹与自动失效；
- Steam CEF 修复、登录状态解析、中文字体与 UE 参数顺序。
- Indie Wine 11 Manifest、本地运行时安装，以及 D3DMetal 原生库/PE Bridge 路径不会被 LaunchPlan 覆盖。

## Apple Silicon 硬件矩阵

在 M 系列真机上按顺序执行：

1. `indie-smoke-x64.exe`：验证 Rosetta、Wine 64 位、窗口和输入。
2. `indie-smoke-x86.exe`：验证新 WoW64 和 32 位窗口。
3. `indie-d3d11-fixture.exe`：先使用 DXMT，再验证 D3DMetal 与 WineD3D 回退。
4. `indie-d3d12-fixture.exe`：必须使用用户导入的 D3DMetal。
5. Steam：使用 Indie Wine 11 登录，扫描 `steamapps`，验证 AppID、名称、BuildID 和多库路径。
6. 一款用户拥有、无内核级反作弊的游戏持续运行 30 分钟，记录 Runtime、Renderer、系统版本和退出状态。

## 失败矩阵

必须验证：损坏哈希/签名、非 Apple GPTK、双层 DMG 中断、错误 DLL Overlay、磁盘不足、中文/空格路径、外置盘、Bottle 并发锁、Wine 非零退出、快照回退和离线启动。

正式发布不能要求 `sudo`、关闭 SIP/Gatekeeper，或对用户目录执行递归 quarantine 清除。
