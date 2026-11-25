# Focus Bar

A quiet, native macOS menu bar checklist for tasks you enter yourself. Tasks are stored locally with SwiftData. V1 does not use AI, network services, accounts, calendar integrations, or cloud sync.

## Requirements

- macOS 14 or later
- Xcode 16 or later (Swift 6 toolchain recommended)

## Build and run

```sh
swift run
```

For a normal menu bar app bundle (`LSUIElement`, so it does not occupy the Dock):

```sh
./scripts/build-app.sh
open ".FocusBarBuild/Focus Bar.app"
```

The bundle is ad-hoc signed for local use. It is not notarized or ready for distribution. Login at Start requires launching the bundled app; the SwiftPM executable is not a registered login item.

## Tests

```sh
swift test
```

## Features

- Native menu bar panel that sizes to its content; the list scrolls only past ~70% of the screen height
- Today, Tomorrow, and arbitrary date navigation: ‹ / › arrows, a Today button, and a calendar popover on the date
- Create, rename in place, complete/reopen, reschedule, and delete tasks; deletion can be undone
- Always-visible quick add field defaults to the viewed date; date, time, and repeat are set from small popovers and shown as removable chips
- Hover and keyboard selection on rows; an ⓘ button opens a details popover (title, notes, date, time, optional deadline) that saves on close
- Optional local time and notes; stable ordering for anytime items
- Daily and weekly recurrence with per-day completion and exception records
- Overdue one-time tasks remain on their original date
- Today follows local-day changes and refreshes after wake, clock, and time-zone notifications
- Optional menu bar count (hidden at zero), completed-task visibility, and login item setting
- English and Simplified Chinese UI strings

### Keyboard

| Keys | Action |
| --- | --- |
| ⌘N | Focus the quick add field |
| ↑ / ↓ | Move the selection |
| Space | Complete or reopen the selected task |
| Return | Rename the selected task |
| Delete | Delete the selected task (undo from the banner or ⌘Z) |
| ⌘I | Open details for the selected task |
| ⌘[ / ⌘] / ⌘T | Previous day / next day / today |
| ⌘, | Settings |

## Project layout

- `Sources/FocusBar/Domain.swift`: local-date, navigation, and deterministic list rules
- `Sources/FocusBar/CalendarState.swift`: system calendar lifecycle notifications and badge refresh
- `Sources/FocusBar/Models.swift`: SwiftData task and recurrence occurrence records
- `Sources/FocusBar/TaskStore.swift`: local persistence and task commands
- `Sources/FocusBar/TodayPanel.swift`: menu bar panel, list rows, quick add, details popover, keyboard handling
- `Sources/FocusBar/SettingsView.swift`: local preferences and login item
- `Tests/FocusBarTests`: date, recurrence, deadline, ordering, and persistence tests (21 tests)

Data remains in the app's local SwiftData store. There is no import/export or migration UI in this first implementation.
