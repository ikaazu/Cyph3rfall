# App Store Migration Guide

Reference document for moving Cyph3rfall from direct distribution to Mac App Store.
Authored June 2026 based on the v2.0 codebase.

---

## What Must Be Removed

### Auto-updater (significant)

The entire self-update mechanism is incompatible with the App Store sandbox. The App Store
manages updates itself, so this feature is replaced — not just blocked.

Files and methods to delete:

- `AppDelegate.checkForUpdatesManually()` — manual update check
- `AppDelegate.installUpdate()` — DMG download + `ditto` copy + relaunch
- `AppDelegate.openReleasePage()` — fallback to GitHub releases page
- `AppDelegate.makeGitHubReleaseRequest()` — GitHub Releases API request builder
- `AppDelegate.isNewerVersion(_:than:)` — version comparison
- `AppDelegate.stripVersionTag(_:)` — strips "v" prefix from tag names
- The background update check that runs on app launch (look for the `URLSession.dataTask`
  call in `applicationDidFinishLaunching` or similar)
- `updateAvailableVersion` and `updateDownloadURL` state vars
- `isDownloadingUpdate` state var
- The "⬆ Update Available (v…)" dynamic menu item in `rebuildMenu()`
- `PreferencesWindowController.triggerCheckForUpdates()` and `onCheckForUpdates` callback
- The "Check for Updates…" button in the About tab (`makeAboutTabContent`)
- `releasesPageURL` constant in AppDelegate

Also remove from `Info.plist` / entitlements anything added solely for the updater.

---

## What Stays the Same

Everything below works in the App Store sandbox without modification:

| Feature | Why it's fine |
|---|---|
| Global hotkey | Carbon `RegisterEventHotKey` is permitted in App Store sandbox |
| Password lock (Touch ID / Apple Watch) | `LocalAuthentication` works in sandbox |
| Launch at Login | `SMAppService.mainApp` is the modern sandbox-compatible API |
| Settings Import / Export | `NSOpenPanel` / `NSSavePanel` are sandbox-compatible |
| Full-screen rain window | Plain `NSWindow` — no restrictions |
| Menu bar app (`LSUIElement`) | Supported on App Store |
| Website / email links | `NSWorkspace.shared.open()` is fine |
| Sidebar settings panel | Pure AppKit — no restrictions |
| CVDisplayLink animation | No restrictions |

---

## New Requirements

### 1. Sandbox entitlement

Create `Cyph3rfall.entitlements` (or update the existing one) and add to the Xcode target:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
</dict>
</plist>
```

If you add a "Visit Website" or any other outbound network feature, also add:

```xml
    <key>com.apple.security.network.client</key>
    <true/>
```

### 2. LocalAuthentication usage description

Add to `Info.plist` if not already present (required for biometric permission prompt):

```xml
<key>NSLocalAuthenticationUsageDescription</key>
<string>Cyph3rfall uses Touch ID or Apple Watch to unlock the screensaver.</string>
```

### 3. Privacy manifest (`PrivacyInfo.xcprivacy`)

Apple requires a privacy manifest for apps that use certain APIs. LocalAuthentication
triggers this requirement. Create `PrivacyInfo.xcprivacy` in the app target:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryLocalAuthentication</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>1.0</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

Verify the required reason codes against Apple's current documentation at review time —
these change periodically.

### 4. App Store Connect setup

- Create a new app record in App Store Connect
- Set bundle ID to match `PRODUCT_BUNDLE_IDENTIFIER` in Xcode
- Choose category: **Utilities**
- Provide screenshots for each required Mac display size
- Write App Store description, keywords, and support URL
- Set pricing (free / paid / freemium)

### 5. Build configuration

- Switch signing to **App Store Distribution** certificate + provisioning profile
- Archive via **Product → Archive** in Xcode
- Upload via **Xcode Organizer → Distribute App → App Store Connect**
- The `scripts/make-dmg.sh` script and notarization workflow are no longer needed
  (App Store submission replaces both)

---

## Things to Verify Before Submission

- [ ] Auto-updater fully removed — no `ditto`, no `URLSession` update checks, no GitHub API calls
- [ ] App launches and runs cleanly under sandbox (test with entitlement applied in Xcode)
- [ ] Touch ID lock still works under sandbox
- [ ] Global hotkey still registers under sandbox
- [ ] Launch at Login still works under sandbox
- [ ] Import / Export settings still work under sandbox
- [ ] No `NSWorkspace.open()` calls pointing at GitHub release URLs (remove or replace)
- [ ] Privacy manifest present and reason codes current
- [ ] App Store screenshots captured at required resolutions

---

## Distribution Comparison

| | Current (Direct) | App Store |
|---|---|---|
| Updates | Self-updating via GitHub Releases + DMG | Managed by App Store |
| Signing | Developer ID Application | Apple Distribution |
| Notarization | Manual (`xcrun notarytool`) | Handled by App Store |
| DMG | `scripts/make-dmg.sh` + `create-dmg` | Not needed |
| Sandbox | No | Required |
| Revenue cut | 0% | 15–30% |
| Discoverability | Direct link / word of mouth | App Store search |
| Beta testing | Manual DMG distribution | TestFlight |
