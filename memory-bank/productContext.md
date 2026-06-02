# Product Context — Cyph3rfall

## Problem Statement

No modern macOS screensaver does Matrix-style rain well. Existing options are either Windows-only, abandoned, or use the deprecated macOS screensaver framework. The original WizardsOfTheCoast-era tools no longer exist. MatrixMania (Windows) was the reference point.

## dAId Development Model

Cyph3rfall is built using **Directed AI Development** — not vibe coding, not traditional development. The human (Greg Stock) holds the vision, makes product decisions, and owns the product. Claude Code handles implementation. Every feature is conceived and directed by the human; the AI handles the Swift and catches the bugs.

This is explicitly called out on the website and in the About panel.

## User Goals

| Goal | How Met |
|------|---------|
| Ambient digital rain aesthetic | CVDisplayLink-driven animation, 60+ glyph types |
| Works on all my screens | Multi-monitor, simultaneous coverage |
| Doesn't get in the way | Menu bar only, no Dock icon, LSUIElement=true |
| Activates automatically when idle | Configurable 1–30 min idle threshold |
| Locks the screen | Touch ID / Apple Watch auth to dismiss |
| Looks great, feels polished | 9 colour presets, glow, Chromafall, clock overlay |
| No friction to install | Notarized DMG — drag to Applications, run |

## Release History

| Version | Date | Key Change |
|---------|------|-----------|
| v1.0 | Early 2026 | Initial release (not notarized) |
| v1.1 | May 2026 | Tabbed settings, column spacing, clock colour presets, settings backup, auto-update check |
| v1.2 | May 2026 | **First notarized release.** Wide column default, density warning at 151%, version comparison fix |

## Backlog (Planned Features)

See `progress.md` for full list. Top items:
1. Auto-updater (in-app download + install + restart)
2. UI & Performance overhaul (HIG, sidebar settings, M1–M5 optimisation)
3. Color cycle mode ("Prismafall" — slow palette drift through all 9 presets)
4. "Start Now" shortcut display in menu
5. Branded DMG installer (drag-to-Applications background)
6. Windows companion app (Tauri, post macOS feature stability)
