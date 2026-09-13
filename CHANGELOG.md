# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-09-13

### Fixed

- **The updater hung instead of installing.** `applicationShouldTerminate` returned
  `.terminateLater` and sent its reply from a `Task { @MainActor in ... }`. That is fine for a
  ⌘Q, but the updater calls `NSApp.terminate` from inside a main-actor closure — so the reply
  could never be scheduled, the app never quit, and the helper waiting for it never swapped the
  bundle. The update appeared to start and then quietly did nothing. The delegate now saves
  synchronously and returns `.terminateNow`, and the updater arms a hard-exit fallback on the
  main queue before asking AppKit to quit, because "the app would not quit" is the worst way an
  updater can fail.
- Verified end to end afterwards: a 0.1.0 build auto-updated itself to 0.1.1 in place,
  relaunched, left no backup behind, kept its seven stickers and settings, and the replaced
  bundle passed `codesign --verify`.

> **0.1.0 and 0.1.1 cannot auto-update** — they carry the hang above. Install 0.1.2 by hand
> once; from 0.1.2 onward the updater works.

## [0.1.1] - 2026-09-13

### Fixed

- **One animated GIF could pin 30–45% of a CPU core.** Everything showed up inside ImageIO's
  GIF decoder, so the fix was to stop asking it for work that was not needed. Three separate
  causes, each measured on the same 4.3 MB / 630×824 / 96-frame GIF:
  - The decode target was `decodePixelLimit × display scale` (640 px) regardless of how large
    the sticker actually was, so a 200 pt sticker was decoded at 640 px. Decoding now targets
    the sticker's real pixel size, with the preference acting as a ceiling.
  - Reducing by a small factor was *more* expensive than not reducing: ImageIO's thumbnail path
    decodes the frame in full and then resamples it, so 630×824 → 640 cost twice what 630×824
    cost. Reductions of less than half now skip the thumbnail path and let the GPU scale.
  - The frame cache could not hold a whole animation, so every loop re-decoded every frame.
    When an animation fits in ~96 MB the cache now grows to hold all of it, so each frame is
    decoded once ever instead of once per loop. The second and third points are coupled — a
    downscale that looks expensive per frame pays for itself if it makes the animation
    cacheable — so they are decided together.

  Result: that single GIF went from **43% of a core to 0.4%**, and seven stickers together from
  **45% to 2.5–3.6%**. Memory for those seven went from ~91 MB to ~146 MB; the cache may hold
  tens of MB per sticker, with a shared 192 MB ceiling across all of them.

## [0.1.0] - 2026-09-13

### Added

- **Built-in updater.** MemeDesk now checks GitHub Releases for a newer version and replaces
  itself **in place** — no disk image to mount and drag. Settings → Updates has the switches:
  check automatically (on by default), download and install automatically (off by default,
  because it restarts the app), plus a manual **Check Now**. A dot appears on the menu bar
  panel's settings button when a version is waiting.
- Update archives are verified before anything is installed: a SHA-256 checksum always, and an
  Ed25519 signature on top of it once a public key is configured (see `Scripts/sign_update.py`).
  With a key configured a missing signature is a hard failure, never a silent downgrade.
- Releases now ship `MemeDesk-x.y.z.zip` (+ `.sha256`, and `.ed25519` when the signing secret is
  set) next to the dmg. The dmg stays for first-time installs.

### Changed

- **`desk.json` no longer breaks when preferences gain a field.** `Preferences` used to rely on
  synthesised `Codable`, so any unknown/missing key made the whole snapshot fail to decode —
  and `Stage.load()` swallows that with `try?`, which would have silently wiped the desk layout
  of anyone upgrading. It now decodes field by field with defaults.
- Update traffic bypasses the URL cache entirely. `URLCache` applies heuristic freshness from
  `Last-Modified`, which could serve a stale `.sha256` — a changed archive would then still
  compare equal, i.e. fail **open**.
- **"Up to date" is decided by the version number, not by what assets a release happens to
  carry.** A release that is not newer than the running build used to be reported as a failed
  check when it had no zip attached. Now the comparison comes first and the missing archive only
  matters when the release really is newer.
- **"Last checked" records the attempt, not only the success.** Previously a failed check left
  the timestamp untouched, so Settings could sit on "Never checked" forever while checks were in
  fact running.
- Update checks write to the system log (`subsystem com.memedesk.app`, `category update`), so a
  failure in the field can actually be diagnosed:
  `log show --predicate 'subsystem == "com.memedesk.app"' --last 10m --info`
- Building from source still needs the full Xcode; `make zip` / `make release` join the existing
  release targets.

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
