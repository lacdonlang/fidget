# Features

**English** · [简体中文](../zh-CN/FEATURES.md)

How each feature behaves, with defaults and limits. Code and tests both follow this spec.

## Idle movement

| Setting | Default | Range | Notes |
| --- | --- | --- | --- |
| Idle threshold `idleThresholdSeconds` | 60 s | 5 s – 2 h | How long after your last real input movement starts |
| Interval `jiggleIntervalSeconds` | 60 s | 5 s – 2 h | Time between movements; the first one happens as soon as the threshold is reached |
| Pattern `pattern` | Nudge | Nudge / circle / square / figure eight / random walk | Nudge and square alternate direction so the pointer doesn't drift |
| Distance `amplitude` | 8 px | 1 – 300 px | Maximum distance from the starting point |
| Duration `durationMilliseconds` | 300 ms | 50 – 3000 ms | Length of one movement, sampled 60 times a second (2 – 240 steps) |
| Return to origin `returnToOrigin` | On | | Circle and figure eight always end where they started |
| Invisible mode `invisibleMode` | Off | | Forces 1 px, 50 ms and return to origin: invisible to the eye, but it still resets the idle timer |

- Only **real** input puts Fidget back into watching; its own movements don't count (see [Architecture](ARCHITECTURE.md)).
- Near a screen edge the starting point moves inward so hot corners aren't triggered, and every point stays on the pointer's display.
- After each movement Fidget reads the pointer position back. Two movements in a row that didn't move it show a warning suggesting a permission check (the check can be turned off in Advanced).

## On, off and pausing

- Main switch: the popover, the right-click menu, the global shortcut, or `fidget://enable|disable|toggle`. The shortcut ends a manual pause; otherwise it toggles Fidget.
- Pause presets: 15 min, 30 min, 1 h, 2 h, 4 h, the rest of the day (until midnight) or until resumed. Timed pauses end on their own, and the popover shows when.

## Smart pause (highest priority first)

1. **Screen locked, screen saver, user switched out or system asleep** (on by default).
2. **On battery** (off).
3. **Schedule** (off): weekdays plus a start and end time. An end time at or before the start spans midnight and belongs to the start day; equal times mean all day. The popover shows when Fidget resumes.
4. **Apps** (none): pause while a listed app is running, or only while it's frontmost.
5. **Another app keeps the display awake** (off): typical for video, presentations and calls. Diagnostics list which apps.

## Keep awake (optional, off by default)

Prevents display sleep and/or system sleep with IOKit power assertions. They are held only while Fidget is watching or active, and released when it's off, paused or quitting.

## Menu bar and popover

- The icon shows the state: active, watching, paused, needs permission or off (dimmed). Five icon styles, and an optional countdown next to it.
- Click for the popover: status, main switch, progress, permission and warning banners (with **Reset Permission**), pause and resume, **Move Now**, statistics, and Settings, About and Quit. ⌘, opens Settings and ⌘Q quits.
- Right-click for a menu with the same main actions.

## Settings window

The design is inspired by CleanMyMac: every section has its own accent color and a soft glow that follows as you switch sections. **Settings → General → Appearance** (System / Light / Dark) applies to the whole app; the menu bar icon follows the menu bar. The window opens at 860×640, can shrink to 780×520, and never truncates text, even in English at the minimum size.

| Section | Contents |
| --- | --- |
| General | Launch at login, icon style, countdown, global shortcut, appearance, language (System / English / 简体中文, applied immediately), permission status, Reset Permission, setup assistant |
| Movement | Move Now, threshold and interval, pattern preview and cards, distance, duration, return to origin, invisible mode |
| Schedule | On/off, weekdays (the week starts as in the system), start and end time, when the schedule next applies |
| Smart Pause | The system rules, the app list and its mode |
| Keep Awake | Display and system sleep, and whether an assertion is currently held |
| Advanced | Statistics, diagnostics with a copy button, file logging, settings import/export/reset, updates |

## Setup assistant

Four steps: welcome → grant Accessibility (detected live, with Reset Permission if the switch is on but not honored) → common preferences → done, with a test movement. It opens at launch until it has been completed or while the permission is missing, and Settings can reopen it.

## Automation

URL scheme `fidget://`: `enable`, `disable`, `toggle`, `pause[?minutes=N]`, `resume`, `move`, `settings[?section=movement]` and `setup`. On SIGTERM (for example `killall Fidget`) Fidget quits normally: it saves settings and statistics and releases its power assertions.

## Updates

- Sparkle 2.9.x checks `https://github.com/lacdonlang/fidget/releases/latest/download/appcast.xml` once a day and shows the update notes from the changelog.
- The notes follow the app language, which is the system language by default or the one picked in **Settings → General → Language**: a Chinese UI reads `appcast.zh-CN.xml`, any other language `appcast.xml`. A language change applies from the next check.
- **Settings → Advanced → Updates**: check automatically (on by default), download and install automatically (off by default; the update installs when Fidget quits), **Check for Updates…** and the time of the last check.
- An update must carry a valid EdDSA signature for the `SUPublicEDKey` in `Info.plist` and meet the installed version's code signing requirement (same developer and bundle ID), so the Accessibility permission survives updates.
- Debug builds and `swift run` don't check for updates; there, Check for Updates… opens the Releases page.

## Non-functional

- English and Simplified Chinese; all UI text goes through `L.t` / `L.f`, and tests keep both languages' keys in sync.
- No account. The only network access is the update check, which can be turned off. The only third-party dependency is Sparkle.
- Polls once a second. Expensive queries (running apps, assertions held by other processes) only run while their rule is on and are cached for 5 s. Closed windows and the hidden popover release their SwiftUI content.
- Swift 6 strict concurrency, arm64 only.
- macOS 11 or later. On macOS 11 the mouse-shaped menu bar icon isn't offered (its symbol needs macOS 12). On macOS 11–12 launch at login uses a LaunchAgent, so Fidget doesn't appear in the system's login items list.
