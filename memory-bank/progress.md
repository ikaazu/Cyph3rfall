# Progress — Cyph3rfall

## Shipped

### v1.4.1 (June 2026) — Current Release
- ✅ Spectrafall colour cycle mode (8 presets in hue order, 3 speeds, starts from active preset)
- ✅ Password lock hardening — fails closed, stale LAContext invalidated on sleep/wake
- ✅ Settings General tab scrollable (accommodates growing row count)
- ✅ Fix: Message and Clock tab content anchored to top (FlippedClipView)
- ✅ Font name validation on settings import
- ✅ Website and README updated — Spectrafall feature, casual privacy lock framing
- ✅ Notarized, stapled, DMG published, GitHub release live

### v1.3 (June 2026)
- ✅ Glyph atlas (CGImage bitmap blit, pre-warmed)
- ✅ 60fps frame cap (raised from 30fps)
- ✅ CVDisplayLink leak fixed — CPU drops to near zero after dismissal
- ✅ Glyph mutation rate halved
- ✅ "Show overlays on main display only" toggle
- ✅ Verified on Mac Mini M4 dual 4K + 1440p high-refresh

### v1.2 (May 2026)
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

## Roadmap

### v1.5.2 (June 2026) — Current Release
- ✅ **Auto-updater relaunch fix** — shell watcher polls for old PID to exit before launching new instance; eliminates race condition where `open` activated the running process instead of relaunching.

### v1.5.1
- ✅ **About panel transparency** — blurred `NSVisualEffectView` (double-pass `.hudWindow`) with transparent titlebar; `alphaValue = 0.82`.
- ✅ **Settings tab bar light mode fix** — `PillTabBar` colours now adapt to system appearance via `viewDidChangeEffectiveAppearance()`; light mode shows light gray track + white pill + dark text.
- ✅ **Live Preview / version label contrast** — bumped from tertiary/quaternary to secondary/tertiary label colour for readability in light mode.

### v1.5
- ✅ **Column grid centering** — rain columns laid out with equal margins left and right; clock, date, and message all share the same screen center axis.
- ✅ **Clock/date centering** — CTLine glyph-path bounds for precise visual centering; burn-in protection replaced with ±1 pt font size nudge once per minute (no more positional drift).
- ✅ **Version number in settings** — current app version displayed below the live preview panel.
- ✅ **Auto-updater** — clicking "Update Available" downloads the DMG, prompts "Install & Restart", copies app via `ditto`, relaunches. No Sparkle dependency — uses GitHub Releases API already in place.
- ✅ **"Start Now" shortcut display** — global hotkey shown right-aligned on the Start Now menu item using native AppKit rendering; updates when shortcut changes; blank if no shortcut set. ⌘, removed from Settings (not globally usable).
- ✅ **Branded DMG installer** — custom MidJourney Matrix background, app icon + Applications alias, drag-to-install layout. Script: `scripts/make-dmg.sh`. Requires `create-dmg` via Homebrew.

### v2.0
- **UI & Performance overhaul** — macOS HIG design pass (developer.apple.com/design), settings redesigned as macOS-style sidebar with coloured selection and attached square preview panel, full optimisation pass targeting M1–M5.

### Post v2.0 (Separate Project)
- **Windows companion app** — Tauri (Rust + Web Canvas), separate repo, native Windows feel, feature parity with macOS version.

---

## Known Issues / Beta Features

| Item | Status | Notes |
|------|--------|-------|
| Password Lock | BETA | Touch ID / Apple Watch auth working. Codex improved lock arming logic (manual start + idle=0 now locks immediately). More testing needed. |
| Cloudflare Workers | Config present, not deployed | `wrangler.jsonc` merged to main but DNS not pointed at Cloudflare yet. GitHub Pages is live. |
