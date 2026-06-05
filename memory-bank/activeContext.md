# Active Context — Cyph3rfall

**Last Updated**: 2026-06-01  
**Current State**: IDLE — v1.3 feature complete, ready to notarize and release

---

## Current Focus

Performance optimisation pass — glyph atlas, 30fps frame cap, reduced mutation rate. Changes built and running in debug. User is testing on Mac Mini M4 via AirDrop.

### What Was Just Done

Three performance changes landed in the same session (not yet committed to main):

1. **`Shared/GlyphAtlas.swift`** (new file) — lazy `(Character, colorID) → NSImage` bitmap cache. Replaces Core Text layout calls with bitmap blits in the draw loop.

2. **`Shared/Cyph3rfallView.swift`** — major changes:
   - `StreamColor` now `init(preset:)` instead of `init(fg:head:)` — adds `fgColorID`/`headColorID` for atlas lookup
   - `drawGlyph()` now uses `glyphAtlas.image(...).draw(in:from:operation:fraction:respectFlipped:hints:)`
   - `respectFlipped: true` required — without it glyphs render upside down in flipped NSView
   - `alpha` passed via `fraction:` parameter — `ctx.setAlpha()` does not affect NSImage drawing
   - Frame rate cap: 30fps via `lastRenderTime` / `targetFrameInterval = 1.0/30.0`
   - Removed orphaned `sharedAttrs` and `glyphStringCache`
   - `cachedDefaultStream` and `randomStreamColor()` use `StreamColor(preset:)`

3. **`Shared/GlyphColumn.swift`** — mutation throttled to every 2 ticks via `mutationCounter`

### Issues Found and Fixed This Session

| Bug | Cause | Fix |
|-----|-------|-----|
| Trail no longer fades | `NSImage.draw(in:)` ignores `ctx.setAlpha()` | Pass alpha via `fraction:` parameter |
| Message characters upside down | `NSImage.draw()` doesn't respect flipped view | Add `respectFlipped: true, hints: nil` |

### Committed: e231195

All three files committed and pushed. Verified on MacBook Pro M5:
- No startup hesitation (prewarm working)
- Trail fade correct (ctx.setAlpha works with CGContext)
- Message overlay correct (per-glyph flip compensation fixes upside-down glyphs)

Mac Mini M4 testing to be completed when available.

---

## Open Questions

- Mac Mini M4 full test still pending (user is travelling)
- Should the frame rate cap be user-configurable (60/30 fps toggle) or stay as a fixed internal constant?

---

## State Machine Position

**State**: IDLE (between tasks)  
**Last completed**: Performance optimisation (BUILD complete, testing in progress)  
**Next**: Commit after Mac Mini validation, then choose next backlog item
