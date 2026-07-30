# Repository Guidance for Coding Agents

## Scope

These instructions apply to the entire repository. More specific instructions
may be added in nested `AGENTS.md` files if a component later needs different
rules.

This repository contains **Cyph3rfall**, a native macOS menu bar application
that renders animated digital rain, activates after idle time, optionally asks
macOS Local Authentication before dismissal, checks GitHub Releases for
updates, and imports or exports visual settings as JSON.

## Sources of Truth

Use current source and configuration before historical documentation:

1. The user's current request.
2. This `AGENTS.md` and the closest nested agent instructions.
3. `SECURITY.md` for threat model, security invariants, and finding severity.
4. `project.yml`, `TestApp/Info.plist`, and current Swift source.
5. `memory-bank/` and other design documents as historical context.

Some memory-bank material is stale. For example, the live version is defined in
`TestApp/Info.plist`, and the current `project.yml` does not assign an
entitlements file. Do not make a current-state claim from the memory bank
without checking the source of truth.

## Repository Map

- `Shared/`: rendering, settings model, persistence, JSON import/export, and
  preferences UI.
- `TestApp/`: application lifecycle, menu bar UI, idle activation, global
  hotkey, full-screen windows, Local Authentication, and update installation.
- `project.yml`: canonical Xcode project definition.
- `Cyph3rfall.xcodeproj/`: generated Xcode project, committed for convenience.
- `docs/`: static website published at `cyph3rfall.app`.
- `scripts/make-dmg.sh`: release DMG packaging.
- `dmg-assets/`: DMG artwork.
- `memory-bank/`: historical decisions, product context, and release notes.

## Working Agreements

- Inspect `git status` before changing files and preserve unrelated user work.
- Prefer focused changes that extend existing types and patterns.
- Do not rewrite a component merely to modernize its style.
- Do not add a runtime dependency without explicit user approval and a concrete
  benefit that cannot reasonably be achieved with Apple frameworks.
- Do not edit `Cyph3rfall.xcodeproj` by hand. Edit `project.yml`, run
  `xcodegen generate`, and review the generated project diff.
- Do not change signing, hardened-runtime, bundle identifier, deployment
  target, app permissions, release credentials, or notarization behavior unless
  they are explicitly in scope.
- Never commit credentials, signing keys, notarization passwords, API tokens,
  private user data, or local machine paths containing sensitive information.
- Treat downloaded data, imported JSON, release metadata, URLs, filenames, and
  process arguments as untrusted at their boundary.
- For audits and recommendation-only tasks, do not modify application code.
  Separate observed facts, supported inferences, hypotheses, and proposals.
- Do not automatically update `memory-bank/` for routine work. Update it only
  when the user requests documentation or a durable architectural decision was
  intentionally made.

## Build and Validation

Prerequisites are macOS 14 or later, Xcode 16 or later, and XcodeGen.

List the project:

```bash
xcodebuild -list -project Cyph3rfall.xcodeproj
```

Regenerate the project only after changing `project.yml`:

```bash
xcodegen generate
```

Run a local compile without requiring signing:

```bash
xcodebuild \
  -project Cyph3rfall.xcodeproj \
  -scheme Cyph3rfall \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Validate the property list after changing it:

```bash
plutil -lint TestApp/Info.plist
```

There is currently no automated test target. For behavior changes, report the
manual checks performed and the untested areas. Relevant manual checks include:

- launch and menu reconstruction;
- idle and manual activation;
- dismissal with password lock off and on;
- sleep/wake while an authentication prompt is active;
- global hotkey registration, replacement, and removal;
- multi-display creation and teardown;
- JSON import/export, including malformed and oversized inputs;
- update check failure, cancellation, download, validation, install, and
  relaunch;
- rendering smoothness at maximum density on one and multiple displays.

Release archives, signing, notarization, DMG creation, GitHub releases, and
website deployment are explicit release operations. Do not perform them unless
the user specifically requests them. Never publish or overwrite a release as
an incidental verification step.

## Swift and AppKit Conventions

- Use Swift and AppKit; do not introduce SwiftUI without explicit approval.
- Prefer `final` classes for concrete controller and service types.
- Prefer value types for settings and serializable data.
- Keep declarations `private` unless wider visibility is required.
- Name files and types with `PascalCase`; use `camelCase` for functions,
  properties, and constants.
- Comment non-obvious intent, security boundaries, lifecycle behavior, and
  performance tradeoffs rather than restating the code.
- Keep UI work and AppKit state changes on the main thread.
- Avoid force unwraps for data influenced by files, the network, system state,
  or user configuration.

## Rendering and Performance Invariants

`Cyph3rfallView` and related glyph code are frame-sensitive. Do not put the
following work in `draw`, `externalTick`, display-link callbacks, or per-glyph
loops unless measurement proves it is safe:

- file or network I/O;
- `UserDefaults` access;
- font lookup;
- attributed-string construction;
- repeated `NSColor`/`CGColor` conversion;
- object allocation that can be cached;
- logging.

Preserve these established rules:

- Precompute rendering state in `rebuild()` and invalidate it only when inputs
  change.
- Invalidate `glyphAtlas` during rebuild rather than from a draw path.
- Construct stream colors through `StreamColor(preset:)`.
- When settings change, ensure the rebuild size guard cannot leave stale
  caches.
- Draw `NSImage` in flipped views with `respectFlipped: true` and pass image
  alpha through the drawing `fraction`.
- Do not change the density warning threshold (`value <= 1.51`) without an
  explicit product decision.

Performance recommendations must be measurement-led. Identify the workload,
hardware, display count and refresh rate, build configuration, sampling method,
and before/after result. Avoid describing a speculative micro-optimization as a
measured bottleneck.

## Security-Sensitive Areas

Read `SECURITY.md` before security work. The highest-value review surfaces are:

- `TestApp/AppDelegate.swift`: Local Authentication state and update
  download/install/relaunch.
- `TestApp/FullScreenWindow.swift`: global/local event monitors and dismissal.
- `TestApp/IdleWatcher.swift`: idle-state transitions.
- `TestApp/HotkeyManager.swift`: Carbon callback lifetime and input handling.
- `Shared/Cyph3rfallSettings+JSON.swift` and
  `Shared/PreferencesWindowController.swift`: untrusted settings files.
- `project.yml`, `TestApp/Info.plist`, and `scripts/make-dmg.sh`: signing,
  permissions, packaging, and release integrity.
- `docs/`: external links and static-site content.

The password-lock feature is a casual privacy overlay, not an operating-system
lock screen or authorization boundary. Preserve that product claim in code,
documentation, and findings.

### Update path

Changes to update handling must preserve or improve all of the following:

- bind release metadata and assets to the expected GitHub repository and HTTPS
  origins;
- validate HTTP status, redirects, response size, and expected asset type;
- stage downloads safely and clean up mounts and temporary files on every path;
- verify the candidate app's bundle identifier, Developer ID Team Identifier,
  code signature, and notarization/Gatekeeper result before replacement;
- avoid following attacker-controlled paths inside a mounted image;
- avoid shell interpolation; use fixed executable URLs and argument arrays;
- do not replace the running app until validation succeeds;
- provide a recoverable failure path and avoid leaving a partially replaced
  bundle.

Do not assume that HTTPS transport or a GitHub release URL alone proves the
downloaded application's authenticity.

### Authentication and dismissal

- A locked overlay may dismiss after a successful result from the currently
  active `LAContext`.
- Results from invalidated, timed-out, pre-sleep, or superseded contexts must
  not dismiss a newly armed overlay.
- Keep concurrent prompts from stacking.
- The documented no-passcode behavior prevents trapping a user and is not an
  OS security guarantee; call out any change to that behavior explicitly.
- Never capture, store, or log keys, clicks, biometric details, credentials, or
  authentication error data beyond what is necessary for safe user feedback.

### Settings files

- Preserve `requirePassword` and hotkey settings when importing visual
  settings.
- Do not export those security-sensitive settings.
- Bound input size before parsing, validate the top-level schema and version,
  clamp numeric values, limit strings, and reject unsafe or unsupported types.
- File access should remain user-selected and narrowly scoped.

## Code Review Rules

### Update supply chain

- Flag any path that can install or execute downloaded code without verifying
  the expected bundle identifier, Developer ID Team Identifier, code signature,
  and notarization/Gatekeeper result. The safe path is validation before any
  copy into the installed application.

### Authentication lifecycle

- Flag stale or concurrent `LAContext` callbacks that can dismiss a later lock
  session. The safe path is identity-checking the active context and
  invalidating it on timeout, sleep/wake, teardown, and replacement.

### Process and filesystem operations

- Flag shell-string construction, untrusted executable paths, unvalidated DMG
  paths, unsafe mount contents, broad file permissions, and non-atomic
  replacement. Use fixed system executables, argument arrays, validated
  canonical paths, and recoverable staging.

### Settings trust boundary

- Flag unbounded file reads, unvalidated imported fields, or import/export of
  the password-lock and hotkey configuration. Validate and clamp before state
  reaches rendering, authentication, or hotkey code.

### Permissions and signing

- Flag weakened hardened-runtime or signing settings and newly requested
  entitlements without a documented feature requirement and least-privilege
  analysis.

### Rendering regressions

- Flag file I/O, networking, defaults access, logging, or repeatable allocation
  added to frame, glyph, or display-link hot paths. Move the work to cached
  rebuild or lifecycle boundaries.

## Definition of Done

Before handing off a change:

- review the diff for unrelated or generated noise;
- run the smallest relevant validation commands above;
- report build/test/manual-check results honestly;
- describe security, privacy, performance, compatibility, and release impact;
- identify untested paths and assumptions;
- update user-facing documentation when behavior or security claims change;
- never claim that a scan, successful build, notarization, or AI review proves
  the application is secure.
