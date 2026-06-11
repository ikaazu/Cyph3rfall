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

### v1.5

### v1.5
- **Auto-updater** — version label at top of menu transforms into "Update to vX.X" button when update available. In-app download + install + restart. Requires write permission to `/Applications`. Sparkle framework likely needed (adds a dependency — needs decision).
- **"Start Now" shortcut display** — assigned global shortcut shown right-aligned on the Start Now menu item, matching standard macOS menu convention. Blank if no shortcut set.
- **Branded DMG installer** — custom dark background with Cyph3rfall icon + Applications folder alias + drag instruction. Replaces current plain DMG.

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
