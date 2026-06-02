# Quick Start — Cyph3rfall

## Daily Development Loop

```bash
cd ~/MatrixRainSaver

# 1. Edit source files in Shared/ or TestApp/
# 2. If project.yml changed:
xcodegen generate

# 3. Build debug
xcodebuild build -project Cyph3rfall.xcodeproj -scheme Cyph3rfall -configuration Debug

# 4. Find and run debug build
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'Cyph3rfall.app' -path '*/Debug/*' | head -1)"

# 5. Commit
git add <files>
git commit -m "Description"
git push
```

## File Quick Reference

| What you want to change | File |
|------------------------|------|
| Rain animation / rendering | `Shared/Cyph3rfallView.swift` |
| Glyph bitmap cache | `Shared/GlyphAtlas.swift` |
| Column physics / mutation | `Shared/GlyphColumn.swift` |
| Settings data model | `Shared/Cyph3rfallSettings.swift` |
| Settings persistence (UserDefaults) | `Shared/Cyph3rfallSettings+Defaults.swift` |
| Settings JSON export/import | `Shared/Cyph3rfallSettings+JSON.swift` |
| Preferences window UI | `Shared/PreferencesWindowController.swift` |
| Menu bar, idle, hotkey, lock, update check | `TestApp/AppDelegate.swift` |
| Full-screen window per monitor | `TestApp/FullScreenWindow.swift` |
| Idle time polling | `TestApp/IdleWatcher.swift` |
| Global hotkey registration | `TestApp/HotkeyManager.swift` |
| Hotkey recorder UI control | `Shared/HotkeyRecorderView.swift` |
| App icon, Info.plist, version | `TestApp/` |
| Website | `docs/index.html` |

## Common Patterns

### Adding a new setting

1. Add property to `Cyph3rfallSettings.swift`
2. Add UserDefaults read/write in `Cyph3rfallSettings+Defaults.swift`
3. Add JSON encode/decode in `Cyph3rfallSettings+JSON.swift`
4. Add UI control in `PreferencesWindowController.swift`
5. Use in `Cyph3rfallView.swift` — add to cache in `rebuild()` if expensive

### Adding a colour preset

1. Add case to `ColorPreset` enum in `Cyph3rfallSettings.swift`
2. Add `label`, `foregroundColor`, `headColor` in the switch statements
3. Atlas colorID auto-follows: `preset.rawValue * 2` (fg) and `* 2 + 1` (head)
4. If adding beyond 8 presets: update `GlyphAtlas.whiteID` constant

### Checking for performance regressions

Open Activity Monitor on the test machine. Look at CPU % for the `Cyph3rfall` process at:
- Normal settings (green, density 1.0, glow on) → target: <5% on M1
- High density (2.0+) + Chromafall → this is the stress test
- Multi-monitor adds roughly linear CPU per display

### Release checklist

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `TestApp/Info.plist`
2. Run `xcodegen generate`
3. Archive: `xcodebuild archive ... -archivePath /tmp/Cyph3rfall-vX.X.xcarchive`
4. Verify signing: `codesign -dv --verbose=2 Cyph3rfall.app | grep Authority`
5. Zip and submit to notarytool
6. Check status until `Accepted`
7. Staple: `xcrun stapler staple Cyph3rfall.app`
8. Verify: `spctl --assess --type exec --verbose Cyph3rfall.app` → `Notarized Developer ID`
9. Package DMG
10. `git commit` + `git push`
11. `gh release create vX.X Cyph3rfall-vX.X.dmg --title "..." --notes "..."`
12. Update `docs/index.html` (version badge, What's New, install steps if changed)
13. `git push` website changes

## Key Constants

| Constant | Value | Location |
|----------|-------|----------|
| Team ID | `GHXKLLWQPM` | `project.yml`, signing commands |
| Bundle ID | `com.cyph3rfall.Cyph3rfall` | `project.yml` |
| Density warning threshold | `1.51` | `PreferencesWindowController.swift:709` |
| Frame rate cap | `1.0 / 30.0` | `Cyph3rfallView.swift:targetFrameInterval` |
| Glyph atlas white ID | `18` | `GlyphAtlas.whiteID` |
| Idle poll interval | `5s` | `IdleWatcher.swift:24` |
| Flash timer range | `2...6` ticks | `GlyphColumn.swift:update()` |
| Mutation interval | every 2 ticks | `GlyphColumn.swift:mutationCounter` |
