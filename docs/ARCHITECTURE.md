# Indie 架构

## 数据流

```text
用户导入 EXE / Steam AppManifest
        │
        ▼
PEAnalyzer + SteamScanner ──→ GameRecord(SQLite)
        │
        ▼
RecipeRepository ──→ RendererResolver ──→ immutable LaunchPlan
        │                                      │
        │                                      ▼
Indie Wine 11 Manifest ──→ WineRuntimeProvider / Subprocess
                                               │
                    ┌──────────┬───────────┬────┴─────┐
                    ▼          ▼           ▼          ▼
                D3DMetal     DXMT        DXVK      WineD3D
                    └──────────┴────→ Metal ←─────────┘
```

`IndieCore` 只包含模型、路径和 SQLite 状态；`IndieCatalog` 负责无副作用的识别与配方；`IndieRuntime` 是所有外部进程、运行时、Bottle 和图形组件的边界；GUI 与 CLI 都调用同一套模块。

默认宿主是 Indie 从公开对应源码构建的 Wine 11，而不是 CrossOver.app 的封装。D3DMetal 是用户从 Apple 下载后本地导入的独立渲染器：Wine 11 的 `WINEDLLPATH_PREPEND` 补丁把其 PE Bridge 放在内置 WineD3D 之前，`libd3dshared.dylib` 则通过单独的原生动态库路径加载。Steam 客户端本身使用软件 CEF/WineD3D，登录完成后游戏才按配方切换图形后端。

## 核心约束

- `LaunchProfile` 是用户偏好，`LaunchPlan` 是解析后的不可变执行事实。日志永远引用 Plan ID，从而可复现问题。
- Runtime 和 Renderer Overlay 安装到版本目录，不原地升级；更新通过暂存、验证、原子移动完成。
- Steam 使用商店级 Bottle；本地 EXE 默认一游戏一 Bottle。当前 UI 已实现 Steam 安装、登录检测、游戏扫描和两阶段启动闭环。
- 配方顺序为精确 Steam AppID、EXE 文件名、静态分析默认。用户覆盖将在后续 UI 中置于配方之前。
- Stable Manifest 必须签名；手动 Wine 导入只进入 Experimental 通道。

## 渲染选择

| 输入 | 默认顺序 |
|---|---|
| 64 位 D3D12 | D3DMetal → experimental VKD3D |
| D3D10/11 | DXMT → D3DMetal → DXVK → WineD3D |
| D3D9 | WineD3D → DXVK |
| 旧 2D/未知 | WineD3D |

内核级反作弊在生成 LaunchPlan 前阻断。32 位可执行文件不会选择 D3DMetal。

## 数据目录

`~/Library/Application Support/Indie` 下分为 `Runtimes`、`ImportedComponents`、`Overlays`、`Bottles`、`Recipes`、`ShaderCaches`、`ShaderCacheBackups`、`Logs` 和 `Downloads`。D3DMetal 缓存按渲染器版本、源镜像哈希、图形选项、macOS 和配方参数建立指纹；变化时旧缓存会移动到可恢复备份。数据库只保存元数据；账户密码由 Steam/Wine 自己管理。
