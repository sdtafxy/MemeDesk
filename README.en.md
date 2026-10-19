<div align="center">

<img src="Resources/AppIcon.png" width="104" alt="MemeDesk icon">

# MemeDesk

**A layer of memes that sits on your desktop and keeps looping.**

<!-- Badges: one row of platform and stack, one row of release and status. Keep them in ONE paragraph -- a blank line between the rows splits it in two and the paragraph margins make the gap look too wide. The trailing <br> is what breaks the line. -->
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?style=for-the-badge&logo=apple&logoColor=white)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-000000?style=for-the-badge&logo=apple&logoColor=white)](#requirements)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?style=for-the-badge&logo=swift&logoColor=white)
![Zero dependencies](https://img.shields.io/badge/dependencies-none-2ea44f?style=for-the-badge)<br>
[![Latest release](https://img.shields.io/github/v/release/sdtafxy/MemeDesk?style=for-the-badge&label=release&color=FF7A2E&sort=semver)](https://github.com/sdtafxy/MemeDesk/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/sdtafxy/MemeDesk/total?style=for-the-badge&label=downloads&color=FF7A2E)](https://github.com/sdtafxy/MemeDesk/releases)
[![CI](https://img.shields.io/github/actions/workflow/status/sdtafxy/MemeDesk/ci.yml?style=for-the-badge&label=CI)](https://github.com/sdtafxy/MemeDesk/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/sdtafxy/MemeDesk?style=for-the-badge&color=FF7A2E)](LICENSE)
[![Stars](https://img.shields.io/github/stars/sdtafxy/MemeDesk?style=for-the-badge&color=FF7A2E&label=stars)](https://github.com/sdtafxy/MemeDesk/stargazers)

**[简体中文](README.md)** · [Changelog](CHANGELOG.md)

<img src="Docs/demo.gif" width="340" alt="MemeDesk stickers looping on the desktop">

</div>

---

A wallpaper and a screenshot can only sit there. Memes move.

MemeDesk does one thing: pins the memes you've collected onto your desktop and loops them.
GIF, APNG, video, stills — all fine. Any number at once, and each one can be dragged, scaled,
rotated, bounced, or made to follow your cursor. It lives in the menu bar only — no Dock icon,
no wallpaper change, no pop-ups.

The one time it goes quiet on its own is when you open a full-screen video.

## What it does

- As many as you like, each with its own settings, and they come back next launch
- GIF, APNG, PNG, JPG, HEIC, WebP, MP4, MOV, M4V — drop a file in
- Three layers: under the desktop icons, on the desktop, or above every window
- Six behaviours: still, breathing, bouncing off the edges, falling to the bottom, following the cursor, wandering
- Right-click for size, opacity, speed, rotation, mirroring, click-through, lock
- Snaps to screen edges, so one can't get lost off-screen
- English and Simplified Chinese, following the system by default
- Six sample stickers included — one click in the library

## Install

Grab `MemeDesk-*.dmg` from [Releases](../../releases/latest), open it, and drag the app into
Applications.

> [!NOTE]
> The app is ad-hoc signed, so Gatekeeper stops it the first time. Right-click the icon and
> choose Open; after that it launches normally.

The release is Apple silicon only. On an Intel Mac, build it yourself — see
[below](#build-from-source).

## Usage

Click the face in the menu bar. The panel gives you add, library and settings, plus
hide all / pause / clear desktop.

### Mouse and keyboard

- **Drag** — move it. Snaps to screen edges
- <kbd>⌥</kbd> + drag — scale proportionally
- **Scroll** — nudge the size
- **Double-click** — pause just that one
- **Right-click** — size, opacity, speed, rotation, layer, behaviour, mirror, click-through, lock, duplicate, remove
- <kbd>⌘</kbd> <kbd>,</kbd> — open Settings

<details>
<summary>Control it with a URL scheme (Raycast, Alfred, Shortcuts)</summary>

```bash
open "memedesk://add?file=/Users/me/cat.gif"
open "memedesk://hide"    # hide everything
open "memedesk://show"    # show everything
open "memedesk://pause"   # pause playback
open "memedesk://resume"  # resume playback
open "memedesk://clear"   # clear the desk
```

</details>

## Updates

Two switches in Settings: check automatically (on by default), and install automatically
(off by default, because it restarts the app).

When a new version is out, a small orange dot appears on the settings button in the panel.

Updating replaces the app bundle in place. Your desk layout, sticker paths and settings live in
`~/Library/Application Support/MemeDesk/`, outside the bundle, so nothing is lost.

Archives are verified before install: SHA-256 always, plus Ed25519 if a public key is configured.
A missing signature is refused outright rather than falling back to the checksum alone.

Checking for updates is the only thing in this app that touches the network: `api.github.com` and
the release files, with no identifying information. Turn automatic checks off and nothing is
requested until you press the button.

## Build from source

You need the full Xcode. The Command Line Tools alone are not enough — SwiftUI's macro plugin
ships only with Xcode.

```bash
./Scripts/build.sh        # → dist/MemeDesk.app
open dist/MemeDesk.app
```

`./Scripts/make_dmg.sh` builds a disk image as well. To debug in Xcode:

```bash
brew install xcodegen
xcodegen -s Xcode/project.yml
open MemeDesk.xcodeproj
```

## About that face

The menu bar icon is not a shrunken app icon; it's a separate set of faces.

The app icon is an orange rounded square — heavy, and small at 22 pt. A menu bar icon should also
take its colour from the system rather than from the app. So it's a template image: black on a
light menu bar, white on a dark one.

Two groups: eight drawn as vectors (smile, laughing, wink, surprised, cool, love, sad, angry) and
two derived from photographs. Switch any time in Settings, applied immediately.

## FAQ

**"Cannot verify the developer" on first launch?**
Right-click the app and choose Open. That's what ad-hoc signing looks like; the file is fine.

**Will it run on an Intel Mac?**
Yes, if you build it. The release is arm64 only.

**Where does it keep my stickers?**
`~/Library/Application Support/MemeDesk/`. Delete that folder to start clean.

**Is it heavy on the CPU?**
Idle, it's zero. Large GIFs decode at the size of the window rather than at full size, and
playback pauses when a sticker is fully covered, a full-screen app is in front, the screen is
locked, or you're on battery.

**A sticker is covering my desktop icons.**
The default layer sits above them. Change the layer to "under the icons" to slip it between the
wallpaper and the icons — but macOS swallows mouse events at that level, so it stops being
draggable.

## Requirements

- macOS 13 Ventura or later
- Apple silicon (build from source on Intel)

## License

[MIT](LICENSE)
