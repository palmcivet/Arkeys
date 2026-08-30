# Arkeys 本地存储

用户设置与键鼠方案均落在 macOS Application Support，不经 iCloud / 沙盒容器。

根目录：

```text
~/Library/Application Support/Arkeys/
  settings.json
  Keymaps/
    {bundleID}/
      manifest.json
      {schemeID}.json
```

`bundleID` 路径段会把 `/` 替换为 `_`，避免非法路径。

## 全局设置 — `settings.json`

由 `AppSettingsStore`（KeymapCore）读写。启动时 `InputRuntime` 恢复；开关 / 注入模式 / 目标变更时写回。

| 字段 | 含义 |
|------|------|
| `lastTargetBundleID` | 上次绑定的目标应用 |
| `lastTargetAppName` | 显示名缓存 |
| `isEnabled` | 总开关 |
| `injectModeRaw` | `InjectMode.rawValue`（字符串，避免 KeymapCore 依赖 Injection） |
| `preferMouseMovedBeforeHID` | HID 路径是否先 `mouseMoved` |
| `restoreCursorAfterHID` | HID/session 注入后是否 warp 回光标 |

示例：

```json
{
  "isEnabled": true,
  "injectModeRaw": "postToPid",
  "lastTargetAppName": "SomeGame",
  "lastTargetBundleID": "com.example.game",
  "preferMouseMovedBeforeHID": true,
  "restoreCursorAfterHID": true
}
```

## 键鼠方案 — 按目标应用、多方案

模型：**一个目标 App（bundle id）下可有多套方案**；任一时刻只有一套 `active`。导入 / 新建追加新方案并设为 active；切换只改 active，不删其他。

### 目录与文件

```text
Keymaps/{bundleID}/
  manifest.json          # 方案列表 + activeSchemeID
  {schemeID}.json        # CanonicalKeymap 正文（UUID 文件名）
```

实现：`KeymapStore`（KeymapCore）。

### `manifest.json`

```json
{
  "activeSchemeID": "A1B2C3D4-...",
  "schemes": [
    {
      "id": "A1B2C3D4-...",
      "name": "PlayCover 导入",
      "updatedAt": "2026-07-13T05:00:00Z"
    },
    {
      "id": "E5F6...",
      "name": "未命名方案",
      "updatedAt": "2026-07-13T05:10:00Z"
    }
  ]
}
```

- `KeymapSchemeMeta`：`id`、`name`、`updatedAt`（ISO8601）
- `activeSchemeID` 指向当前运行 / 编辑的方案；删除 active 时自动切到列表第一项（若还有）

### `{schemeID}.json`

内容为规范模型 `CanonicalKeymap`（元素、键码、相对坐标、来源元数据等）。编辑器与运行时只认此模型；PlayCover 等格式仅在导入/导出时经 parser 转换。

## 运行时关系

```text
ContentView / Tray（未来）
        │
        ▼
  InputRuntime          ← 内存态：target、schemes、activeSchemeID、keymap、设置
        │
        ├── AppSettingsStore → settings.json
        └── KeymapStore      → Keymaps/{bundleID}/…
```

典型动作：

| 动作 | 行为 |
|------|------|
| 绑定目标 | 读该 bundle 的 manifest，加载 active 方案到 `keymap` |
| 新建方案 | `create` → 写新 `{uuid}.json` + 更新 manifest，设为 active，可进入编辑 |
| 导入 PlayCover | 解码为 `CanonicalKeymap` 后 `create`（名称默认用文件名） |
| 切换方案 | `setActive` + 加载对应 JSON |
| 编辑保存 | 覆盖当前 `schemeID` 的 JSON，刷新 `updatedAt` |
| 删除方案 | 删 JSON，从 manifest 移除；若删的是 active 则切换或清空 |

## 相关代码

| 组件 | 路径 |
|------|------|
| `KeymapStore` / meta / manifest | `Packages/KeymapCore/.../KeymapStore.swift` |
| `AppSettings` / `AppSettingsStore` | `Packages/KeymapCore/.../AppSettingsStore.swift` |
| `CanonicalKeymap` | `Packages/KeymapCore/.../CanonicalKeymap.swift` |
| 运行时编排 | `Packages/InputRuntime/.../InputRuntime.swift` |
| 设置 UI（方案 Picker） | `Arkeys/Settings/KeymapSettingsView.swift` |
