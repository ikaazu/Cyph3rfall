# Cyph3rfall

**Ambient Digital Rain for macOS** — a native menu bar app that fills every screen with cascading Matrix-style glyphs.

🌐 **[cyph3rfall.app](https://cyph3rfall.app)** &nbsp;·&nbsp; 📦 **[Latest Release](https://github.com/ikaazu/Cyph3rfall/releases/latest)**

---

## What it is

Cyph3rfall lives in your menu bar and activates after a configurable idle timeout, covering every connected display with falling half-width katakana, digits, letters, and symbols. Dismiss with any mouse or keyboard input — or require Touch ID / Apple Watch authentication first.

Built entirely with Swift and AppKit. No third-party dependencies, no screensaver framework workarounds.

## Features

| | |
|---|---|
| ☰ Menu bar agent | No Dock icon — always accessible via the Ξ icon |
| ⏱ Idle activation | Configurable timeout: 1 min to 30 min, or never |
| ⌨️ Global shortcut | System-wide hotkey to launch from any app |
| 🖥 Multi-monitor | Covers every display with smooth fade in/out |
| 🎨 9 colour presets | Green, Amber, Cyan, White, Purple, Blue, Red, Orange, Pink |
| 🌈 Chromafall | Per-stream random colours, re-randomised on each wrap |
| 🌅 Spectrafall | Full-screen palette drift through all colour presets, smooth interpolation, configurable speed |
| 💬 Message overlay | A phrase that materialises character-by-character in the rain |
| 🕐 Clock overlay | Time and date with custom font, size, and slow drift |
| 🔒 Password lock | Touch ID / Face ID / Apple Watch to dismiss — a casual privacy lock, not a security boundary |
| ⚡️ Optimised rendering | Smooth at 60 fps at maximum density with Chromafall |
| 🗂️ Tabbed settings | General, Message, Clock, and Import/Export tabs with live preview |
| ⬛️ Column spacing | Wide or Narrow — Narrow packs columns 25% closer for denser rain |
| 🎨 Clock colour presets | Optionally tie the clock colour to your active rain preset |
| 💾 Settings backup | Export and import your configuration as a JSON file |
| 🔄 Auto update check | Checks GitHub for new releases on launch; manual check in About |

## Installation

1. Download `Cyph3rfall-v*.zip` from the [Releases page](https://github.com/ikaazu/Cyph3rfall/releases/latest)
2. Unzip and drag **Cyph3rfall.app** to `/Applications`
3. Launch it — the **Ξ** icon appears in your menu bar

> **Note:** macOS may show a security prompt on the very first launch. If it does, right-click the app and choose **Open** to approve it once.

## Requirements

- macOS 14.0 Sonoma or later
- Apple Silicon or Intel

## Tested on

| Device | Displays | Notes |
|--------|----------|-------|
| MacBook Pro M5 | Built-in display | Primary development machine |
| Mac Mini M4 | 4K + 1440p high-refresh (dual display) | Performance and multi-monitor testing |

Smooth 60 fps on both machines across single and dual-display configurations including high-refresh rate monitors.

## Building from source

```bash
git clone https://github.com/ikaazu/Cyph3rfall.git
cd Cyph3rfall
xcodegen generate
open Cyph3rfall.xcodeproj
```

Select the **Cyph3rfall** scheme and press **⌘R**.

## The story

Cyph3rfall was conceived and directed by Greg Stock — not a software developer — in close collaboration with **Claude Code** by Anthropic. Every feature was described in plain language and implemented iteratively through conversation. It is a work in progress, and that's the point.

## Credits

Inspired by *The Matrix* (1999) and MatrixMania for Windows by StrongGames.  
Built with Swift & AppKit · [cyph3rfall.app](https://cyph3rfall.app)
