# Active Context — Cyph3rfall

**Last Updated**: 2026-06-01  
**Current State**: IDLE — performance optimisation shipped, testing in progress

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

### Pending: Commit & Push

These changes are built and running but **not yet committed**. Next step after Mac Mini testing confirms no regressions:

```bash
cd ~/MatrixRainSaver
git add Shared/GlyphAtlas.swift Shared/Cyph3rfallView.swift Shared/GlyphColumn.swift
git commit -m "Performance: glyph atlas, 30fps cap, halve mutation rate"
git push
```

---

## Open Questions

- Does the 30fps cap feel smooth enough on the Mac Mini M4 connected to a 4K display?
- Are there any visual regressions in Chromafall mode or with message/clock overlays on the Mac Mini?
- Should the frame rate cap be user-configurable (60/30 fps toggle), or stay as a fixed internal constant?

---

## State Machine Position

**State**: IDLE (between tasks)  
**Last completed**: Performance optimisation (BUILD complete, testing in progress)  
**Next**: Commit after Mac Mini validation, then choose next backlog item
