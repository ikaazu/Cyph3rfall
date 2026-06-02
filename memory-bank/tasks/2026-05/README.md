# Tasks — May 2026

## Summary

v1.1 shipped, optimization pass completed, v1.2 (first notarized release) shipped.

## Tasks Completed

### 2026-05-??:  v1.1 Release
- Tabbed settings panel (General / Message / Clock / Import/Export)
- Auto-update check via GitHub Releases API
- Settings export/import (JSON)
- Column spacing (Wide / Narrow)
- Clock colour tied to rain preset

### 2026-05-20 – 2026-05-21: Notarization Attempt
- Submitted 5 times; all stuck "In Progress" — Apple new-account manual vetting queue
- Filed Apple Developer Support ticket
- All 5 submissions eventually Accepted

### 2026-05-21: Render Loop Optimisation Pass (pre-atlas)
- NSFont cached in rebuild()
- NSAttributedString cached per-second for clock
- Per-frame CGColor bridging eliminated
- `sharedAttrs` pattern for glyph drawing
- `glyphStringCache` for NSString bridging
- `lastBuiltSize` guard in layout()
- In-place array refill in GlyphColumn.reset()
- Single Calendar.dateComponents() call per frame

### 2026-05-21: v1.2 Release (First Notarized)
- Version bump to 1.2 / build 5
- Added `Cyph3rfall` scheme to project.yml (required for xcodebuild archive)
- Release config: Manual signing with Developer ID
- Notarized, stapled, Gatekeeper verified
- DMG packaged and released on GitHub
- Website updated (Gatekeeper note removed, install steps simplified to 3)

### 2026-05-24: Codex Integration
- Reviewed Codex changes from `/private/tmp/Cyph3rfall-review/`
- Accepted: HotkeyManager error handling, Apple Watch auth preference, lock arming logic
- Rejected: density threshold regression (2.0 → restored to 1.51)
- Merged: Cloudflare Workers config (wrangler.jsonc)
