# Testing

**English** · [简体中文](../zh-CN/TESTING.md)

## Test layers

| Layer | What it covers | How | Where it runs |
| --- | --- | --- | --- |
| FidgetCore | State machine, patterns, schedule, settings decoding and validation, statistics, command parsing | Swift Testing on pure value types, with a fixed-time-zone calendar and the `EngineSim` timeline simulator | Any Mac, no permissions |
| FidgetSystem | Every system adapter runs, doesn't crash and handles edge cases | Integration tests against real macOS APIs; tests that need Accessibility are skipped with `#require` | Local or CI GUI session |
| FidgetApp | State-to-text and icon mapping, driver and model working together, localization, updates | `EngineDriver` with in-memory storage and a fake pointer; source scans for string keys | Any Mac |
| UI | Where the real menu bar popover appears | `make ui-test` (sets `FIDGET_UI_TESTS=1`; skipped by default because it steals focus) | Local GUI session |
| End to end | The packaged app launches and really moves the pointer; every window renders | `make smoke` (the terminal needs Accessibility) and `make screenshots` | Local |

## Running tests

```bash
swift test                            # everything
swift test --filter FidgetCoreTests   # core layer only
make ui-test                          # real popover placement
make check-min-os                     # type-check against macOS 11
```

- CI (`.github/workflows/ci.yml`) runs on Apple Silicon with the Xcode chosen by `scripts/select-xcode.sh`: `swift build`, `swift test`, `STRICT_MIN_OS=1 scripts/build-app.sh` and `scripts/verify-app.sh`.
- Local Xcode 27 builds check API availability against macOS 12 only, so run `make check-min-os` after changing UI or system code.
- `make smoke` starts the executable inside the `.app` directly instead of using `open`, so it inherits the terminal's Accessibility permission.
- `make screenshots` renders one set per language (`en`, `zh-CN`) and appearance (`dark`, `light`) into `docs/images/<lang>/<appearance>/`, in-process and without any permission. Windows are saved as JPEG, the popover as PNG. Review them after UI changes.

## What the tests check

- **Core**: settings defaults, fallbacks and clamping; schedule boundaries and windows across midnight; pattern limits and corner safety; every engine transition, including own movements not counting as input, pauses, rule priority and failure warnings.
- **System**: each adapter against the real API, including a real 1 px move (with permission), corrupt-file backup and the LaunchAgent login item on macOS 11–12.
- **App**: status presentation, the full `EngineDriver` loop with fake services, SF Symbols on macOS 11, and matching localization keys in both languages.
- **Updates**: the feed URL and public key in `Info.plist`; both appcasts from `scripts/make-appcast.sh` (version, build number, minimum OS, URL, signature, English and Chinese notes), which fails if either changelog lacks the current version; a Chinese UI picks `appcast.zh-CN.xml`.

## Manual checklist before a release

0. Repeat this list on the oldest macOS you can get (macOS 12 runs in a VM on Apple Silicon), focusing on the Settings layout, the menu bar icon and launch at login.
1. New user: the setup assistant appears; after granting permission the popover goes from "needs permission" to watching, and Move Now moves the pointer. If the switch is on but not honored, Reset Permission fixes it.
2. The popover hangs fully below the menu bar icon, also after a banner appears or disappears.
3. Settings: section colors change; Appearance switches between System, Light and Dark immediately; the window can be dragged by its top edge; no text is truncated at the minimum size; menus open with the current choice marked; times can be edited with the keyboard.
4. With a 10 s threshold and hands off, the pointer follows the chosen pattern and returns; the countdown is right; Slack stays active.
5. Touching the mouse goes back to watching immediately.
6. Locking the screen or starting the screen saver pauses Fidget; unlocking resumes it.
7. A schedule that excludes the current time shows that Fidget is outside the schedule and when it resumes.
8. Adding the frontmost app to the rules: both the running and the frontmost mode work.
9. With display sleep prevention on, `pmset -g assertions` lists Fidget's assertion; it disappears when turned off.
10. Global shortcut, instant language switching, settings import and export, statistics reset.
11. After a relaunch, settings and statistics are kept and the login item matches the system. Once a release is out, the previous version finds it with Check for Updates…, installs it, relaunches and keeps the Accessibility permission; the update notes are in the app's language.
12. `open "fidget://pause?minutes=1"` resumes after a minute.
