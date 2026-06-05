# Progress — Cyph3rfall

## Shipped

### v1.2 (May 2026) — Current Release
- ✅ Apple Notarized (Developer ID Application: Gregory Stock, GHXKLLWQPM)
- ✅ Default column spacing changed to Wide
- ✅ Density performance warning at >151%
- ✅ Version comparison fix (1.02 no longer sorts above 1.1)
- ✅ Build number removed from About panel
- ✅ Branded DMG (plain, not yet drag-to-Applications styled)

### v1.1 (May 2026)
- ✅ Tabbed settings panel (General / Message / Clock / Import/Export)
- ✅ Auto-update check via GitHub Releases API
- ✅ Settings export/import (JSON)
- ✅ Column spacing control (Wide / Narrow)
- ✅ Clock colour tied to rain preset
- ✅ Chromafall multi-colour mode

### v1.0
- ✅ Matrix rain animation (CVDisplayLink, Core Graphics)
- ✅ 9 colour presets
- ✅ Menu bar app (LSUIElement)
- ✅ Idle activation
- ✅ Sleep/lid-close activation
- ✅ Global hotkey
- ✅ Multi-monitor
- ✅ Password lock (Touch ID / Apple Watch) — BETA
- ✅ Message overlay
- ✅ Clock overlay
- ✅ Launch at login

---

## In Progress

### Performance Optimisation (2026-06) — COMPLETE
- ✅ Glyph atlas (`GlyphAtlas.swift`) — CGImage bitmap blit instead of Core Text per glyph
- ✅ Atlas pre-warmed in `rebuild()` — no cold-start jank on first frame
- ✅ 60fps frame cap (raised from 30fps — 30fps caused judder on high-refresh displays)
- ✅ Glyph mutation rate halved (every 2 ticks)
- ✅ CVDisplayLink leak fixed — CPU now drops to near zero after screensaver dismissal
- ✅ Verified on Mac Mini M4: dual 4K + 1440p, smooth animation, CPU drops on dismiss
- ⬜ Shared display link across views (multi-monitor — deferred, not needed after other fixes)

---

## Backlog (Prioritised)

### 1. Auto-Updater
In-app download + install + restart flow. Version label at top of menu transforms into "Update to vX.X" button when update available. Requires write permission to `/Applications`. Likely uses Sparkle framework (adds a dependency — needs decision).

### 2. UI & Performance Overhaul
Combined task (HIG + settings redesign + full optimisation):
- macOS HIG design pass (developer.apple.com/design)
- Settings redesign: macOS-style sidebar navigation (replaces tab strip), coloured selected item, attached square preview panel
- Optimise for all Apple Silicon: M1, M2, M3, M4, M5
- Shared display link for multi-monitor

### 3. Color Cycle Mode
Slow full-screen palette drift through all 9 presets. Smooth interpolation between head/trail colours. Configurable speed (time-per-colour). Mutually exclusive with Chromafall. Name TBD (candidates: Prismafall, Spectrafall, Driftfall).

### 4. "Start Now" Shortcut Display
Show currently assigned global shortcut right-aligned on the "Start Now" menu item, matching standard macOS menu convention. Blank if no shortcut set.

### 5. Branded DMG Installer
Custom dark background with Cyph3rfall icon + Applications folder alias + arrow/instruction. Replaces current plain DMG.

### 6. Windows Companion App
Tauri (Rust + Web Canvas) stack. Separate repo. Native Windows feel. Feature parity with macOS. After macOS feature set stabilises post v1.3+.

---

## Known Issues / Beta Features

| Item | Status | Notes |
|------|--------|-------|
| Password Lock | BETA | Touch ID / Apple Watch auth working. Codex improved lock arming logic (manual start + idle=0 now locks immediately). More testing needed. |
| Cloudflare Workers | Config present, not deployed | `wrangler.jsonc` merged to main but DNS not pointed at Cloudflare yet. GitHub Pages is live. |
