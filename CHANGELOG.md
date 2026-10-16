# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-10-16

### Changed

- **Menu bar icons are larger.** The artwork now fills 98% of the 18 pt canvas instead of 86%,
  and the eight vector faces and two photo faces are scaled to match.

### Fixed

- **Rotated video played on its side** — portrait phone clips whose audio track was stripped,
  which is the default path for any video with sound.
- **Dropping a file on the app icon in the Finder did nothing.** Only `memedesk://` URLs were
  handled; file URLs were discarded without a word.
- **Preference changes waited for an unrelated refresh** before taking effect: pause on battery,
  hide when fullscreen, pause when occluded, and the motion-speed floor.
- **A drag interrupted by hiding, locking or click-through froze that sticker's motion** until
  relaunch.
- **A failed or interrupted self-update could leave no app at all.** The new bundle is staged
  beside the old one before anything moves, the rollback also runs on a signal, and the old build
  is relaunched when the swap cannot complete.
- **The "clear desk" confirmation survived closing the panel**, so a single click after reopening
  cleared the desk.
- Window position was remembered per language, so switching languages re-centred the Library and
  Settings windows.
- `MDButtonStyle` and `MDPrimaryButtonStyle` ignored the disabled state and the destructive role,
  so disabled buttons still looked pressable.
- Version comparison mishandled build metadata (`1.0.0+build-5` sorted below `1.0.0`) and numeric
  prerelease identifiers (`alpha.10` sorted below `alpha.2`).
- Resizing a sticker with Option-drag no longer restarts its motion.
- "Launch at login" is recorded only when the system accepts the registration.

## [0.1.8] - 2026-09-24

### Fixed

- **Dragging a sticker no longer fights the motion engine.** While the mouse holds a sticker the
  engine is suspended, and releasing resumes from rest rather than from the velocity accumulated
  during the drag.

### Changed

- **Releases are arm64-only again.** 0.1.7 shipped a universal binary, which doubles the download
  for everyone; Intel Macs are covered by building from source. Both READMEs say so.
- **The shipped binary is stripped**, halving the update archive (zip 1.34 MB → 0.58 MB).

## [0.1.7] - 2026-09-23

### Fixed

- **Preference changes were discarded whenever "restore the last session on launch" was off**,
  including the change that turns it back on. Preferences are saved in every case now; the
  freeze still protects the saved desk layout.
- **"Automatically download and install updates" never downloaded anything.** The check held its
  own busy flag across the download call, which then refused to start.
- **A missing or unfetchable `.sha256` skipped verification entirely.** It is a hard failure now.
- A settled gravity sticker can be dragged again and resumes motion on release.
- The 30 Hz motion loop stops once every sticker has settled, and during fullscreen pause.
- The motion-speed slider scales the same way in all six behaviours, and takes effect mid-flight.
- The sticker menu in the menu bar panel now freezes motion and lowers the window below the menu,
  as the desktop right-click menu already did.
- New stickers are no longer placed off the left edge of the screen when the default size is
  large and the sticker is wide.
- Concurrent thumbnail requests for the same file are decoded once.

### Changed

- CI asserts that the version agrees across `Resources/Info.plist`, `Xcode/project.yml` and this
  file, and that the release tag matches.
- The release body is taken from this file and the build fails if that section is missing or
  empty.
- CI builds with `-strict-concurrency=complete` and verifies the release artefacts.

## [0.1.6] - 2026-09-21

### Fixed

- **The two "Jimi" menu bar faces were inverted**: the cat's face was transparent and its
  features solid. Bright areas of the photograph are now the solid ones, and the face reads as
  solid instead of washed out.

### Changed

- The release body no longer loses the version number from its heading.

## [0.1.5] - 2026-09-21

### Fixed

- **`hideOnFullscreen` never fired on a display arranged above or below the primary one**, because
  Quartz window bounds were compared for exact equality against Cocoa screen frames.
- **Thumbnail decoding ran on the main thread**, once per visible row.
- **A frame with `dt == 0` discarded all motion state**, so a sticker already resting on the floor
  dropped a second time after a pause or a fullscreen transition.
- The bulk hide/show button read "Show all" on an empty desk, and disabled buttons now look
  disabled.
- **Double-click to pause now works.** Both READMEs documented it; nothing implemented it.

## [0.1.4] - 2026-09-21

### Added

- **Two more menu bar faces, "Jimi"** — grinning and scratching head, derived from photographs of
  a cat and quantised to four alpha levels so they stay recognisable at 36 px.
- The icon picker is grouped ("Faces" / "Jimi").

### Changed

- Quantised icon data is packed at two bits per pixel and embedded in the source, so the app
  ships no extra image resource.

## [0.1.3] - 2026-09-16

### Added

- **Eight menu bar faces** — smile, laughing, wink, surprised, cool, love, sad, angry — switchable
  in Settings with no relaunch.

### Changed

- **The menu bar button is a vector template image now**, not a shrunk copy of the app icon. It is
  black on a light menu bar and white on a dark one.

### Fixed

- **Removing a sticker from its right-click menu froze all motion until relaunch.**
- **Turning off "restore the last session on launch" destroyed the saved desk.**
- "Clear desk" asks for confirmation and disarms after four seconds.

## [0.1.2] - 2026-09-13

### Fixed

- **The updater hung instead of installing.** The app now saves synchronously and quits
  immediately, with a hard-exit fallback if AppKit does not comply.

> 0.1.0 and 0.1.1 cannot auto-update. Install 0.1.2 or later by hand once; after that the
> updater works.

## [0.1.1] - 2026-09-13

### Fixed

- **A single animated GIF could use 43% of a CPU core.** Decoding now targets the sticker's real
  pixel size, skips downscales smaller than half, and keeps a whole animation in cache when it
  fits — that GIF now uses 0.4%, and seven stickers together use 2.5–3.6%.

## [0.1.0] - 2026-09-13

### Added

- **Built-in updater.** MemeDesk checks GitHub Releases and replaces itself in place. Settings →
  Updates has automatic check, automatic install and a manual check.
- Update archives are verified before install: SHA-256 always, plus an Ed25519 signature once a
  public key is configured. A missing signature is a hard failure, never a silent downgrade.
- Releases ship `MemeDesk-x.y.z.zip` (with `.sha256`, and `.ed25519` when signing is configured)
  beside the dmg.

### Changed

- **`desk.json` no longer breaks when a preference gains a field**, and an unreadable preference
  can no longer wipe the saved desk layout.
- Update traffic bypasses the URL cache, which could serve a stale checksum and fail open.
- "Up to date" is decided by the version number, not by which assets a release carries.
- "Last checked" records the attempt rather than only the success.

## [0.0.2] - 2026-09-12

### Fixed

- The selection outline no longer lingers on the desktop after using a sticker's right-click
  menu.
- A sticker on the "floating above everything" layer no longer covers its own right-click menu.

### Added

- A demo animation in both READMEs.

### Changed

- Building from source needs the full Xcode; the build scripts pick it up automatically.

## [0.0.1] - 2026-09-08

First public beta.

### Added

- Desktop sticker playback for GIF, APNG, still images, MP4, MOV and M4V, with any number of
  simultaneous instances and full session restore.
- Three window layers and six motion behaviours (still, breathing, screen bounce, gravity
  hammock, follow cursor, wander).
- Per-instance size, opacity, playback speed, rotation, mirroring, click-through, lock,
  duplicate and remove.
- Menu-bar-only operation: status item, control panel, sticker library, settings, and a welcome
  window on first launch.
- `memedesk://` URL scheme for `add`, `hide`, `show`, `pause`, `resume` and `clear`.
- English and Simplified Chinese UI; launch at login via `SMAppService`.
- Power saving: one shared frame clock, decode-at-display-size, a byte-capped frame cache,
  audio-stripped video, and pausing when locked, on battery, behind a full-screen app or fully
  occluded.
- Build scripts for a standalone `.app` and a `.dmg`, plus an XcodeGen project.
