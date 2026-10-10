# Changelog

**English** · [简体中文](CHANGELOG.zh-CN.md)

## 1.3.1

- Update notes now follow the app language: the system language, or the one you choose in Settings → General → Language
- The README, docs and changelog are now available in English and Chinese

## 1.3.0

- In-app updates: Fidget checks for new versions daily; after you confirm, it downloads the update, verifies its signature, replaces the app and relaunches. Updates can also install automatically in the background (Settings → Advanced → Updates)
- Fixed: the app icon and name at the top of the Settings sidebar weren't aligned with the sections below
- The build number is now derived from the version (1.3.0 → 10300) instead of the git history

## 1.2.0

- Redesigned Settings window inspired by CleanMyMac: each section has its own accent color and a soft glow that shifts as you switch sections; glass cards and custom glowing switches, sliders, segmented pickers and capsule buttons
- Light and dark color schemes; new Appearance option in General: System (default), Light or Dark, applied to the whole app
- The sidebar shows the current status and the main switch; Move Now moved to the Movement page header and patterns became five cards with a glowing preview; Keep Awake became two feature cards with descriptions; Advanced shows statistics as number cards
- The setup assistant and About window share the new style
- The README is now in English by default (the Chinese one moved to README.zh-CN.md) with screenshots in the matching language; there is one screenshot set per language and appearance, saved as JPEG (the gradients made each PNG 2–3 MB)

## 1.1.1

- Fixed: on macOS 27 the menu bar popover extended above the screen, showing only its bottom row (it was positioned at zero height and then grew upwards)
- New Reset Permission: when Fidget's switch in System Settings is on but the app still isn't authorized (the record belongs to an older build with a different signature), it deletes the stale record and asks again. Available from the popover's permission banner, the setup assistant and General settings
- Tests: `make ui-test` opens the real menu bar popover and checks that it hangs below the menu bar

## 1.1.0

- Supports macOS 11 Big Sur and later, every release that runs on Apple Silicon (previously macOS 14)
- The Settings window now uses a custom sidebar and grouped cards, so it looks the same on every macOS version
- Launch at login uses a LaunchAgent on macOS 11–12 and moves to the system login item after upgrading to macOS 13 or later
- Dates, durations and weekday names follow the app language (they used to follow the system language after switching)
- Fixed: the shortcut recorder started recording as soon as Settings opened
- The Settings window no longer recomputes every second along with live data
- Build: CI picks an Xcode that can deploy to macOS 11, embeds the Swift concurrency runtime when needed, and checks and launches the app before release

## 1.0.1

- Fixed: builds made on GitHub crashed at launch (with an older SwiftPM resource bundle layout, the language files weren't copied into the app)
- Packaging now fails if a language file is missing

## 1.0.0

- First version (unreleased): a native Apple Silicon redesign of automatic-mouse-mover
- Idle movement engine: tells real input from its own, threshold and interval, five patterns, invisible mode, screen-edge safety
- Smart pause: screen lock and screen saver, battery, schedule, app rules, media playback
- Sleep prevention, global shortcut, launch at login, `fidget://` commands
- Menu bar popover, right-click menu, six-section Settings window, setup assistant, English and Simplified Chinese
- SwiftPM and script-based packaging, Developer ID signing, notarization and DMG, XcodeGen project, CI
