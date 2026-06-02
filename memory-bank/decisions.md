# Architectural Decisions — Cyph3rfall

---

## 2026-05-01: No Screensaver Framework

**Status**: Approved  
**Context**: macOS screensaver framework is deprecated, sandboxed, and difficult to distribute.  
**Decision**: Build as a plain `NSApplication` with `LSUIElement = true`. Full-screen windows created manually via `NSScreen.screens`.  
**Alternatives**: ScreenSaverKit (deprecated, restricted), WWDC screensaver APIs (limited)  
**Consequences**: Full control over windowing, signing, and distribution. No `.saver` bundle complications.

---

## 2026-05-01: No Third-Party Dependencies

**Status**: Approved  
**Context**: Screensaver should be lean and have zero supply-chain risk.  
**Decision**: Only Apple system frameworks. No SPM, CocoaPods, or Carthage.  
**Alternatives**: Sparkle (auto-updater), various animation libraries  
**Consequences**: More code written manually (hotkey, idle detection, update check). Auto-updater backlogged.

---

## 2026-05-10: XcodeGen Over Manual Xcodeproj

**Status**: Approved  
**Context**: `project.pbxproj` is fragile and hard to review in diffs.  
**Decision**: Use XcodeGen (`project.yml`) as source of truth. `xcodeproj` is generated, committed for IDE compatibility.  
**Alternatives**: Manual Xcode project, Tuist  
**Consequences**: Clean, readable project definition. Must run `xcodegen generate` after any project change.

---

## 2026-05-15: CVDisplayLink Per View (Current)

**Status**: Approved (subject to review)  
**Context**: Each `Cyph3rfallView` on each monitor needs its own animation loop.  
**Decision**: Each view owns its own `CVDisplayLink` targeting that display.  
**Alternatives**: Shared link in `FullScreenWindow`, single app-level timer  
**Consequences**: Simple isolation. On multi-monitor setups, callback count multiplies. Shared link is on the backlog.

---

## 2026-05-20: Rebuild Cache Pattern

**Status**: Approved  
**Context**: `draw()` runs 30–60× per second. NSFont, CGColor, NSAttributedString allocations in the draw loop cause visible CPU overhead.  
**Decision**: All expensive values pre-computed in `rebuild()`, cached as properties, invalidated only on settings/geometry change.  
**Alternatives**: Lazy properties (don't invalidate on change), per-frame computation (too expensive)  
**Consequences**: Significant CPU reduction. `lastBuiltSize` guard prevents redundant rebuilds during resize animations.

---

## 2026-05-21: Notarization Strategy

**Status**: Approved  
**Context**: First 5 notarization submissions stuck "In Progress" for days on new Apple Developer account.  
**Decision**: Filed Apple Developer Support ticket. Waited for manual vetting queue clearance. v1.2 = first notarized release.  
**Alternatives**: Ship un-notarized with right-click workaround (done temporarily for v1.1)  
**Consequences**: All subsequent submissions accepted in under 60 seconds. Clean install experience for users.

---

## 2026-05-25: Glyph Atlas Over Direct Core Text

**Status**: Approved  
**Context**: At high density on 4K displays, `NSString.draw(in:withAttributes:)` calls Core Text layout engine thousands of times per frame at 60fps. This is the primary CPU bottleneck.  
**Decision**: Pre-render each `(Character, colorID)` pair into a `NSImage` bitmap (`GlyphAtlas.swift`). Draw path becomes a bitmap blit.  
**Alternatives**: Metal shader rendering (much more complex), CALayer-based animation (loses fine-grained control), lower density cap  
**Consequences**: Dramatically lower CPU at high density. Atlas invalidated on any settings change and repopulated lazily. `respectFlipped: true` required for correct orientation in flipped NSView. Alpha must be passed via `fraction:` not `ctx.setAlpha()`.

---

## 2026-05-25: 30fps Internal Frame Cap

**Status**: Approved  
**Context**: Physics and rendering both ran at display link rate (60–120Hz). Rendering at 60fps for rain animation provides no perceptible quality gain over 30fps.  
**Decision**: Time-based frame cap in `tick()` — physics ticks at full rate, `needsDisplay = true` only when `>= 1/30s` elapsed since last render.  
**Alternatives**: 24fps cap (too low for smooth column movement), 60fps (no change), user-configurable (deferred)  
**Consequences**: ~50% render call reduction. Physics remains smooth at full rate so column positions update correctly even when renders are skipped.

---

## 2026-05-26: Codex Hotkey + Auth Improvements Accepted

**Status**: Approved  
**Context**: Codex (OpenAI) worked on the codebase in a separate working copy (`/private/tmp/Cyph3rfall-review/`). Changes included hotkey error handling, Apple Watch auth preference, and improved lock arming logic. Also included a density threshold regression (2.0 vs 1.51).  
**Decision**: Accept HotkeyManager + AppDelegate improvements. Reject density threshold change (restored to 1.51). Cloudflare Workers config (`wrangler.jsonc`) merged separately.  
**Consequences**: Hotkey conflicts now surface an NSAlert instead of silently failing. Apple Watch preferred over Touch ID when available. Manual-start + idle=0 now locks immediately.
