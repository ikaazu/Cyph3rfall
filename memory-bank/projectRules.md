# Project Rules — Cyph3rfall

## Coding Standards

### Language
- Swift 5.0, AppKit only — no SwiftUI, no third-party dependencies
- `final class` for all major types (prevents unintended subclassing)
- Value types (`struct`) for settings and data models
- `private` by default — only promote access level when required

### Naming
- Files: `PascalCase.swift`
- Types/Structs: `PascalCase`
- Properties/functions: `camelCase`
- Constants: `camelCase` (not SCREAMING_SNAKE)
- Settings keys: `camelCase` strings (e.g. `"idleTimeoutSeconds"`)
- URL constants: `static let` on `AppDelegate` — never force-unwrapped string literals inline

### Comments
- Comment the *why*, not the *what*
- Mark non-obvious performance decisions prominently (e.g. "avoids NSColor allocation per glyph")
- MARK sections: `// MARK: - Section Name`

---

## Architecture Rules

### Never-Per-Frame Work
The following must NEVER run inside `draw()` or `tick()`:
- NSFont lookup by name
- NSColor → CGColor bridging (use pre-computed `cgColor`)
- NSAttributedString allocation
- New NSColor with alpha component (use `ctx.setAlpha()` or `fraction:`)
- Any `UserDefaults` read/write
- Any file I/O

All such values must be pre-computed in `rebuild()` and cached.

### Rebuild Guard
`rebuild()` is gated by `guard sz != lastBuiltSize else { return }` in `layout()`. Any settings change must set `lastBuiltSize = .zero` before calling `rebuild()` to ensure the guard doesn't skip it.

### NSImage Drawing in Flipped Views
When drawing `NSImage` into a flipped NSView (`isFlipped = true`):
- **Always** use `draw(in:from:operation:fraction:respectFlipped:hints:)` with `respectFlipped: true`
- **Never** use `ctx.setAlpha()` to control NSImage alpha — it is ignored. Pass alpha via the `fraction:` parameter instead.
- Simple `draw(in:)` will render images upside down in flipped views.

### StreamColor Construction
Always use `StreamColor(preset:)`. Never construct with raw `NSColor` values — the atlas color IDs will not match.

### Atlas Invalidation
Call `glyphAtlas.invalidate()` from `rebuild()` whenever settings change. The atlas is cheap to repopulate lazily. Do NOT call `invalidate()` from the draw path.

### Settings Struct
`Cyph3rfallSettings` is a pure value type. No mutation outside of `AppDelegate` or `PreferencesWindowController`. Changes flow: `prefsController` edits → `AppDelegate.settings = newSettings` → `settings.didSet` propagates to all views.

---

## UI Rules

### Menu Bar
- Icon: `Ξ` (Xi, U+039E)
- No Dock icon (LSUIElement = true in Info.plist)
- Menu item order: Start Now | separator | Settings | About | separator | Quit

### Preferences Window
- Currently: tab strip (General / Message / Clock / Import/Export)
- Planned redesign: sidebar + attached preview panel (see backlog item 2)
- Live preview NSView uses `startExternalAnimation()` / `externalTick()` mode

### Density Performance Warning
Threshold: `value <= 1.51` (151%). Appears in `densityChanged()` and `populate()` in `PreferencesWindowController.swift`. The note text is amber coloured. Do NOT change this threshold without user approval — it has been deliberately set twice.

---

## XcodeGen Rules

- Edit `project.yml` — never edit `Cyph3rfall.xcodeproj` directly
- Run `xcodegen generate` after any `project.yml` change
- Debug: Automatic signing | Release: Manual, Developer ID
- Scheme name: `Cyph3rfall` (required for `xcodebuild archive -scheme Cyph3rfall`)

---

## Git Rules

- Branch: `main` is the production branch
- Commit messages: imperative present tense, brief summary line
- Co-author line on AI-assisted commits: `Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>`
- DMG assets committed to repo root (tracked in git)
- Generated Xcode files (`project.pbxproj`, `xcschemes/`) ARE committed

---

## Version Numbering

- Format: `MAJOR.MINOR` (e.g. `1.2`)
- Build number: sequential integer in `Info.plist CFBundleVersion`
- Both live in `TestApp/Info.plist`
- Current: version `1.2`, build `5`
- Next planned: `1.3` (post-performance + HIG pass)
