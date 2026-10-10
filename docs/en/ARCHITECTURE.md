# Architecture

**English** · [简体中文](../zh-CN/ARCHITECTURE.md)

Fidget shares its goal with [automatic-mouse-mover](https://github.com/prashantgupta24/automatic-mouse-mover) (Go and robotgo): move the mouse slightly while you're away, so the Mac stays awake and chat apps keep showing you as active. It is a from-scratch rewrite as a native Swift app for Apple Silicon.

## Goals and constraints

| Topic | Decision | Why |
| --- | --- | --- |
| Platform | macOS 11+, arm64 only | Covers every macOS that runs on Apple Silicon. Newer APIs need an `#available` check and a fallback; all versions share one UI code path |
| Toolchain | Swift 6 language mode, SwiftPM | Compile-time data race checking; SwiftPM is the single source of truth for code and tests |
| UI | SwiftUI views on an AppKit lifecycle (`NSStatusItem`, `NSPopover`, `NSWindow`) | A menu bar app needs more control over the popover, menus and windows than `MenuBarExtra` offers |
| Dependencies | Sparkle only | Replacing a running app safely is too risky to build by hand; everything else uses system frameworks |
| Distribution | Developer ID and notarization | Not possible through the App Store (see the last section) |

## Project layout

```
Package.swift            SwiftPM: the single source of truth for code and tests
Sources/FidgetCore       Pure logic: settings, state machine, patterns, schedule, rules, statistics
Sources/FidgetSystem     macOS adapters: CGEvent, IOKit, screen lock, permissions, login items, hotkeys, storage, logging
Sources/FidgetApp        SwiftUI views, menu bar controller, composition root, updates, localized resources
Sources/Fidget           Executable entry point
Tests/                   Swift Testing: core, system and app-layer tests
Resources/               Info.plist, entitlements, icons, asset catalog
scripts/                 Build, sign, notarize, DMG, appcast, icon, smoke test, screenshots
project.yml              XcodeGen configuration (generates Fidget.xcodeproj)
```

## Layers

Dependencies point strictly downwards: `Fidget` → `FidgetApp` → `FidgetSystem` → `FidgetCore`.

- **FidgetCore** is pure Swift without AppKit, so it's fully unit-testable. It holds the settings model (lenient decoding falls back to defaults for missing or invalid keys; `validated()` clamps values), the `Engine` state machine, path generation, schedule, rules, statistics, the hotkey model, `fidget://` parsing, and protocols for every system service.
- **FidgetSystem** has one adapter per system API, each implementing a core protocol: idle time and mouse events (`CGEvent` posted to the HID event tap), IOKit power assertions and power source, assertions held by other apps, screen lock and sleep notifications, the Accessibility permission (Reset Permission runs `tccutil reset`), login items (`SMAppService` on macOS 13+, a user LaunchAgent on 11–12, migrated after an upgrade), Carbon hotkeys (no permission needed), atomic JSON storage and logging.
- **FidgetApp** is a library, so `swift test` covers it too; it only exposes `FidgetAppEntry.run()`.
  - `AppDelegate` is the composition root. Every settings change goes through one place that saves (debounced), re-evaluates the engine, re-registers the hotkey and switches the language.
  - `AppModel` is the single data source for the UI. Data that changes every second lives in `model.live`, so the Settings window doesn't recompute on every tick.
  - `EngineDriver` runs a 1 Hz timer: collect inputs → `engine.tick` → perform effects and apply power assertions → update model and statistics.
  - `StatusItemController` opens the popover on click and a menu on right-click. The popover and windows create their SwiftUI content when shown and release it when closed.
  - `UpdateController` wraps Sparkle in release builds; `FeedSelector` chooses the feed by UI language (see [Updates](#updates)).
  - `L` handles localization and can switch language at runtime; dates and durations are formatted in the UI language.
  - The Settings, setup and About windows share a CleanMyMac-inspired style (`Aurora.swift`) with a theme per section and custom accessible controls. Every color has a light and a dark value; the Appearance setting sets `NSApp.appearance`.
  - `ScreenshotRenderer` (debug builds only) renders the README screenshots in-process from sample data.

## Telling real input from Fidget's own

The system idle timer doesn't know who produced an event, so Fidget's own movements reset it too. `Engine.updateRealInput` works around that:

1. Each tick computes `observedLastInput = now - systemIdle`.
2. The engine records a time window for every movement, with 0.75 s of tolerance on each side.
3. Input inside a window is Fidget's own; anything else updates `lastRealInputAt`.
4. The state machine uses `realIdle = now - lastRealInputAt`.

A touch during a 0.3 s movement can be missed once; the next input corrects it. Move Now goes through the engine (`requestJiggle()`), so the same windows cover it.

## State machine

```
any state ── isEnabled = false ──► off

enabled ── no permission ─────────► blocked
   │    ── rule or manual pause ──► paused(reason) ── pause ends ──► watching
   ▼
watching ── realIdle ≥ threshold ──► active ── every interval ──► move
   ▲                                   │
   └─────────── real input ────────────┘
```

- Entering `active` moves right away, then once per interval; movements never overlap.
- Rule priority: screen lock, screen saver or user switched out > battery > schedule > apps > another app keeping the display awake.
- Power assertions are held only in `watching` and `active`. The engine declares the desired state every tick, and the controller applies it idempotently.
- Two movements in a row that didn't move the pointer raise `pointerDidNotMove`; Fidget warns but keeps trying.

## Concurrency

UI, controllers, the driver and the system adapters are `@MainActor`; the core consists of `Sendable` value types. Movements run as async `Task`s. System notifications and Carbon hotkey callbacks are delivered on the main queue and enter the actor with `MainActor.assumeIsolated`. `Log` protects its file sink with a lock, so it can be called from any thread.

## Persistence

| File | Location | Contents |
| --- | --- | --- |
| `settings.json` | `~/Library/Application Support/Fidget/` | All settings; saved 400 ms after a change |
| `statistics.json` | Same | Statistics, kept out of settings exports; saved every 60 s and on quit |
| `fidget.log` | `~/Library/Logs/Fidget/` | Optional file log, rotated at 1 MB |

A corrupt file is kept as `*.corrupt-<timestamp>.json` and defaults are used. `FIDGET_CONFIG_DIR` redirects the directory for tests and scripts.

## Build and packaging

- `swift build` and `swift test` for daily work. `make app` runs `scripts/build-app.sh`, which assembles the `.app` (Info.plist, icons, resources, plus the Swift concurrency runtime when targeting macOS 11) and signs it with `scripts/sign.sh`.
- `scripts/verify-app.sh` checks architecture, minimum OS, library resolution and signature, then launches the app for 5 seconds.
- The build number is derived from the version (1.3.0 → 10300), not from git history. Sparkle compares it to detect newer versions.
- `project.yml` generates the Xcode project with XcodeGen; its app target only contains the entry point and the asset catalog.
- Signing, notarization and releases: see [Releasing](RELEASING.md).

## macOS 11 support

| Area | Approach |
| --- | --- |
| Toolchain | Xcode 27 can only deploy to macOS 12 and quietly raises the target. CI picks the newest Xcode that still deploys to 11 (`scripts/select-xcode.sh`) and builds with `STRICT_MIN_OS=1`, which fails unless the app's minimum is 11.0 |
| Runtime | macOS 11 has no Swift concurrency runtime, so `build-app.sh` embeds the back-deployed one; macOS 12+ uses the system copy |
| API availability | `make check-min-os` type-checks all modules and tests against macOS 11 with `swiftc`, bypassing the build system |
| SF Symbols | `SymbolAvailabilityTests` checks that every symbol exists on macOS 11 or has a fallback registered in `Symbols` |
| Verification | One code path for every version plus the checks above; on macOS 12+ the UI can be tested by hand in a VM |

## Updates

- Sparkle is pinned to 2.9.x because 2.10 and later require macOS 12.
- The app isn't sandboxed, so Sparkle's XPC services are removed. The framework is thinned to arm64 and signed inside out: Autoupdate, Updater.app, the framework, then the app.
- The hardened runtime is enabled only for Developer ID builds. With ad-hoc signing, library validation would refuse to load Sparkle and the app would quit at launch.
- Each release publishes two feeds that differ only in their notes: `appcast.xml` (English, from `CHANGELOG.md`) and `appcast.zh-CN.xml` (Chinese, from `CHANGELOG.zh-CN.md`). `Info.plist` points to the English feed; `FeedSelector` switches to the Chinese one whenever the UI is in Chinese, whether that comes from the system or from Settings → General → Language.

## Decisions

1. **`NSStatusItem` and `NSPopover` instead of `MenuBarExtra`**: the popover can be closed programmatically and left and right clicks handled separately; SwiftUI still draws all content.
2. **Own `NSWindow` instead of the SwiftUI `Settings` scene**: it can open at a given section from the hotkey or a URL, without private selectors.
3. **`CGEvent` instead of `CGWarpMouseCursorPosition`**: warping creates no HID event, so the idle timer isn't reset and chat apps still mark you away. The price is the Accessibility permission, which the setup assistant and the state machine treat as first class.
4. **JSON files instead of UserDefaults**: readable, easy to import, export and back up, and testable in a temporary directory.
5. **Sparkle for updates**: it handles replacing a running app, asking for authorization, App Translocation, rollback and relaunch, and verifies EdDSA and code signatures.
6. **macOS 11 support**: Apple Silicon Macs shipped with macOS 11. That rules out `@Observable`, `NavigationSplitView` and grouped `Form`; in return every version runs the same UI code.

### Why not the App Store

The App Store requires the sandbox, and a sandboxed app can't get the Accessibility permission, so it can't post real mouse events. All it could do is `CGWarpMouseCursorPosition` plus power assertions, which prevents sleep but still lets chat apps mark you away. That's why Fidget ships with Developer ID signing and notarization. The `PointerControlling` protocol leaves room for a sandboxed fallback.
