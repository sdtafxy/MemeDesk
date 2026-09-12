# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.2] - 2026-09-12

### Fixed

- The selection outline could linger on the desktop after using a sticker's right-click menu —
  most visibly after picking a motion behaviour or a layer. Clearing it no longer depends on the
  app losing focus (which often never happens after a menu): the outline now also drops the
  moment the menu closes, and any click landing outside the app clears it.
- The right-click menu was hidden behind its own sticker when the layer was set to
  "floating above everything". A `screenSaver`-level window sits above the pop-up menu, so the
  sticker is now lowered just below the menu for as long as the menu is open, and restored
  afterwards.

### Added

- A demo animation on the landing page of both READMEs (`Docs/demo.gif`).

### Changed

- Building from source now documents that it needs the **full Xcode**: SwiftUI's macro plugin
  (`SwiftUIMacros`) ships only with Xcode, so the Command Line Tools alone cannot compile the
  UI. `Scripts/build.sh` and the `Makefile` now pick up `/Applications/Xcode.app` automatically
  when `xcode-select` points at the Command Line Tools.

## [0.0.1] - 2026-09-08

First public beta. Feedback welcome — please open an issue with your macOS version and steps
to reproduce.

### Added

- Desktop sticker playback for GIF, APNG, still images, MP4, MOV and M4V, with any number of
  simultaneous instances and full session restore.
- Three window layers (behind desktop icons, above desktop icons, floating above everything) and
  six motion behaviours (still, breathing, screen bounce, gravity hammock, follow cursor, wander).
- Per-instance controls: size, opacity, playback speed, rotation, mirroring, click-through, lock,
  duplicate, remove.
- Menu-bar-only operation (`LSUIElement`): status item, control panel, sticker library and
  settings, plus a welcome window on first launch.
- `memedesk://` URL scheme for `add`, `hide`, `show`, `pause`, `resume` and `clear`.
- English and Simplified Chinese UI, switchable in Settings; follows the system by default.
- Launch at login via `SMAppService`.
- Power saving: a single shared frame clock, decode-at-display-size, byte-capped LRU frame
  cache, audio-stripped video playback, and automatic pausing when locked, on battery, behind a
  full-screen app or fully occluded.
- A hand-drawn app icon generated from one 1024 px master into both `.icns` (Finder / Dock) and
  `.png` (shown inside the app), so the icon is the same everywhere.
- Build scripts for a standalone `.app` and a distributable `.dmg`, plus an XcodeGen project.

### Notes

- The menu-bar panel is a self-managed `NSStatusItem` + `NSPopover` with a fixed, arithmetic
  size, so its layout cannot shift when stickers are added or removed.
- The whole UI shares one design language: white canvas, grey block buttons, one brand orange
  for primary actions (`Sources/MemeDesk/UI/Design.swift`).
