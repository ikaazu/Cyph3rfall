# Tech Context — Cyph3rfall

## Language & Platform

| Item | Value |
|------|-------|
| Language | Swift 5.0 |
| UI Framework | AppKit (NSView, NSPanel, NSStatusItem) |
| Rendering | Core Graphics (CGContext), Core Text via NSString.draw |
| Animation | CVDisplayLink |
| Platform | macOS 14.0+ (Sonoma) |
| Architectures | arm64 (Apple Silicon) + x86_64 (Intel) |
| Xcode | 16+ |
| Build tool | XcodeGen (`project.yml`) |

## Dependencies

**Zero runtime dependencies.** No third-party frameworks, CocoaPods, or SPM packages in the app target.

System frameworks used:
- `Cocoa.framework`
- `ServiceManagement.framework` — Launch at Login
- `LocalAuthentication.framework` — Touch ID / Apple Watch auth
- `Carbon.framework` — Global hotkey registration (RegisterEventHotKey)

## Project Generation

Project is defined in `project.yml` (XcodeGen). Never edit `Cyph3rfall.xcodeproj` directly — always edit `project.yml` then run:

```bash
cd ~/MatrixRainSaver
xcodegen generate
```

Key `project.yml` settings:
- Debug config: `CODE_SIGN_STYLE: Automatic`, `DEVELOPMENT_TEAM: GHXKLLWQPM`
- Release config: `CODE_SIGN_STYLE: Manual`, `CODE_SIGN_IDENTITY: "Developer ID Application: Gregory Stock (GHXKLLWQPM)"`
- `ENABLE_HARDENED_RUNTIME: YES` (required for notarization)
- `MACOSX_DEPLOYMENT_TARGET: "14.0"`

## Build Commands

```bash
# Regenerate Xcode project
xcodegen generate

# Debug build (for local testing)
xcodebuild build \
  -project Cyph3rfall.xcodeproj \
  -scheme Cyph3rfall \
  -configuration Debug

# Release archive (for distribution)
xcodebuild archive \
  -project Cyph3rfall.xcodeproj \
  -scheme Cyph3rfall \
  -configuration Release \
  -archivePath /tmp/Cyph3rfall-vX.X.xcarchive
```

## Signing & Notarization

- **Certificate**: `Developer ID Application: Gregory Stock (GHXKLLWQPM)`
- **Team ID**: `GHXKLLWQPM`
- **Notarization**: Apple notarytool (xcrun notarytool)
- **App-specific password**: stored in 1Password, not in repo

### Full Notarization Flow

```bash
# 1. Archive
xcodebuild archive -project Cyph3rfall.xcodeproj -scheme Cyph3rfall \
  -configuration Release -archivePath /tmp/Cyph3rfall-vX.X.xcarchive

# 2. Zip
ditto -c -k --keepParent \
  /tmp/Cyph3rfall-vX.X.xcarchive/Products/Applications/Cyph3rfall.app \
  /tmp/Cyph3rfall-vX.X.zip

# 3. Submit (add --wait for synchronous result)
xcrun notarytool submit /tmp/Cyph3rfall-vX.X.zip \
  --apple-id APPLE_ID --team-id GHXKLLWQPM --password APP_SPECIFIC_PWD --wait

# 4. Staple
xcrun stapler staple /tmp/Cyph3rfall-vX.X.xcarchive/Products/Applications/Cyph3rfall.app

# 5. Verify
spctl --assess --type exec --verbose Cyph3rfall.app
# Expected: "source=Notarized Developer ID"

# 6. Package as DMG
mkdir -p /tmp/dmg-stage
cp -R Cyph3rfall.app /tmp/dmg-stage/
hdiutil create -volname "Cyph3rfall" -srcfolder /tmp/dmg-stage \
  -ov -format UDZO /tmp/Cyph3rfall-vX.X.dmg
```

## GitHub CLI

`gh` is installed at `/opt/homebrew/bin/gh`. Authenticated as `ikaazu`.

```bash
# Create release
gh release create vX.X Cyph3rfall-vX.X.dmg \
  --title "Cyph3rfall vX.X" --notes "..."
```

## Notarization History

All 5 prior submissions (May 20–21, 2026) were stuck "In Progress" due to Apple's new account manual vetting queue. Apple Developer Support ticket resolved this. All submissions subsequently showed `Accepted`. v1.2 notarization came back `Accepted` in under 60 seconds.

## Website

- URL: `https://cyph3rfall.app`
- Source: `docs/` folder
- Hosting: GitHub Pages (primary), Cloudflare Workers config present (`wrangler.jsonc`)
- CNAME: `docs/CNAME`
- No build step — edit `docs/index.html` directly

## Debug App Location

After a Debug build, the app is at:
```
~/Library/Developer/Xcode/DerivedData/Cyph3rfall-[hash]/Build/Products/Debug/Cyph3rfall.app
```
Find with: `find ~/Library/Developer/Xcode/DerivedData -name "Cyph3rfall.app" -path "*/Debug/*"`

## Test Machines

| Machine | Chip | Role |
|---------|------|------|
| MacBook Pro | M5 | Primary development |
| Mac Mini | M4 | Performance testing target |
