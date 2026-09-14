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
    - [Homebrew](#homebrew)
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
    - Global shortcut listening (`NSEvent`), posting clicks into the target, and reading window frames via Accessibility APIs
- Input Monitoring
    - Optional
    - May be required when the **Event Tap** capability check in Settings → Compatibility is unavailable. The Event Tap row is a status indicator, not a user-configurable switch; some macOS versions route keyboard event-tap probes through this permission

### Enable Accessibility

1. Launch Arkeys. macOS may show **Accessibility Access**.
2. Open **System Settings → Privacy & Security → Accessibility**.
3. Enable **Arkeys**. If it is already listed but off, turn it on. If a rebuild changed the signature, remove the old entry, then add the new `Arkeys.app`.
4. In Arkeys: **Settings → Compatibility → Refresh**. Accessibility should read **On**.

You can jump to the pane from **Settings → Compatibility → Grant Permission**.

Without Accessibility, shortcuts will not fire and injection will fail.

## Install

### Homebrew

```bash
brew install --cask palmcivet/tap/arkeys
```

If Gatekeeper blocks the app on first launch: Control-click the icon and choose **Open**, or allow it under **System Settings → Privacy & Security**.

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

Download or copy the [uninstall script](./Scripts/uninstall.sh), then run:

```bash
./uninstall.sh
```

The script quits Arkeys, deletes `Arkeys.app` from Applications, and removes the files this project actually writes:

```text
~/Library/Application Support/Arkeys/
~/Library/Preferences/palmcivet.arkeys.plist
```

Preview first with `--dry-run`. Other options:

- `--yes` skip confirmation
- `--keep-app` reset data only

If `tccutil` cannot clear TCC automatically, remove **Arkeys** from **System Settings → Privacy & Security → Accessibility**.

## Injection

Settings automatically disables routes that the current system cannot use. A successful API post does not guarantee the target will consume the event.

### Automatic

**Mechanism:** target-aware, availability-based cascade

For ordinary targets, Arkeys tries `postToPid`, then SkyLight, then Global HID only when the current route reports failure. Targets detected as iOS-on-Mac or Unity go directly to Global HID because those targets often ignore per-process events. Arkeys cannot tell whether a target consumed a successfully posted event, so this is not a guaranteed response-based fallback. Prefer this for everyday use.

### Post to Process

**Mechanism:** Public `CGEvent.postToPid`

Posts into the target process without a global HID move or cursor warp. Works for many native macOS apps. Chromium web content, Unity, and many canvas-based apps often drop these mouse events.

### SkyLight

**Mechanism:** Private `SLEventPostToPid` (`dlsym`)

On the macOS versions tested by this project, it behaves like `postToPid`. It does not reliably bypass Unity or most game input filters. The symbol exists only on supported OS versions, so Arkeys probes it and soft-fails when unavailable.

### Global HID

**Mechanism:** `CGEvent.post(.cghidEventTap)`, optionally a `mouseMoved` first, then warp the cursor back.

System-wide HID mouse events. Most compatible with games and iOS-on-Mac, but the cursor jumps to the click point and drags can break. Some engines still notice the warp.
