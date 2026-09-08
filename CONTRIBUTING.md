# Contributing

Thanks for taking the time to help. This is a small AppKit/SwiftUI project, so the process is
deliberately lightweight.

## Getting set up

```bash
git clone https://github.com/sdtafxy/MemeDesk.git
cd MemeDesk
./Scripts/build.sh
open dist/MemeDesk.app
```

To debug with a full Xcode project you additionally need
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen -s Xcode/project.yml
open MemeDesk.xcodeproj
```

`swift build -c release` must pass before a pull request is opened. CI runs the same build on a
macOS runner and also packages a `.dmg`.

## Ground rules

- **Deployment target is macOS 13.** Do not use newer APIs unless they are availability-guarded.
- **Keep it light.** This app runs all day on people's desktops. Before adding work to a per-frame
  path, check whether it can be done once, cached, or skipped when the sticker is not visible.
- **No decoding on the main thread.** Image and video decoding belongs on the existing background
  queues.
- **Benchmarks over claims.** If a change is supposed to improve performance, measure it with
  Instruments and mention the numbers in the pull request.

## Adding or changing UI text

All user-visible strings live in `Sources/MemeDeskShared/Localization.swift`. Add a case to `LKey`
and fill in both the `zh` and `en` values in `text`. The Swift compiler enforces that no case is
left untranslated, so please do not hard-code strings in views.

## Commit and pull request style

- One logical change per pull request.
- Describe what changed and why; if it fixes a behaviour, say how to reproduce it.
- Update `CHANGELOG.md` under an `Unreleased` heading for user-visible changes.
- Keep the code style consistent with the surrounding files: four-space indentation, no forced
  unwraps in code that can run during startup.

## Reporting bugs

Open an issue with your macOS version, the sticker format involved, and the steps to reproduce.
If MemeDesk is using more CPU than you expect, an Instruments time profile is worth a thousand
words — but a description of what was on the desktop is a good start.
