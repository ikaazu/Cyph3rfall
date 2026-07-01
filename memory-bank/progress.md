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
- ✅ Password lock (Touch ID / Apple Watch)
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

### v1.5.3 (June 2026) — Current Release
- ✅ **Auto-updater relaunch fix (verified working)** — replaced shell watcher (killed by sandbox on parent exit) with `NSWorkspace.shared.openApplication(createsNewApplicationInstance: true)` + 1s delay before terminate; uses Launch Services directly, no child process. Confirmed working on Mac Mini and MacBook Pro.

### v1.5.2
- ✅ **Auto-updater relaunch fix (attempt)** — shell watcher approach; did not survive sandbox teardown.

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

### v2.0 — In Progress

#### Settings
- ✅ Sidebar navigation — macOS source-list style (NSTableView `.sourceList`), replacing PillTabBar pill tabs
- ✅ About moved into Settings sidebar — removed from menu bar menu
- ✅ HIG content pass — section headers (Animation, Color, Display & Security) in General tab; checkboxes self-labeling on Message and Clock tabs; row spacing tightened to 10pt
- ✅ American spelling throughout UI ("Color" not "Colour")

#### Menu
- ✅ Version displayed at top of menu bar menu (disabled/grayed label)
- ✅ "Check for Updates…" added to menu bar menu (alongside Settings)

#### Website
- ✅ Changelog page (cyph3rfall.app/changelog.html) — full version history
- ✅ Add changelog link to footer nav

#### Stability
- ✅ Password lock out of beta — BETA label removed

#### Performance
- ✅ Shared CVDisplayLink across views — one link in FullScreenWindow drives all rain views via externalTick(); removed per-view links on multi-monitor
- ✅ Profile on M4 / M5 — verified on Mac Mini M4 dual display; smoother frame pacing than v1.x confirmed

### Post v2.0 (Separate Project)
- **Windows companion app** — Tauri (Rust + Web Canvas), separate repo, native Windows feel, feature parity with macOS version.

---

## Known Issues

| Item | Status | Notes |
|------|--------|-------|
| Cloudflare Workers | Removed | Worker route was causing 522 errors by intercepting traffic with no origin. Deleted Worker, added CNAME `@` → `ikaazu.github.io` (DNS only). GitHub Pages serving directly. |
