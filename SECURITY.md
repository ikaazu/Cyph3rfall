# Security Policy and Threat Model

## Purpose

This file provides persistent security context for maintainers, reviewers, and
Codex Security scans of Cyph3rfall. It describes what the application protects,
where untrusted data enters, which behaviors are security-sensitive, and how to
evaluate findings.

Cyph3rfall is a native macOS menu bar application. It renders an ambient
full-screen overlay, responds to system idle time and input events, optionally
uses macOS Local Authentication before dismissal, imports and exports visual
settings, and downloads updates from GitHub Releases.

## Supported Versions

Security fixes are made on the `main` branch and are intended for the latest
published release. Older releases may not receive fixes. Confirm the current
release and revision before evaluating or reporting an issue.

## Important Product Boundary

The optional password-lock feature is a **casual privacy overlay**. It is not a
replacement for the macOS lock screen, FileVault, account authentication,
authorization checks, or physical security.

A way to bypass the overlay is still worth reporting when it violates the
documented dismissal behavior, but it must not be described as an operating
system authentication bypass unless it crosses an actual macOS security
boundary.

## Assets to Protect

- Integrity and authenticity of the installed application and its updates.
- Developer signing, notarization, GitHub, and release credentials.
- Correct lifecycle of Local Authentication prompts and dismissal state.
- User privacy while the full-screen overlay is active.
- User-selected settings, including the custom displayed message.
- Password-lock and global-hotkey preferences that must not leak through a
  visual-settings export or be silently replaced by an import.
- Availability and rendering responsiveness of the menu bar application.
- Integrity of the static website and release links.

The application is not expected to store account passwords, biometric data,
financial data, health data, or server-side secrets.

## Trust Boundaries and Untrusted Inputs

### Network to updater

GitHub API responses, redirects, release tags, asset names, asset URLs, HTTP
headers, and downloaded bytes are untrusted until validated. The intended
source is the `ikaazu/Cyph3rfall` GitHub repository over HTTPS.

### Downloaded DMG to installed application

A mounted disk image and everything inside it are untrusted. Before any
application is copied over the installed bundle, the candidate must be bound to
the expected bundle identifier and Developer ID Team Identifier and pass code
signature and notarization/Gatekeeper validation.

Do not treat HTTPS, a `.dmg` suffix, or a GitHub-hosted URL as sufficient
authenticity evidence.

### User-selected file to settings state

Imported JSON may be malformed, oversized, deeply structured, or manually
crafted with out-of-range values and unexpected types. Validate and bound it
before it affects rendering, authentication behavior, hotkeys, or persistent
preferences.

### System events to lock state

Mouse and keyboard events, idle-time calculations, sleep/wake notifications,
screen changes, timers, and asynchronous Local Authentication callbacks may
arrive in surprising orders. Treat their ordering and lifetime as adversarial
when reviewing state transitions.

### Developer workstation to release

Archives, signing identities, notarization credentials, generated DMGs, and
GitHub release operations cross from a developer machine into the public
software supply chain. Credentials must come from the Keychain, 1Password, a
secret manager, or protected environment variables and must never be written to
the repository, logs, command examples containing real values, or scan output.

### Static website

Content in `docs/` is publicly served. Links, scripts, redirects, embedded
content, and downloadable release references must not introduce script
injection, reverse-tabnabbing, misleading downloads, or an untrusted release
origin.

## Security Invariants

### Updates and release integrity

- Only the expected GitHub repository and approved HTTPS origins may supply
  release metadata and update assets.
- Redirects, HTTP status, response size, asset type, and final URL must be
  validated.
- A candidate application must have the expected bundle identifier,
  Developer ID Team Identifier, valid code signature, and accepted
  notarization/Gatekeeper assessment before installation.
- Mounted-image paths must be canonicalized and must not escape the intended
  mount or select an unexpected application.
- Installation must not use shell interpolation or attacker-controlled
  executable paths.
- Failed validation must leave the existing application intact.
- Temporary downloads and mounts must be uniquely staged and cleaned up on
  success, cancellation, and failure.
- Release builds retain the hardened runtime. New entitlements or permissions
  require a least-privilege justification.

### Authentication and dismissal

- When the privacy lock is armed, a successful response from the currently
  active `LAContext` is the normal dismissal path.
- Callbacks from an invalidated, timed-out, pre-sleep, or superseded
  authentication context must not dismiss a later session.
- Concurrent authentication dialogs must not stack.
- Sleep/wake and teardown invalidate obsolete authentication state.
- Failure and cancellation keep the overlay visible, except for the documented
  no-device-passcode safety behavior that prevents trapping the user.
- The application does not capture or log input contents, credentials,
  passcodes, or biometric data.

### Settings import and export

- Imported data has a reasonable maximum size and a supported top-level schema
  version.
- Numeric values are finite and clamped to supported ranges.
- Strings are length-bounded before they reach display or font APIs.
- Unknown or unsafe types do not alter application state.
- Imports preserve the existing password-lock and hotkey configuration.
- Exports omit the password-lock and hotkey configuration.
- File access remains limited to files explicitly selected by the user.

### Local data and privacy

- Settings are stored locally in `UserDefaults`.
- Custom messages and preferences are not transmitted as telemetry.
- Network access is limited to update checks/downloads and links explicitly
  opened by the user unless a new feature is deliberately reviewed.
- Logs and errors do not expose secrets, sensitive local paths, authentication
  details, or imported file contents.

### Process execution and filesystem changes

- External commands use fixed absolute executable paths and argument arrays.
- Untrusted data is never concatenated into a shell command.
- File replacement is staged, validated, recoverable, and limited to the
  intended application bundle.
- Build and packaging scripts quote paths, fail safely, and clean only the
  exact temporary locations they created.

### Rendering and availability

- File I/O, networking, logging, `UserDefaults`, and avoidable allocation stay
  out of per-frame and per-glyph paths.
- Malformed settings or unusual display configurations must not cause an
  unbounded allocation, persistent hang, or crash loop.
- Global event monitors are removed during teardown and do not record input
  contents.

## Current Priority Review Surfaces

Review the current source rather than assuming these areas are safe:

1. **In-app updater** in `TestApp/AppDelegate.swift`. At the time this policy
   was written, the flow selected a `.dmg` URL from GitHub release metadata,
   mounted it, and copied `Cyph3rfall.app` over the running bundle. Treat
   signature, Team Identifier, notarization, path, redirect, size, rollback,
   and partial-install checks as priority evidence requirements.
2. **Authentication state machine** in `TestApp/AppDelegate.swift`, especially
   timers, sleep/wake, stale `LAContext` callbacks, and repeated input.
3. **Event monitors** in `TestApp/FullScreenWindow.swift`.
4. **JSON import** in `Shared/Cyph3rfallSettings+JSON.swift` and
   `Shared/PreferencesWindowController.swift`, including file-size limits and
   schema validation.
5. **Release configuration** in `project.yml`, `TestApp/Info.plist`, and
   `scripts/make-dmg.sh`.
6. **Static website** under `docs/`.

No `.entitlements` files are currently tracked or assigned by `project.yml`.
Older notes under `memory-bank/` that describe entitlement files are historical
and must not be treated as the current configuration.

## Finding Criteria and Severity Context

### Critical or high priority

- Remote or supply-chain code execution.
- Installing an application that is unsigned, signed by the wrong team,
  improperly notarized, or sourced from an unexpected repository or path.
- Exposure of signing, notarization, GitHub, or release credentials.
- Arbitrary file overwrite or command execution through update, import,
  packaging, or path handling.
- A change that disables hardened runtime or materially weakens release
  integrity without explicit, reviewed justification.

### Medium priority

- Reliable dismissal of an armed privacy overlay without the documented
  authentication behavior.
- Stale authentication callbacks that dismiss a later session.
- Persistent denial of service or crash loops from plausible imported files,
  release responses, or display configurations.
- Unexpected disclosure of a custom message, settings, local paths, or
  authentication details.
- Unnecessary permissions, entitlements, event monitoring, or network access.
- Update failures that can corrupt or partially replace the installed app.

### Low priority or hardening

- Local crashes requiring implausibly large, explicitly selected input.
- Missing defense-in-depth where the existing trust boundary remains intact.
- Error messages that reveal low-sensitivity implementation details.
- Minor website-link hardening or release-process improvements without a
  credible exploit path.

### Normally not security findings

- Visual glitches, animation quality, or ordinary performance regressions
  without an availability or privacy impact.
- Bypassing the overlay with administrator/root control, a compromised macOS
  account, or a compromised operating system.
- Behavior that correctly reflects the documented fact that the overlay is not
  a macOS lock screen.
- Vulnerabilities requiring control of the developer's signing identity or
  GitHub account, unless the report demonstrates missing defense-in-depth that
  would materially limit that compromise.

## Validation Expectations

A useful finding should identify:

- the affected revision and exact source location;
- attacker-controlled input or precondition;
- the trust boundary crossed;
- source-to-sink or state-transition evidence;
- realistic reachability and user interaction;
- impact and severity rationale;
- counterevidence and remaining uncertainty;
- a bounded remediation and a way to verify it.

Use safe, non-destructive validation. Do not access real credentials, publish
releases, replace the installed application, weaken the developer machine, or
retain private source excerpts outside approved storage. A successful scan or
build is evidence of coverage, not proof that the software is secure.

## Reporting a Vulnerability

Prefer GitHub's private vulnerability-reporting or Security Advisory workflow
for the `ikaazu/Cyph3rfall` repository when available. If private reporting is
not available, contact `dev@cyph3rfall.app` with:

- a concise description and expected impact;
- affected versions or commit;
- reproduction steps or a minimal proof of concept;
- relevant logs or screenshots with secrets removed;
- suggested remediation, if known.

Do not open a public issue for an unpatched vulnerability that could put users
or the update supply chain at risk. Do not include credentials, private keys,
notarization passwords, personal data, or destructive payloads in a report.

## After a Fix

- Reproduce the original issue against the patched revision.
- Add the smallest practical automated or manual regression check.
- Re-run the relevant security scan and review its coverage gaps.
- Verify signing, hardened runtime, notarization, and update behavior when the
  fix touches the release path.
- Update this policy when the trust model, permissions, network destinations,
  stored data, or security claims change.
