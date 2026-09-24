# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.8] - 2026-09-24

A regression 0.1.7 introduced in the motion engine, and the packaging policy reversed.

### Fixed

- **Dragging a settled gravity sticker made it twitch, then slam into the floor.** 0.1.7 fixed
  "a sticker that has come to rest cannot be woken by dragging" by clearing `sleeping` whenever
  the position changed externally. But *waking* the engine while the mouse is still holding the
  sticker is exactly the wrong half of the fix: the engine and the mouse then both write the
  window position thirty times a second, so the sticker jitters under the cursor, and `vy` keeps
  accumulating gravity for as long as the drag lasts, so letting go launches it downward.

  Measured with a harness that drives the real `MotionEngine.swift` (stub `MotionMode`, script
  compiled twice — once against the 0.1.7 logic, once against the fix):

  | | 引擎在拖拽 30 帧里插手的次数 | 松手后头几帧的位移 |
  |---|---|---|
  | 0.1.7 | **30 / 30** | +11.8, +10.2, +8.6 … 每帧**向上**——它在被地板弹回来 |
  | 0.1.8 | **0 / 30** | −1.6, −3.1, −4.7 … 从静止平滑加速下落 |

  Dragging is now a first-class state rather than an inference from "the position moved":
  `MotionEngine.hold(_:)` / `release(_:)` suspend the physics for that instance, and
  `MotionEngine.update` returns `nil` — "do not touch it this frame" — so the caller skips
  `applyMotion` as well. Releasing keeps the velocity at zero, so it starts falling from rest
  instead of inheriting whatever the drag accumulated.

### Changed

- **Releases are arm64-only again.** 0.1.7 shipped a universal binary, which doubles the
  download (zip 0.76 MB → 1.34 MB) in order to serve Intel Macs on the last macOS that supports
  them. Not worth it. Intel users build from source, which is architecture-agnostic and which
  the README now says. `Scripts/build.sh` carries an `EXPECTED_ARCH` constant and
  `check_artifacts.sh` asserts the architecture is exactly that, so switching back is one line
  plus one check.
- **The shipped binary is stripped.** The symbol tables are a large fraction of a Swift binary —
  `__LINKEDIT` was about 63% of each slice. `strip -x` takes a slice from 2.23 MB to **0.96 MB**
  (−57%), and still −32% once inside the zip. It runs **before** `codesign`; modifying a binary
  after signing invalidates the signature. Local symbols are not needed at runtime and debug
  symbols live in the separately generated `.dSYM`, so crash symbolication is unaffected. The
  artefact check now also flags a binary that looks unstripped, because "correct but twice the
  size" is invisible on CI.

### Notes

- The motion harness lives in `/tmp/memedesk-fixes/motion-drag/` and compiles the real
  `MotionEngine.swift`, so it keeps working as long as that file stays free of AppKit — which is
  the same property that lets the menu bar icon file be dumped to PNG for visual checking.

## [0.1.7] - 2026-09-23

A full self-audit turned up fourteen defects across the state machine, the updater and the
release tooling. Two of them were the kind that quietly do nothing at all, and four were in the
CI and packaging path, which had never verified anything about what it produced.

### Fixed

- **Every preference change was silently discarded whenever "restore last desk" was off.**
  `Stage.saveNow()` opened with `guard !archiveIsFrozen else { return }`. The freeze exists so
  that an empty-desk start is not written over the archive, but it swallowed every preference
  write as well — including the one that turns `restoreSession` back on, which is the very action
  the freeze was added to protect. To see it: turn the setting off, quit, relaunch (empty desk),
  turn it back on, quit, relaunch — the desk is still empty and the setting is off again. The
  freeze now covers only `stickers`: preferences are written while frozen, and the layout that is
  already on disk is carried over untouched.
- **"Automatically download and install updates" never downloaded anything.** `checkForUpdates`
  set `busy = true` with `defer { busy = false }` and then called `await download(...)` while
  `busy` was still true — and `download` opens with `guard !busy else { return }`. The `defer`
  only runs when the whole async function returns. The check phase is its own function now, which
  owns `busy` and has released it by the time it returns.
- **A failed checksum fetch silently skipped verification.** The hash block was an
  `if let … = try? …` chain: a missing `.sha256` asset, a transient network error swallowed by
  `try?`, or an unparsable file all fell through to *no verification at all* — while the README
  says the checksum is always checked. It is a hard failure now: no checksum, no install.
- **A gravity sticker that had come to rest could not be woken by dragging it.** `MotionEngine`
  returned early on `state.sleeping` *before* writing the state back, so the re-anchor for an
  external move was thrown away — the sticker stayed where the mouse let go. The external-move
  branch clears `sleeping` now. (`wake(_:)` was dead code with no callers at all.)
- **The 30 Hz motion ticker never idled.** `ensureMotionLoop` asked whether any sticker had
  `motion != .still`, never whether any of them was still awake, so a desk where everything had
  settled kept a timer running forever — contradicting both file headers. It now also requires
  `hasAwakeMotion`, and `Stage.update` wakes a sticker whose **centre** actually moved (centre
  only: nudging the opacity must not drop a settled sticker again). Fullscreen pause stops the
  loop too, since every sticker window is ordered out at that point.
- **`motionSpeed` meant different things in different modes.** Bounce multiplied the slider into
  the initial velocity *and* into the per-step displacement (so quadratic, but only at startup),
  gravity squared it consistently, and wander and follow-cursor were linear. Speed is applied
  once, at the displacement step, for both of the velocity modes now — linear everywhere, and a
  change mid-flight takes effect immediately.
- **The sticker menu opened from the menu bar panel** did not freeze motion or lower the window
  below the menu, both of which the desktop right-click path has always done. A sticker on the
  floating layer could cover its own menu.
- **A new sticker could be placed off the left edge of the screen.** The position used `min()` as
  a clamp: at the maximum default size (600) and a 3.2 aspect the expression goes negative and
  `min()` picks the *more* out-of-range value. The bound is clamped first now. The stagger offset
  was also being counted twice — `configs.count` grows inside the loop.
- **`ThumbnailCache` had no in-flight de-duplication.** Two concurrent requests for the same
  uncached file both decoded it, and the second `store` left a duplicate key in the LRU order
  list, so the earlier eviction dropped an entry that was still in use.

### Tooling and CI

None of the following had ever been verified by anything.

- **No one asserted that the version numbers agree.** They are hand-edited in three places and
  were only ever *read* by the packaging scripts. A tag that disagrees with `Info.plist` produces
  a release whose app reports an older version — and because `release.version > current` then
  holds forever, the updater offers the same update on every launch. `Scripts/check_version.sh`
  asserts the three places agree, and both workflows pass the tag in as well.
- **The release notes could be published empty, silently.** `awk … | sed … > release_notes.md`
  writes zero bytes and returns 0 when the CHANGELOG has no `## [` heading, and also when the
  file is missing entirely — the step still succeeded, so the release went out with an empty
  body. `Scripts/release_notes.sh` sets `pipefail`, refuses an empty result, and refuses a
  section whose heading is not the expected version.
- **The artefacts were arm64-only.** `lipo -info` on the shipped binary says as much; CI runs on
  an arm64 runner so it could never notice; and the README claims macOS 13, which plenty of Intel
  Macs run. `build.sh` and the Makefile build `--arch arm64 --arch x86_64` now, and abort if the
  result is not universal. Note that the first attempt at this failed on CI in a way worth
  recording: `cp "$ROOT/.build/release/MemeDesk"` copied a **thin** binary even though the log
  above it said "Create universal binary MemeDesk" and "Build succeeded". `.build/release` is a
  symlink to whatever the *previous* build produced, and a preceding single-architecture
  `swift build` uses a different (older) build system with a different product directory, so the
  symlink still pointed at the arm64 file. The script now locates the product by inspecting it
  with `lipo` and skipping `*.dSYM/*` — the DWARF file inside a dSYM is also a universal Mach-O
  with the same name.
- **Ed25519 was wired on one side only.** The public key in `Info.plist` is empty, so a published
  `.ed25519` would never be checked — decoration. In the other direction, filling in the key
  without configuring the CI secret makes every update fail hard at `signatureUnavailable`.
  `Scripts/check_update_signing.sh` refuses to build when only one of the two sides is set.
- **`Scripts/check_artifacts.sh` is new** and runs in both workflows. It checks the architecture,
  `minos` against `LSMinimumSystemVersion`, that all three artefacts exist, the zip's top level,
  the checksum against the zip, that the DMG mounts, and that the signature's presence matches
  the public-key configuration.
- `make_dmg.sh` fell back to version `1.0.0` and `make_zip.sh` to `0.0.0` when the plist could
  not be read, so a single release could ship two differently-named artefacts. Both fail loudly
  now. They also self-verify what they produce: the DMG is mounted and unmounted, the written
  `.sha256` is recomputed and compared, and a signature that came out empty is an error.
- `generate_samples.py` called `ffmpeg` without checking that it exists, so on a machine without
  it the script crashed *after* rendering 48 frames, and the "skipped" message below was
  unreachable.
- `make_menubar_icons.py` raised a bare `ValueError: zero-size array to reduction operation
  minimum` when background removal left no subject at all. It now says what happened and what to
  try instead.
- CI builds with `-strict-concurrency=complete` now, and checks the release-notes extraction.
  It previously did neither.

### Notes

- Every item here was reproduced by reading the code or by running the command. The two most
  severe had never been noticed because each of them degrades silently instead of failing.
- ⚠️ Shell gotcha worth remembering: a `$VAR` immediately followed by a full-width character
  (`$OUT（`) makes bash swallow the multi-byte bytes into the variable name and fail with a
  confusing `unbound variable`. Five spots in the new scripts needed `${VAR}`.

## [0.1.6] - 2026-09-21

The two "Jimi" menu bar faces were rendering as a pale, hollow ghost of the photographs. The
quantisation's polarity was inverted, and the tone curve had no white point, so the brightest
part of the image — the cat's face — landed on level 0 (fully transparent) and the rest of the
animal collapsed onto level 1.

### Fixed

- **The two "Jimi" faces were inverted.** `make_menubar_icons.py` mapped *dark* to opaque
  (`round((1 - t) * 3)`), so the brightest region — the face — became fully transparent and
  everything else piled onto level 1, alpha 85. The measured distribution was 37 / 36 / 18 / 8
  per cent: half the tile parked on the faintest level that is visible at all. It is now
  `round(t * 3)`, i.e. what is bright in the photograph is what gets drawn.
- **Inverting alone was not enough — the face was still washed out.** A photograph's face is a
  broad midtone, so half of it still landed on the two semi-transparent levels. A levels pass
  now sits on top of the 6%/94% percentile normalisation: raising the black point is what makes
  the features genuinely transparent, and **lowering the white point is what makes the face
  solid**. Level 3 went from 8% of the tile to 36%.
- **The outline was aliased.** The silhouette was a hard mask (`np.where(mask, lvl, 0)`), which
  left a ring of stair-stepping around the edge. The tone map is multiplied by the resampled
  mask instead, so the edge is antialiased.
- **The two faces read a size larger than the vector ones.** They filled 100% × 93% of the
  canvas while the eight vector faces are discs of about 86%. In the same row they looked both
  bigger and heavier; they are scaled to 86% now.

### Changed

- `Scripts/make_menubar_icons.py` lost its entire feature-detection path — `feature_mask`,
  `components`, the contrast and area thresholds, and the dilation that guaranteed a minimum
  stroke width. All of it only ever served the "solid silhouette with the dark parts knocked
  out" experiment, which was tried and rejected: binarising the subject throws away exactly the
  tonal structure that makes the photograph recognisable. The script is now background removal
  plus a tone map, and it is shorter than it was in 0.1.4.
- `release.yml` no longer drops the version from the release body. It rewrote
  `## [0.1.5] - 2026-09-21` to `## 2026-09-21`, discarding the version number — which is why the
  bodies of the 0.1.2 through 0.1.5 releases have no version in their heading. They now read
  `## 0.1.6 — 2026-09-21`.
- Both READMEs described the faces as "solid where dark and transparent where light", which is
  the wrong way round; corrected.

### Notes

- Every comparison sheet was rendered at **Retina device pixels** — 18 pt is 36 px there, and
  the 54 px tile is resampled *down* to that. Rendering at 18 px instead draws detail the menu
  bar never shows and makes the edges look sharper than they are. The earlier sheets in this
  round were wrong for that reason.
- The source photographs are attachments, not repository content — they live in the host's blob
  store. The generator reproduces the committed bitmaps from them byte for byte, which is how
  the two were confirmed to be the right pair.

## [0.1.5] - 2026-09-21

Six defects that the 0.1.3 self-audit turned up, all of them long-standing and none of them
obvious from reading the code.

### Fixed

- **`hideOnFullscreen` could never fire on a stacked display.** `CGWindowListCopyWindowInfo`
  returns Quartz bounds (origin at the top-left of the primary display, y downwards) and those
  were compared for **exact equality** against `NSScreen.frame`, which is Cocoa coordinates
  (origin bottom-left, y upwards). The two coincide on a single display — which is why it looked
  correct — but a display arranged above or below the primary mirrors y, so the comparison can
  never hold. The rect is converted first, and "covers this screen" is now a tolerance test.
- **Thumbnail decoding was running on the main thread.** `ThumbnailCache` is a `@MainActor`
  class, and the `static func` it called was inferred to be main-actor isolated as well — so the
  `await` inside `.task` was in fact a synchronous decode on the main thread, once per row. The
  decoders are `nonisolated` now and are reached through `Task.detached`, and probing the media
  kind (a file-header read) moved into the background with them. Measured: eight large GIFs
  decode in 123 ms while the main thread's longest stall is 3.0 ms.
- **A frame with `dt == 0` discarded all motion state.** `FrameTicker.reschedule()` zeroes
  `lastTimestamp` every time it restarts, so the first tick after any restart — pause/resume,
  frame-rate negotiation, leaving fullscreen — arrives with dt 0, and that case shared a guard
  with "motion has been switched off", which clears the state. Accumulated velocity and phase
  were thrown away, so a sticker already asleep on the floor dropped a second time after a
  pause. Only a genuinely disabled motion clears state now.
- **The bulk hide/show button read "Show all" on an empty desk.** `allSatisfy` returns true for
  an empty array. It now tests for empty first, and is disabled when there is nothing to act on.
  `MDIconButtonStyle` also dims while disabled — a `.disabled()` button that still looks
  pressable is worse than one that is not disabled at all.
- **Double-click to pause did not exist.** Both READMEs have documented "double-click: pause or
  resume that one instance" for some time, but `mouseDown` never looked at `clickCount` and
  `onTogglePlay` was never called. It is wired up now, and the second click of a double-click no
  longer opens a drag, so a small twitch of the mouse cannot shift the window.
- `Stage.update` had two branches that did the same thing (`markDirty()` is `scheduleSave()`).
  Collapsed, with the meaning of `publish` written down.

### Notes

- Every fix has a small harness that compiles the real source files and asserts against measured
  values, including a negative assertion that reproduces the multi-monitor bug and a timing test
  that shows the decode is off the main thread.
- Two of these still want a human: the dimmed button's appearance, and the double-click itself.
  Neither can be checked without eyes and hands on a real desk.

## [0.1.4] - 2026-09-21

### Added

- **A second group of menu bar faces: "Jimi".** Two icons — grinning and scratching head —
  derived from two photographs of the same cat. They are **quantised to four grey levels**
  (solid where dark, transparent where light) rather than drawn as vector shapes, because that
  is what keeps them recognisable as the original: at 36 px the face still reads. Reducing the
  same photographs to "a solid silhouette with the dark parts knocked out" does not work — the
  dark regions of a photo are connected shadows, not clean eyes and a mouth, so the result is an
  amorphous blob.
- The icon picker is now grouped ("Faces" / "Jimi"), with sub-headers shown only when there is
  more than one group.

### Changed

- `MenuBarIcon` gained a group. `image(pointSize:)` returns a decoded bitmap for the icons that
  carry one and falls back to the vector path for the rest.
- The quantised data is packed at two bits per pixel and embedded as base64 in
  `Sources/MemeDesk/UI/MenuBarIconBitmaps.swift`, so the app ships no extra image resource and
  that file still depends on nothing but AppKit — which is what lets it be compiled on its own
  and dumped to PNG for visual checking. `Scripts/make_menubar_icons.py` regenerates it from the
  source photographs.

## [0.1.3] - 2026-09-16

### Added

- **A choice of menu bar faces.** The status item now offers eight vector faces — smile,
  laughing, wink, surprised, cool, love, sad, angry — switchable in Settings and applied
  immediately, with no relaunch.

### Changed

- **The menu bar button is a template image now, not the app icon.** It used to shrink the
  512 px app icon (an orange rounded square) into 17 pt with `isTemplate = false`, which read
  as both heavier and smaller than the system's own glyphs. It is drawn as vector paths on a
  24×24 grid instead: a solid disc with the features knocked out, filling about 86% of an
  18 pt canvas, handed to the system as a template so it is black on a light menu bar and white
  on a dark one. The geometry is exercised by a standalone harness that dumps every face to a
  PNG — a menu bar cannot be screenshotted from here, so that is the only way to check shapes.
  `AppBrand.menuBarImage` is gone with it.

### Fixed

- **Removing a sticker from its right-click menu froze all motion until relaunch.**
  `Stage.menuInteractionCount` goes up when a menu opens and comes back down from a `defer` in
  `StickerView.rightMouseDown` — but that callback was a `[weak self]` closure over the *window
  controller*, and "Remove from desk" destroys that controller before the menu returns. The
  unwrap then failed silently, the count never came back down, and `ensureMotionLoop()` concluded
  motion was never needed again: gravity, bouncing, drifting and wandering all stopped until the
  next launch. The callback now captures `Stage.shared`, which outlives any single sticker, so the
  decrement is unconditional; only the window-level part is skipped when the controller is gone.
- **Turning off "restore the last session on launch" destroyed the saved desk.** The empty
  starting desk was written straight back to `desk.json` — once by the debounced save, again by
  the five-second periodic one — so switching the setting back on could not bring anything back.
  The archive is now frozen while a session starts empty, and released the moment the desk really
  changes, i.e. the first sticker the user adds, moves or edits. Measured both ways: the old
  build left 0 of 2 stickers, this one keeps all 2, and the archive still follows the user once
  they touch the desk.
- **"Clear desk" asks for confirmation.** It was a single click in the panel, the same size as
  its neighbours, with no undo. It now arms itself on the first click ("Confirm") and disarms
  after four seconds. Same behaviour in Settings.
- `Preferences` gains `menuBarIcon`. As with every other field it is decoded tolerantly, so an
  existing `desk.json` without it still loads in full — verified, along with an unknown icon name
  falling back to the default rather than failing the whole decode.

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
