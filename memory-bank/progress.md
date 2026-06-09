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

## Roadmap

### v1.4
- **Color cycle mode** — slow full-screen palette drift through all 9 presets, smooth interpolation between head/trail colours, configurable speed. Mutually exclusive with Chromafall. Name TBD (candidates: Prismafall, Spectrafall, Driftfall).
- **Release checklist (beyond standard notarize/DMG/publish flow):**
  - Release notes must mention lock hardening: "Password lock now fails closed if authentication is unavailable" — signals active BETA improvement
  - Add honest framing to website and README: password lock is a "casual privacy lock, not a security boundary" — pair this with the lock improvement for credibility
  - Bump **both** `CFBundleShortVersionString` (1.3 → 1.4) **and** `CFBundleVersion` (build integer) in `TestApp/Info.plist` — required for in-app update banner to fire for existing users

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
