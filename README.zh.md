<p align="center">
  <img src="Assets/appicon.png" width="160" alt="Arkeys">
</p>

<h1 align="center">Arkeys</h1>

<p align="center">
  <a href="./README.md">English</a> · <a href="./README.zh.md">简体中文</a>
</p>

- [功能](#功能)
- [系统要求](#系统要求)
- [需要启用的权限](#需要启用的权限)
    - [打开辅助功能](#打开辅助功能)
- [安装](#安装)
    - [从 Release 安装](#从-release-安装)
    - [从源码编译](#从源码编译)
- [开始使用](#开始使用)
- [卸载](#卸载)
- [注入方式](#注入方式)
    - [自动](#自动)
    - [按进程投递](#按进程投递)
    - [SkyLight](#skylight)
    - [全局 HID](#全局-hid)

macOS 辅助工具：用键盘快捷键在**目标应用窗口内**触发鼠标点击，尽量不移动系统光标。Arkeys 是**进程外**注入，不会改目标应用。快捷键仅在所选应用位于前台时生效。

## 功能

- 菜单栏常驻（默认不占 Dock），从状态栏图标打开设置
- 覆盖层编辑器：在目标窗口上摆放按钮并绑定按键
- 支持导入 / 导出 PlayCover 的 `.plist` / `.playmap` 方案
- 同一目标应用可保存多套方案，设置或菜单里切换
- 分层注入：自动、按进程投递、SkyLight、全局 HID

## 系统要求

- macOS 15.4 或更高版本
- 从源码编译需要 Xcode 16 或更高版本

## 需要启用的权限

Arkeys **未启用沙盒**。监听按键、向其他进程投递点击，都需要系统授权。

- 辅助功能
    - 必须
    - 全局快捷键监听（`NSEvent`）、向目标投递点击/按键、通过辅助功能 API 读取窗口位置
- 输入监控
    - 可选
    - 仅当已打开辅助功能，但「设置 → 兼容性」里 **事件监听** 仍为关时再考虑。部分系统上键盘 Event Tap 探测会走这项

### 打开辅助功能

1. 启动 Arkeys。系统可能会弹出 **辅助功能访问** 提示。
2. 打开 **系统设置 → 隐私与安全性 → 辅助功能**。
3. 勾选 **Arkeys**。若已在列表里但是关闭的，打开即可。本地重新编译后签名可能变化：先删掉旧条目，再添加新的 `Arkeys.app`。
4. 回到 Arkeys：**设置 → 兼容性 → 刷新**。辅助功能应显示为 **开**。

也可以直接点 **设置 → 兼容性 → 授予权限** 跳到系统面板。

未授予辅助功能时，快捷键不会触发，注入也会失败。

## 安装

### 从 Release 安装

1. 到 [Releases](https://github.com/palmcivet/Arkeys/releases) 下载最新构建。
2. 将 `Arkeys.app` 拖到 `/Applications`。
3. 打开应用，菜单栏会出现图标。
4. 若被 Gatekeeper 拦截：按住 Control 点击图标选择 **打开**，或在 **系统设置 → 隐私与安全性** 中允许。

### 从源码编译

```bash
git clone https://github.com/palmcivet/Arkeys.git
cd Arkeys
open Arkeys.xcodeproj
```

在 Xcode 中选择 **Arkeys** scheme，**Product → Run** 调试运行，或 **Product → Archive** 后导出应用。

本地 / 临时签名的构建会被 TCC 当成新二进制。若监听或点击突然失效，请重新授予辅助功能。

## 开始使用

1. 点击菜单栏图标 → **设置…**（应用在前台时也可以用 **Arkeys → 设置…**）。
2. **常规**：打开 **启用**，再点 **选择应用…**，选中正在运行的目标。快捷键只在该应用位于前台时生效。
3. **键鼠方案**：**导入** PlayCover 方案，或 **新建** 后 **编辑**，在覆盖层上摆放按键。
4. **兼容性**：确认辅助功能已开，注入方式建议保持 **自动（推荐）**，除非某个模式对当前目标更稳。
5. 切回目标应用，按下已绑定的键。

PlayCover 这类 iOS-on-Mac 应用常常忽略按进程投递的鼠标事件。若完全点不上，把注入方式改成 **全局 HID**（光标可能短暂跳动，进行中的拖拽可能被打断）。

## 卸载

先从菜单栏退出 Arkeys，再删除应用：

```text
/Applications/Arkeys.app
```

只删 `.app` **不会**清掉设置、键位方案和系统授权。如需彻底移除，一并删除：

```text
~/Library/Application Support/Arkeys/
~/Library/Preferences/palmcivet.arkeys.plist
```

然后打开 **系统设置 → 隐私与安全性**，从 **辅助功能** 中移除 **Arkeys**（若曾勾选 **输入监控**，一并去掉）。

## 注入方式

当前系统不支持的方式会在设置里自动禁用。「API 已投递成功」不等于目标应用一定会处理该事件。

### 自动

**机制：** `postToPid` → SkyLight → HID

按本机能力和目标自动选择。日常使用优先选这项。

### 按进程投递

**机制：** 公开 API `CGEvent.postToPid`

把事件送进目标进程，不走全局 HID、不挪光标。多数原生 macOS 应用可用。Chromium 网页内容、Unity 以及不少画布类应用常会丢掉这类鼠标事件。

### SkyLight

**机制：** 私有 `SLEventPostToPid`（`dlsym` 解析）

在当前 macOS 上与 `postToPid` 同族。不能突破 Unity / 多数游戏的输入过滤。所需符号仅在受支持的系统版本上存在。

### 全局 HID

**机制：** `CGEvent.post(.cghidEventTap)`，可选先发 `mouseMoved`，再 warp 光标回原位。

系统级 HID 鼠标事件。对游戏和 iOS-on-Mac 兼容最好，但光标会跳到点击点，拖拽容易被打断。部分引擎仍能察觉 warp。
