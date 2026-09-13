# 注入技术选型

- [注入技术选型](#注入技术选型)
  - [可行](#可行)
    - [Automatic（cascade）](#automaticcascade)
    - [Post to Process — `CGEvent.postToPid`](#post-to-process--cgeventposttopid)
      - [事件构造要点（已实现）](#事件构造要点已实现)
    - [SkyLight — `SLEventPostToPid`](#skylight--sleventposttopid)
    - [全局 HID — `CGEvent.post(.cghidEventTap)`](#全局-hid--cgeventpostcghideventtap)
    - [场景预期（拖拽中点暂停）](#场景预期拖拽中点暂停)
  - [已评估](#已评估)
    - [`cgSessionEventTap` + warp 回光标](#cgsessioneventtap--warp-回光标)
    - [`CGEventPostToPSN`](#cgeventposttopsn)
    - [窗口字段 91 / 92](#窗口字段-91--92)
    - [SkyLight `SLPSPostEventRecordTo`（focus-without-raise）](#skylight-slpsposteventrecordtofocus-without-raise)
    - [`SLSPostMouseEvent` / auth envelope（macOS 15+）](#slspostmouseevent--auth-envelopemacos-15)
    - [Accessibility `AXPress` / 控件树](#accessibility-axpress--控件树)
    - [AppleScript / System Events `click at`](#applescript--system-events-click-at)
    - [`IOHIDUserDevice` 虚拟键鼠](#iohiduserdevice-虚拟键鼠)
    - [Game Controller 虚拟手柄](#game-controller-虚拟手柄)
    - [进程内 Hook（PlayCover 式）](#进程内-hookplaycover-式)
    - [向自身 `NSApp.sendEvent`](#向自身-nsappsendevent)
    - [更深的 CoreGraphics 私有 `_CGEventPostToPID`](#更深的-coregraphics-私有-_cgeventposttopid)

核心诉求：在尽量不移动系统光标、不打断进行中拖拽的前提下，向目标窗口指定坐标注入单击。Escape / 类 Android「返回」的键盘动作仍属于未来扩展。macOS 上合成输入通道有限，没有对所有游戏都成立的「不挪光标点击」银弹；产品采用分层注入，并按本机能力禁用不可用选项。

## 可行

### Automatic（cascade）

普通目标在事件创建或投递失败时依次尝试：`postToPid` → SkyLight → HID。被启发式识别为 iOS-on-Mac 或 Unity 的目标直接走 HID。注意「API 已 posted」不等于目标一定消费事件，因此这不是基于目标响应的可靠降级。

### Post to Process — `CGEvent.postToPid`

公开 API（10.11+）。把事件送进指定进程队列，不走全局 HID，不 warp 光标。

- 键盘：当前运行时尚未实现键盘动作注入；Escape / 「返回」类需求保留为未来扩展。
- 鼠标：AppKit / 多数原生窗体可用；Unity、Blender、画布类常整段过滤 per-PID。
- Chromium：外层进程可能收到，渲染进程常当 untrusted 丢掉。
- macOS 26 上 Safari WebKit 有「调用成功、内容无反应」的报告，需按版本探测与降级。

权限：Accessibility；沙盒应关闭。

#### 事件构造要点（已实现）

1. **NSEvent → cgEvent 提取**：用 `NSEvent.mouseEvent(with:…)` 构造后取 `.cgEvent`，自动填充 12 个内部字段（41=sourcePID, 43/44=user/groupID, 50/51/55/59/102/108 等私有常量），让事件与真实用户点击高度一致。
2. **显式字段写入**：
   - field 3 (`kCGMouseEventButtonNumber`) = `0`（左键）
   - field 7 (`kCGMouseEventSubtype`) = `3`（Chromium 信任的 subtype，不设则渲染进程 IPC 边界丢弃）
   - field 91 (`kCGMouseEventWindowUnderMousePointer`) = 目标 `CGWindowID`
   - field 92 (`…ThatCanHandleThisEvent`) = 同上
3. **`CGEventSetWindowLocation`**：`dlsym(RTLD_DEFAULT, "CGEventSetWindowLocation")` 拿到私有 setter，传入窗口本地坐标（屏幕 Quartz 点减去窗口 Quartz origin）。告诉 WindowServer 点击在窗口内的精确位置。
4. **`maskCommand` 后台旁路**：当目标 `NSRunningApplication.isActive == false` 时，设 `event.flags = .maskCommand`（`0x00100000`）。这是 WindowServer 过滤绕过，**不是** `kCGEventFlagMaskNonCoalesced`（`0x100`），两者易混淆。

### SkyLight — `SLEventPostToPid`

私有：`dlopen` SkyLight + `dlsym`。C ABI 与公开 API 相同：`SLEventPostToPid(pid_t, CGEventRef)`（**不是** `(event, pid)`；参数反了会 `EXC_BAD_ACCESS`，崩溃地址≈pid）。

在本项目测试过的 macOS 版本上，`SLEventPostToPid` 与 `CGEventPostToPid` 的行为相同。因此「SkyLight 模式」本身不会比 Post to Process 更强；Electron/Chromium 能否点上，取决于事件字段是否像真鼠标（`mouseEventSubtype=3`、窗口 91/92、`CGEventSetWindowLocation` 等），而不是换一个符号名。

- 不解决 Unity / 多数游戏：canvas/game 常整类忽略 per-PID；当前实现会将启发式识别出的这类目标直接交给 HID（会动光标）。
- 风险：符号/ABI 变更；必须软失败。

### 全局 HID — `CGEvent.post(.cghidEventTap)`

游戏 / Metal 画布兼容底线。可选前置 `mouseMoved`，事后 `CGWarpMouseCursorPosition` 拉回光标。

代价：光标会短暂到点击点；进行中的 drag 极易被打断；warp 恢复仍可能被引擎感知。设置里应标明该限制。

### 场景预期（拖拽中点暂停）

若目标消费 per-PID / SkyLight 鼠标事件，可做到不挪光标且尽量保留拖拽。若目标对 per-PID 事件兼容性较差（常见于 Unity / 部分 Metal 游戏），自动模式会根据启发式识别直接使用 HID，拖拽可能被打断。工程上依赖按应用探测与分层回退，而不是赌某一个私有 SPI。

## 已评估

以下手段已调研，不作为产品主路径；部分仅作事件字段或能力探测辅助。

### `cgSessionEventTap` + warp 回光标

早期 PoC 基线，已从代码移除。对游戏弱，且 warp 干扰拖拽。

### `CGEventPostToPSN`

公开但已弃用；等价能力用 `postToPid`。

### 窗口字段 91 / 92

公开字段，可绑定 window id，属于事件 enrichment。不能让游戏接受它本来就忽略的投递通道。产品内已在 postToPid / SkyLight / HID 三条路径上填充。配合 `CGEventSetWindowLocation` 提供窗口本地坐标，可提高 AppKit / Chromium 目标的兼容性，但不保证目标接受事件。

### SkyLight `SLPSPostEventRecordTo`（focus-without-raise）

yabai 模式：翻转 AppKit 激活态但不 raise 窗口。可作为未来「不抢前台」路由的辅助，本身不是点击通道；当前实现未依赖它。

### `SLSPostMouseEvent` / auth envelope（macOS 15+）

与 `SLEventPostToPid` 同族增强。macOS 14 上需 `responds(to:)` / selector 探测后再用，否则可能崩。能力探测可展示，投递层尚未默认依赖。

### Accessibility `AXPress` / 控件树

适合系统 / AppKit / Electron 控件。游戏多为单一 Metal 表面，树为空，不适合坐标点击主路径。

### AppleScript / System Events `click at`

仍走系统指针语义，无法满足「拖拽中不挪鼠标」。

### `IOHIDUserDevice` 虚拟键鼠

非 PID 定向，权限与信任成本高，坐标点击不干净。

### Game Controller 虚拟手柄

无法向第三方进程注入 GC 事件；仅当游戏本身读 GC 才有意义。

### 进程内 Hook（PlayCover 式）

改目标进程输入栈，属于另一架构。Arkeys 是进程外注入，只复用其 keymap 文件格式。

### 向自身 `NSApp.sendEvent`

只能喂给本进程，对第三方无效。

### 更深的 CoreGraphics 私有 `_CGEventPostToPID`

没有比公开 `postToPid`「对游戏明显更强」的稳定私有变体可依赖。
