# Build & Deployment — Cyph3rfall

## Signing Identity

```
Developer ID Application: Gregory Stock (GHXKLLWQPM)
Certificate SHA1: 5606AAF414FA1698AEE4E479E746EDE63833549C
Team ID: GHXKLLWQPM
```

## Notarization Credentials

- Apple ID: `YOUR_APPLE_ID`
- Team ID: `GHXKLLWQPM`
- App-specific password: stored in 1Password (not in repo or memory bank)

## Entitlements

Both `DebugProfile.entitlements` and `Release.entitlements` must include:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
<true/>
```

`DebugProfile.entitlements` also includes:
```xml
<key>com.apple.security.cs.allow-jit</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
```

## Full Release Flow

### 1. Version Bump
Edit `TestApp/Info.plist`:
- `CFBundleShortVersionString`: new version (e.g. `1.3`)
- `CFBundleVersion`: next build integer (e.g. `6`)

### 2. Regenerate Project
```bash
cd ~/MatrixRainSaver && xcodegen generate
```

### 3. Archive
```bash
xcodebuild archive \
  -project Cyph3rfall.xcodeproj \
  -scheme Cyph3rfall \
  -configuration Release \
  -archivePath /tmp/Cyph3rfall-vX.X.xcarchive
```

### 4. Verify Signing
```bash
codesign -dv --verbose=2 \
  /tmp/Cyph3rfall-vX.X.xcarchive/Products/Applications/Cyph3rfall.app \
  2>&1 | grep -E "Authority|TeamIdentifier|flags"
# Must show: Authority=Developer ID Application: Gregory Stock (GHXKLLWQPM)
# Must show: flags=0x10000(runtime)  ← hardened runtime
```

### 5. Zip
```bash
ditto -c -k --keepParent \
  /tmp/Cyph3rfall-vX.X.xcarchive/Products/Applications/Cyph3rfall.app \
  /tmp/Cyph3rfall-vX.X.zip
```

### 6. Notarize
```bash
xcrun notarytool submit /tmp/Cyph3rfall-vX.X.zip \
  --apple-id YOUR_APPLE_ID \
  --team-id GHXKLLWQPM \
  --password APP_SPECIFIC_PASSWORD \
  --wait
# Expected: status: Accepted
```

If not using --wait, poll with:
```bash
xcrun notarytool info SUBMISSION_ID \
  --apple-id YOUR_APPLE_ID \
  --team-id GHXKLLWQPM \
  --password APP_SPECIFIC_PASSWORD
```

### 7. Staple
```bash
xcrun stapler staple \
  /tmp/Cyph3rfall-vX.X.xcarchive/Products/Applications/Cyph3rfall.app
# Expected: The staple and validate action worked!
```

### 8. Gatekeeper Check
```bash
spctl --assess --type exec --verbose \
  /tmp/Cyph3rfall-vX.X.xcarchive/Products/Applications/Cyph3rfall.app
# Expected: source=Notarized Developer ID
```

### 9. DMG
```bash
mkdir -p /tmp/Cyph3rfall-dmg-stage
cp -R /tmp/Cyph3rfall-vX.X.xcarchive/Products/Applications/Cyph3rfall.app \
  /tmp/Cyph3rfall-dmg-stage/
hdiutil create \
  -volname "Cyph3rfall" \
  -srcfolder /tmp/Cyph3rfall-dmg-stage \
  -ov -format UDZO \
  /tmp/Cyph3rfall-vX.X.dmg
cp /tmp/Cyph3rfall-vX.X.dmg ~/MatrixRainSaver/
```

### 10. Commit & Release
```bash
cd ~/MatrixRainSaver
git add TestApp/Info.plist Cyph3rfall.xcodeproj/ Cyph3rfall-vX.X.dmg
git commit -m "Release vX.X — [brief description]"
git push

gh release create vX.X Cyph3rfall-vX.X.dmg \
  --title "Cyph3rfall vX.X" \
  --notes "## Cyph3rfall vX.X
[release notes]"
```

### 11. Update Website
- Update version badge in `docs/index.html`
- Update What's New section
- Update install steps if anything changed
- `git add docs/index.html && git commit -m "Update website for vX.X" && git push`

## GitHub CLI Reference

```bash
# Check releases
gh release list

# Check notarization history
xcrun notarytool history \
  --apple-id YOUR_APPLE_ID \
  --team-id GHXKLLWQPM \
  --password APP_SPECIFIC_PASSWORD
```
