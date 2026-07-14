# Striker

- [Striker](#striker)
  - [Requirements](#requirements)
  - [Technical Approach](#technical-approach)
    - [Automatic](#automatic)
    - [Post to Process](#post-to-process)
    - [SkyLight](#skylight)
    - [Global HID](#global-hid)

A macOS utility that lets you trigger mouse clicks inside a target application's window using keyboard shortcuts—without moving the cursor. It also supports importing key mappings from tools such as PlayCover.

## Requirements

- macOS 14 or later
- Accessibility permission: **System Settings → Privacy & Security → Accessibility** → enable **Striker**.

## Technical Approach

### Automatic

**Mechanism:** `postToPid` → SkyLight → HID

Automatically selects the best available event injection method based on what is supported by the current system. Keep in mind that successfully posting an event does not guarantee that the target application will process it.

### Post to Process

**Mechanism:** Public `CGEvent.postToPid`

Uses the public Core Graphics API to post events directly to the target process. This works well for many standard macOS applications, but mouse events are frequently ignored by Chromium web content, Unity, and other canvas-based applications.

### SkyLight

**Mechanism:** Private `SLEventPostToPid` (resolved via `dlsym`)

Uses the private SkyLight API to deliver events to the target process. This approach does not overcome the input filtering used by Unity or most games, and the required symbol is only available on supported macOS versions.

### Global HID

**Mechanism:** `CGEvent.post(.cghidEventTap)`, optionally preceded by `mouseMoved` and followed by restoring the cursor position with a warp.

Generates system-wide HID mouse events. While effective in some cases, it can interrupt drag operations, and some applications or game engines may still detect the temporary cursor movement even after it is restored.

Methods that are not supported on the current system are automatically disabled in *Settings*.
