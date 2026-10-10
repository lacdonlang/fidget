<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="Fidget icon">
</p>

<h1 align="center">Fidget</h1>

<p align="center">Keeps your Mac awake and your status green by nudging the mouse while you're away.<br>
Apple Silicon only · macOS 11 Big Sur or later · open source (MIT)</p>

<p align="center"><b>English</b> · <a href="README.zh-CN.md">简体中文</a></p>

Fidget is a native Swift menu bar app, rewritten from scratch as a successor to [automatic-mouse-mover](https://github.com/prashantgupta24/automatic-mouse-mover). Once you've been idle for a while, it moves the pointer slightly using real input events, so macOS and chat apps like Slack or Teams keep seeing you as active. It stops the moment you touch the mouse or keyboard.

<p align="center">
  <img src="docs/images/en/dark/settings-movement.jpg" width="860" alt="Fidget settings, Movement page">
</p>

## Features

- **Only while you're away**: starts after an idle threshold (60 s by default) and never mistakes its own movements for you coming back.
- **Real input events**: resets the system idle timer, which tools that only prevent sleep (such as `caffeinate`) can't do.
- **Five patterns**: nudge, circle, square, figure eight and random walk, with adjustable distance and duration, plus an invisible mode.
- **Smart pause**: on screen lock, on battery, outside your schedule, while chosen apps are running or in front, or while another app plays video.
- **Optional sleep prevention**: keeps the display or system awake, only while Fidget is working.
- **Menu bar native**: countdown in the menu bar, global shortcut, `fidget://` automation, English and Simplified Chinese, light and dark appearance.
- **Automatic updates**: checks once a day and verifies every update's signature. No account and no other network access.

## Install

Download the latest `Fidget-<version>.dmg` from [Releases](https://github.com/lacdonlang/fidget/releases) and drag Fidget into Applications. On first launch, the setup assistant asks for the **Accessibility** permission (System Settings → Privacy & Security → Accessibility). If the switch there is already on but Fidget still says it isn't authorized, click **Reset Permission** in the popover and turn the switch on again. From then on, Fidget updates itself (Settings → Advanced → Updates).

## Build from source

Requires an Apple Silicon Mac and Xcode 16 or later. Xcode 27 can only deploy to macOS 12, so apps you build with it need macOS 12+; releases are built on CI with an Xcode that still deploys to macOS 11.

```bash
git clone https://github.com/lacdonlang/fidget.git && cd fidget
make run            # build the debug app and launch it
make test           # run all tests
make app            # build/Fidget.app, ad-hoc signed
make check-min-os   # type-check everything against macOS 11
```

To sign with your own Developer ID, notarize and build a DMG, see [Releasing](docs/en/RELEASING.md).

## Usage

<p align="center">
  <img src="docs/images/en/dark/popover.png" width="330" alt="Menu bar popover">
</p>

| Action | How |
| --- | --- |
| Turn on / off | Popover switch · right-click menu · global shortcut · `open fidget://toggle` |
| Pause for 15 min … the rest of the day, or until resumed | Popover "Pause" menu · right-click menu · `open "fidget://pause?minutes=30"` |
| Move once now (tests the permission) | Popover "Move Now" · `open fidget://move` |
| Open Settings | ⌘, in the popover · `open fidget://settings` |

## Screenshots

| General | Schedule |
| --- | --- |
| ![General settings](docs/images/en/dark/settings-general.jpg) | ![Schedule settings](docs/images/en/dark/settings-schedule.jpg) |
| **Smart Pause** | **Advanced** |
| ![Smart Pause settings](docs/images/en/dark/settings-rules.jpg) | ![Advanced settings](docs/images/en/dark/settings-advanced.jpg) |

Light appearance (Settings → General → Appearance: System / Light / Dark):

| General | Keep Awake |
| --- | --- |
| ![General settings, light appearance](docs/images/en/light/settings-general.jpg) | ![Keep Awake settings, light appearance](docs/images/en/light/settings-keepAwake.jpg) |

## Documentation

- [Features](docs/en/FEATURES.md): what every setting does, with defaults and limits
- [Architecture](docs/en/ARCHITECTURE.md): layers, state machine, key decisions, project layout
- [Testing](docs/en/TESTING.md): test layers and the manual release checklist
- [Releasing](docs/en/RELEASING.md): signing, notarization, update keys, release steps
- [Changelog](CHANGELOG.md)

## License

[MIT](LICENSE). Inspired by [Automatic Mouse Mover](https://github.com/prashantgupta24/automatic-mouse-mover) by Prashant Gupta.
