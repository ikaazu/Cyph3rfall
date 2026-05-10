# Cyph3rfall: Ambient Digital Rain for macOS

**Version 1.0** · Developed by Greg Stock · © 2026 Greg Stock

---

## Overview

Cyph3rfall is a lightweight macOS menu bar application that fills your screen with a mesmerizing cascade of falling glyphs — half-width katakana, digits, letters, and symbols — inspired by the iconic digital rain effect from *The Matrix* (1999, dir. Lana & Lilly Wachowski) and the Windows screensaver *MatrixMania*.

Unlike traditional macOS screensavers, Cyph3rfall runs as a native menu bar agent. It activates automatically after a configurable idle period, covers every connected display simultaneously, and dismisses instantly on any input. No screensaver frameworks, no sandboxing workarounds — just clean, fast, ambient rain.

---

## Features

### Menu Bar Agent
Cyph3rfall lives quietly in your menu bar as a **Ξ** icon. It has no Dock presence and no floating windows — just a single click to access everything. It can be configured to launch automatically at login.

### Idle Activation
The app monitors system idle time and activates after a user-defined period of inactivity. Choose from:

| Timeout | Description |
|---------|-------------|
| Never | Manual activation only |
| 1 Minute | |
| 2 Minutes | |
| 5 Minutes | Default |
| 10 Minutes | |
| 15 Minutes | |
| 30 Minutes | |

### Multi-Monitor Support
When activated, Cyph3rfall covers **every connected display** simultaneously with independent, live rain animations — each screen gets its own full-screen rendering pass.

### Instant Dismiss
Move the mouse, press any key, or click anywhere to instantly dismiss the rain and return to your desktop.

### Start Now
Trigger the rain immediately from the menu bar dropdown or directly from the Settings panel — no need to wait for idle timeout.

### Launch at Login
Register Cyph3rfall as a login item directly from the menu. macOS will start it automatically in the background every time you log in.

### Single Instance Enforcement
Cyph3rfall automatically detects and terminates any previously running instance before starting, so you never end up with duplicate icons or conflicting animations.

---

## Settings

Open settings at any time via **⌘,** or by clicking **Settings…** in the menu bar dropdown. All settings include a **live preview** panel that updates in real time as you make changes.

### Speed
Controls how fast the glyph columns fall.

| Option | Multiplier |
|--------|------------|
| Slow | 0.5× |
| Normal | 1.0× |
| Fast | 2.0× |

### Density
A continuous slider from **10% to 500%** controlling how many glyph streams appear on screen simultaneously.

- **10–50%** — Sparse, atmospheric, wide gaps between streams
- **85–100%** — Classic Matrix look, one stream per column
- **100–200%** — Dense overlap, ~50% of screen covered at any time
- **200–500%** — Maximum chaos, wall-to-wall cascading glyphs

### Glyph Size
| Option | Size |
|--------|------|
| Small | 10 pt |
| Normal | 16 pt |
| Large | 22 pt |

### Color
Nine colour presets, each with a distinct trail colour and a brighter, tinted head glyph:

| Preset | Trail | Head |
|--------|-------|------|
| Green | Matrix green | Pale green-white |
| Amber | Warm gold | Cream |
| Cyan | Electric cyan | Ice blue-white |
| White | Silver-grey | Pure white |
| Purple | Deep amethyst | Soft lavender |
| Blue | Electric blue | Light sky blue |
| Red | Neon crimson | Blush pink |
| Orange | Vivid orange | Warm cream |
| Pink | Hot magenta | Soft blush |

### Glow
When enabled, the leading glyph of each stream is rendered with a soft shadow glow matching the current colour preset. Creates a phosphor-screen aesthetic.

### Classic Dense Mode
Overrides density and trail length to replicate the look of classic Matrix screensavers — maximum density, short trails, and elevated speed. The fastest, most compact presentation of the rain.

---

## Glyph Set

The rain draws from a pool of **95 characters**:

- **Half-width katakana** (U+FF65–FF9F) — 58 characters
- **Digits** — 0–9
- **Uppercase Latin** — A–Z
- **Symbols** — `! @ # $ % & * + - = < > ?`

Each column independently randomises its glyph sequence, speed, trail length, and brightness — giving the rain an organic, living quality. Individual glyphs mutate every frame, and the leading glyph occasionally flashes white-hot for a brief burst.

---

## Technical Details

| Detail | Value |
|--------|-------|
| Platform | macOS 14.0 Sonoma and later |
| Language | Swift 5 |
| Framework | AppKit |
| Rendering | Core Graphics via NSView (CVDisplayLink) |
| Settings storage | `~/Library/Application Support/MatrixRainSaver/` |
| Bundle ID | `com.cyph3rfall.Cyph3rfall` |
| Dock visibility | Hidden (LSUIElement agent) |

---

## Installation

1. Copy **Cyph3rfall.app** to `/Applications`
2. Launch it — the **Ξ** icon appears in the menu bar
3. Click **Ξ → Launch at Login** to register it as a startup item
4. Optionally, disable the system screensaver: **System Settings → Lock Screen → Start Screen Saver when inactive → Never**

---

## Credits

Built with Swift & AppKit
Inspired by *The Matrix* (1999, dir. Lana & Lilly Wachowski) & *MatrixMania* for Windows
No screensaver frameworks were harmed.
