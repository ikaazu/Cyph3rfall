# Tasks — June 2026

## Summary

Performance overhaul — glyph atlas, frame rate cap, mutation rate reduction.

## Tasks In Progress

### 2026-06-01: Performance Optimisation (Glyph Atlas + Frame Cap) [IN-PROGRESS]
- ✅ Created `Shared/GlyphAtlas.swift` — lazy `(Character, colorID) → NSImage` bitmap cache
- ✅ Modified `Shared/Cyph3rfallView.swift`:
  - StreamColor uses `init(preset:)` with atlas colorIDs
  - drawGlyph uses atlas bitmaps with `respectFlipped: true`
  - Alpha via `fraction:` parameter (not ctx.setAlpha — NSImage ignores it)
  - 30fps frame cap via `lastRenderTime` / `targetFrameInterval`
  - Removed orphaned `sharedAttrs`, `glyphStringCache`
- ✅ Modified `Shared/GlyphColumn.swift`:
  - Mutation throttled to every 2 ticks via `mutationCounter`
- ✅ Fixed: trail fade bug (NSImage ignores ctx.setAlpha)
- ✅ Fixed: message characters upside down (NSImage needs respectFlipped: true)
- ✅ Fixed: NSImage.draw → CGImage + per-glyph saveGState/flip/restoreGState
- ✅ Fixed: atlas pre-flip caused double-flip (removed; standard CGBitmapContext now)
- ✅ Committed: e231195, pushed to main
- ⏳ Mac Mini M4 full test pending (user travelling)
