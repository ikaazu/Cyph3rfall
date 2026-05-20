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
| 💬 Message overlay | A phrase that materialises character-by-character in the rain |
| 🕐 Clock overlay | Time and date with custom font and slow drift |
| 🔒 Password lock | Touch ID / Face ID / Apple Watch to dismiss |
| ⚡️ Optimised rendering | Smooth at 60 fps at maximum density with Chromafall |

## Installation

1. Download `Cyph3rfall-v*.zip` from the [Releases page](https://github.com/ikaazu/Cyph3rfall/releases/latest)
2. Unzip and drag **Cyph3rfall.app** to `/Applications`
3. **Right-click → Open** on first launch to bypass Gatekeeper
4. The **Ξ** icon appears in your menu bar

> **Note:** Cyph3rfall is signed but not notarized through Apple's paid developer program. macOS will show a security prompt on the very first open — right-click the app and choose **Open** to approve it once.

## Requirements

- macOS 14.0 Sonoma or later
- Apple Silicon or Intel

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
