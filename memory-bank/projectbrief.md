# Project Brief — Cyph3rfall

## One-Line Vision

A modern, native macOS Matrix-style rain screensaver — built from scratch because the one I wanted didn't exist yet.

## Background

Cyph3rfall is a macOS menu bar application that displays a Matrix-style falling-glyph rain animation across all connected displays. Built as a personal project by a non-developer using Claude Code (dAId — Directed AI Development). The project began because no existing macOS screensaver did this well for modern hardware.

## Core Requirements

### Functional
- Full-screen Matrix rain across all connected displays simultaneously
- Menu bar icon (Ξ) — no Dock icon
- Idle activation (configurable threshold: 1–30 min, or never)
- Sleep/lid-close activation
- Global keyboard shortcut for instant activation
- 9 colour presets (Green, Amber, Cyan, White, Purple, Blue, Red, Orange, Pink)
- Chromafall mode — per-stream random colour from all 9 presets
- Message overlay — phrase hidden in the rain, revealed as columns pass through
- Clock overlay — time and date with slow burn-in-prevention drift
- Password lock — Touch ID / Apple Watch / Face ID to dismiss
- Settings backup — export/import as JSON
- Auto-update check via GitHub Releases API
- Launch at login
- Multi-monitor support

### Non-Functional
- macOS 14 Sonoma or later
- Apple Silicon + Intel universal (arm64 + x86_64)
- Developer ID signed and Apple Notarized
- No third-party dependencies in the main app
- Pure Swift + AppKit — no screensaver framework
- 60 fps render target on M-class chips (30 fps internal cap with atlas rendering)

## Audience

- Primary: Personal use (developer + gaming group)
- Future: Public release with possible small fee if cloud/connectivity features added

## Repository

- Code: `https://github.com/ikaazu/Cyph3rfall`
- Website: `https://cyph3rfall.app` (GitHub Pages / Cloudflare Workers)
- Contact: `dev@cyph3rfall.app`

## Current Release

**v1.2** — First notarized release. Signed: Developer ID Application: Gregory Stock (GHXKLLWQPM).
