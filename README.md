<p align="center">
  <img src="Assets/appicon.png" width="160" alt="Arkeys">
</p>

<h1 align="center">Arkeys</h1>

<p align="center">
  <a href="./README.md">English</a> · <a href="./README.zh.md">简体中文</a>
</p>

- [Features](#features)
- [Requirements](#requirements)
- [Permissions](#permissions)
    - [Enable Accessibility](#enable-accessibility)
- [Install](#install)
    - [From a release](#from-a-release)
    - [From source](#from-source)
- [Get started](#get-started)
- [Uninstall](#uninstall)
- [Injection](#injection)
    - [Automatic](#automatic)
    - [Post to Process](#post-to-process)
    - [SkyLight](#skylight)
    - [Global HID](#global-hid)

A macOS accessibility utility that maps keyboard shortcuts to mouse clicks **inside a target app’s window**, without moving the system cursor. Arkeys is an **out-of-process** injector. It does not modify the target app. Shortcuts fire only while the chosen app is frontmost.

## Features

- Menu-bar agent (no Dock icon by default); settings open from the status item
- Overlay editor: place buttons on the target window and assign keys
- Supports import / export of PlayCover `.plist` / `.playmap` schemes
- Multiple schemes per target app; switch from Settings or the menu
- Layered injection: Automatic, Post to Process, SkyLight, or Global HID

## Requirements

- macOS 15.4 or later
- Xcode 16 or later, if you build from source

## Permissions

Arkeys is **not sandboxed**. It needs system trust to listen for keys and to post clicks into another process.

- Accessibility
    - Required
    - Global shortcut listening (`NSEvent`), posting clicks / keys into the target, reading window frames via Accessibility APIs
- Input Monitoring
    - Optional
    - Only if Accessibility is already on but **Event Tap** in Settings → Compatibility is still off. Some macOS versions route keyboard event-tap probes through this permission

### Enable Accessibility

1. Launch Arkeys. macOS may show **Accessibility Access**.
2. Open **System Settings → Privacy & Security → Accessibility**.
3. Enable **Arkeys**. If it is already listed but off, turn it on. If a rebuild changed the signature, remove the old entry, then add the new `Arkeys.app`.
4. In Arkeys: **Settings → Compatibility → Refresh**. Accessibility should read **On**.

You can jump to the pane from **Settings → Compatibility → Grant Permission**.

Without Accessibility, shortcuts will not fire and injection will fail.

## Install

### From a release

1. Download the latest build from [Releases](https://github.com/palmcivet/Arkeys/releases).
2. Move `Arkeys.app` to `/Applications`.
3. Open it. A menu-bar icon appears.
4. If Gatekeeper blocks the app: Control-click the icon and choose **Open**, or allow it under **System Settings → Privacy & Security**.

### From source

```bash
git clone https://github.com/palmcivet/Arkeys.git
cd Arkeys
open Arkeys.xcodeproj
```

In Xcode, select the **Arkeys** scheme and **Product → Run** (debug) or **Product → Archive** then export the app.

Local or ad-hoc signed builds are a new binary to TCC. Re-grant Accessibility if listening or injection stops working.

## Get started

1. Click the menu-bar icon → **Settings…** (or **Arkeys → Settings…** when the app is focused).
2. **General**: turn **Enabled** on, then **Choose App…** and pick the running target. Shortcuts apply only while that app is frontmost.
3. **Keymap**: **Import** a PlayCover scheme, or **New** and **Edit** to place keys on the overlay.
4. **Compatibility**: confirm Accessibility, then leave the route on **Automatic (Recommended)** unless a specific mode works better for your target.
5. Switch back to the target app and press a bound key.

PlayCover-style iOS-on-Mac apps often ignore per-process mouse events. If clicks never land, switch the route to **Global HID** (the cursor may move briefly; an in-progress drag can be interrupted).

## Uninstall

Quit Arkeys from the menu-bar item, then delete the app:

```text
/Applications/Arkeys.app
```

Deleting the app does **not** remove settings, keymaps, or system permissions. To remove everything, also delete:

```text
~/Library/Application Support/Arkeys/
~/Library/Preferences/palmcivet.arkeys.plist
```

Then open **System Settings → Privacy & Security** and remove **Arkeys** from **Accessibility** (and **Input Monitoring**, if you added it).

## Injection

Settings automatically disables routes that the current system cannot use. A successful API post does not guarantee the target will consume the event.

### Automatic

**Mechanism:** `postToPid` → SkyLight → HID

Picks the best available method for this Mac and target. Prefer this for everyday use.

### Post to Process

**Mechanism:** Public `CGEvent.postToPid`

Posts into the target process without a global HID move or cursor warp. Works for many native macOS apps. Chromium web content, Unity, and many canvas-based apps often drop these mouse events.

### SkyLight

**Mechanism:** Private `SLEventPostToPid` (`dlsym`)

Same family as `postToPid` on current macOS. Does not beat Unity / most game input filters. The symbol exists only on supported OS versions.

### Global HID

**Mechanism:** `CGEvent.post(.cghidEventTap)`, optionally a `mouseMoved` first, then warp the cursor back.

System-wide HID mouse events. Most compatible with games and iOS-on-Mac, but the cursor jumps to the click point and drags can break. Some engines still notice the warp.
