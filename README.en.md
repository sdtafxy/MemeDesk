<div align="center">

<img src="Resources/AppIcon.png" width="104" alt="MemeDesk icon">

# MemeDesk

**Keep your favourite memes looping on the macOS desktop, day and night.**

[中文文档](README.md)


GIF / APNG / still images / MP4 / MOV · any number at once · no Dock icon · bilingual

</div>

---

Memes are the universal currency of chat, but they lose their soul the moment you leave the
conversation. MemeDesk puts them where you actually look — right on the desktop, above the
wallpaper. Place as many as you like; drag, scale, rotate, bounce or make them chase your
cursor. They go quiet during full-screen video and rest when the screen locks.

## Features

- **Any number at once** — every sticker is an independent instance with its own settings; the
  desk is restored exactly as you left it (Security-Scoped Bookmarks).
- **GIF / APNG / PNG / JPG / HEIC / WebP / MP4 / MOV / M4V** — format detected from the
  extension, the UTType and the magic bytes; videos loop with their audio track stripped.
- **Three layers** — behind desktop icons, above desktop icons (default), or floating above
  everything.
- **Six behaviours** — still, breathing, screen bounce, gravity hammock, follow cursor, wander.
- **Per-instance controls** — size, opacity, playback speed, rotation, mirroring, click-through,
  lock, duplicate, remove — all from the right-click menu.
- **Low footprint** — oversized images are downsampled before decoding (adjustable threshold);
  playback pauses automatically when occluded, on battery, behind a full-screen app or when
  the screen is locked.
- **Menu bar only** — an `LSUIElement` app; nothing in the Dock or the App Switcher.
- **Bilingual UI** — English and Simplified Chinese; follows the system by default.
- **`memedesk://` URL scheme** — script it, bind it to a hotkey, drive it from Raycast or Alfred.
- **Six bundled samples** — the sticker library ships with ready-made examples, one click to place.

## Quick start

Grab the latest `MemeDesk-x.y.z.dmg` from [Releases](../../releases), open it and drag MemeDesk
into Applications.

> The build is ad-hoc signed. If Gatekeeper complains on first launch, right-click the app and
> choose **Open**.

Build it yourself (Xcode Command Line Tools only):

```bash
xcode-select --install          # skip if already installed
./Scripts/build.sh              # → dist/MemeDesk.app
open dist/MemeDesk.app
```

Run `./Scripts/make_dmg.sh` for a distributable disk image, or generate a full Xcode project:

```bash
brew install xcodegen
xcodegen -s Xcode/project.yml   # → MemeDesk.xcodeproj
open MemeDesk.xcodeproj
```

## Usage

| Action | Effect |
| --- | --- |
| Click the menu bar icon | Control panel: add, library, settings, bulk hide / pause |
| Drag a sticker | Move it (snaps to screen edges so it never gets lost) |
| `Option` + drag | Resize proportionally |
| Scroll wheel | Fine-tune size |
| Right-click | Size / opacity / speed / rotation / layer / behaviour / mirror / click-through / lock / duplicate / remove |
| Double-click | Pause or resume that one instance |
| Drop files on the library window | Place them on the desktop |
| `⌘ ,` | Open Settings |

The six buttons in the menu-bar panel: **Pause / Resume**, **Library**, **Settings**,
**Hide all / Show all**, **Clear desk**, **Quit**.

### URL scheme

```bash
open "memedesk://add?file=/Users/me/cat.gif"   # place a file
open "memedesk://hide"                          # hide everything
open "memedesk://show"                          # show everything
open "memedesk://pause"                         # pause playback
open "memedesk://resume"                        # resume playback
open "memedesk://clear"                         # clear the desk
```

### Three layers

- **Behind desktop icons** — sandwiched between wallpaper and Finder icons, the most native
  look. Note that macOS swallows mouse events below the normal window level, so interaction is
  unavailable in this mode.
- **Above desktop icons** (default) — covers desktop icons, sits under every app window.
- **Floating above everything** — covers even full-screen video.

## How it stays light

1. **One shared frame clock** — all instances share a single Timer whose rate is negotiated from
   the fastest client; a 10 fps GIF only drives a ~15 Hz clock, and the Timer is released
   entirely when nothing is playing.
2. **Decode at display size** — frames are decoded straight at the displayed size through
   ImageIO's thumbnail API. An 800×800 GIF in a 200 pt window decodes at 400 px, a quarter of
   the memory and time of a full-size decode.
3. **No decoding on the main thread** — a background serial queue decodes and prefetches the
   next five frames; on a miss the previous frame simply stays on screen. The cache is
   byte-capped with LRU eviction.
4. **Knows when to stop** — pauses when fully occluded, behind a full-screen app, on battery or
   when locked; videos play with the audio pipeline stripped.

## Design

The menu-bar panel, welcome window, settings and library share one design language: a plain
white canvas (near-black in dark mode), grey block buttons, and a single brand orange reserved
for the primary action. Colors, corner radii and type sizes live in
`Sources/MemeDesk/UI/Design.swift`; the app icon is generated from one 1024 px master by
`Scripts/make_icon.py` into both `.icns` and `.png`, so Finder, the menu bar and the welcome
window all show the same face.

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools to build from source

## License

[MIT](LICENSE)
