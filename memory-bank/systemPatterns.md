# System Patterns — Cyph3rfall

## Architecture Overview

```
TestApp/                        Shared/
├── AppDelegate.swift           ├── Cyph3rfallView.swift      ← render engine
├── FullScreenWindow.swift      ├── GlyphColumn.swift         ← column model
├── HotkeyManager.swift         ├── GlyphAtlas.swift          ← bitmap cache (NEW)
├── IdleWatcher.swift           ├── Cyph3rfallSettings.swift  ← data model
├── HotkeyRecorderView.swift    ├── Cyph3rfallSettings+JSON.swift
└── main.swift                  ├── Cyph3rfallSettings+Defaults.swift
                                ├── PreferencesWindowController.swift
                                └── HotkeyRecorderView.swift
```

**No screensaver framework**. Cyph3rfall is a plain `NSApplication` (LSUIElement=true) that opens full-screen borderless windows. This avoids screensaver sandbox restrictions and framework deprecations.

## Key Patterns

### 1. Dual Driver Mode (Cyph3rfallView)

`Cyph3rfallView` supports two animation modes:

- **Internal** (test app / menu bar app): owns a `CVDisplayLink`, calls `tick()` internally
- **External** (future screensaver wrapper): caller drives via `externalTick()`

```swift
// Internal mode (Cyph3rfallView.swift:164)
func startAnimation()     // starts CVDisplayLink
func stopAnimation()

// External mode (Cyph3rfallView.swift:180)
func startExternalAnimation()
func externalTick()       // called by external driver each frame
func stopExternalAnimation()
```

### 2. Rebuild / Cache Pattern

`rebuild()` is the expensive setup call. It runs only when settings or geometry change, never per-frame. It populates all per-frame caches:

- `cachedBackgroundCGColor` — avoids NSColor→CGColor per frame
- `cachedDefaultStream` — pre-built `StreamColor` for non-Chromafall mode
- `cachedClockFont` / `cachedClockDateFont` — NSFont lookup is expensive
- `cachedMessageGlowCG` — glow CGColor pre-computed
- `GlyphAtlas.configure()` + `invalidate()` — atlas reset on any settings change

**Guard**: `layout()` only calls `rebuild()` when `bounds.size != lastBuiltSize` (`Cyph3rfallView.swift:158`).

**Trigger**: `settings.didSet` sets `lastBuiltSize = .zero` before calling `rebuild()`.

### 3. Glyph Atlas (GlyphAtlas.swift)

Pre-renders each `(Character, colorID)` pair into an `NSImage` bitmap on first use. At draw time: bitmap blit instead of Core Text layout.

- **Color ID scheme**: `preset.rawValue * 2` = foreground, `preset.rawValue * 2 + 1` = head, `18` = white (flash)
- **Invalidation**: called from `rebuild()` on any settings/size change
- **Thread safety**: main thread only (draw path), no locking needed
- **Key**: `draw(in:from:operation:fraction:respectFlipped:hints:)` with `respectFlipped: true` — required for correct orientation in flipped NSView

### 4. StreamColor Struct

`StreamColor` is created per preset and carries pre-computed values to avoid per-glyph work:

```swift
struct StreamColor {
    let fg, head: NSColor
    let fgCG, headCG, glowCG: CGColor   // pre-bridged
    let fgColorID, headColorID: Int      // atlas keys
    init(preset: Cyph3rfallSettings.ColorPreset)
}
```

Always construct via `StreamColor(preset:)` — never `init(fg:head:)`.

### 5. Frame Rate Cap

Physics ticks at display link rate (60/120 Hz). Render is capped at 30 fps via time-based gate in `tick()` (`Cyph3rfallView.swift`):

```swift
private var lastRenderTime:      CFTimeInterval = 0
private let targetFrameInterval: CFTimeInterval = 1.0 / 30.0
// In tick(): only set needsDisplay = true when elapsed >= targetFrameInterval
```

### 6. Settings → Defaults → JSON

Settings flow:

```
Cyph3rfallSettings (struct, value type)
    ↓ load()
Cyph3rfallSettings+Defaults.swift   ← reads UserDefaults, clamps values
    ↓ save()
UserDefaults                         ← persisted between launches

Cyph3rfallSettings+JSON.swift        ← export/import as JSON file
```

`nearest(in:to:)` overloads in `Cyph3rfallSettings` resolve closest option index for speed, glyph size, trail length.

### 7. Idle Detection

`IdleWatcher` polls every 5 seconds using `CGEventSource.secondsSinceLastEventType`. Static helper `IdleWatcher.currentIdleTime()` is shared with `AppDelegate.startLockEligibilityTimer()` — the CGEventType sentinel lives in exactly one place (`IdleWatcher.swift:44`).

### 8. Hotkey Registration with Error Handling

`HotkeyManager.update(keyCode:carbonModifiers:) throws` — raises `RegistrationError` if Carbon event handler or hotkey registration fails. `AppDelegate.applyHotkey(from:)` is `@discardableResult` and shows an `NSAlert` on conflict (`AppDelegate.swift`).

`hotkeyChanged(from:to:)` guards re-registration so the hotkey is only re-registered when the combo actually changes.

### 9. Lock Arming Logic

- **Idle activation**: lock arms immediately when screensaver starts
- **Manual start + password enabled + idle timeout > 0**: lock arms after idle threshold via `startLockEligibilityTimer()`
- **Manual start + password enabled + idle timeout = 0**: lock arms immediately
- **Manual start + no password**: lock never arms

### 10. Authentication Preference

`AppDelegate` prefers `.deviceOwnerAuthenticationWithWatch` when paired Watch is available, falls back to `.deviceOwnerAuthentication` (Touch ID / Face ID / password) — `AppDelegate.swift`.

### 11. Version Comparison

`isNewerVersion(_:than:)` splits on `.` then expands leading-zero components digit-by-digit so `"1.02"` → `[1,0,2]` correctly sorts below `"1.1"` → `[1,1]`. Avoids the common bug where component `2 > 1` would make `1.02 > 1.1`.

### 12. GlyphColumn Mutation Rate

Glyph mutation is throttled to every 2 physics ticks (`GlyphColumn.swift:mutationCounter`). Halves random work while preserving the living-characters visual effect.

## Multi-Monitor

One `FullScreenWindow` per `NSScreen`. Each owns a `Cyph3rfallView` with its own `CVDisplayLink` targeting that display. All views share the same `settings` value.

**Known improvement**: shared display link in `FullScreenWindow` to reduce callback multiplication (on backlog).

## Website

`docs/` folder — static HTML/CSS/JS served by GitHub Pages and optionally Cloudflare Workers (`wrangler.jsonc`). No build step. Interactive screenshot tab gallery via vanilla JS `showTab()`.
