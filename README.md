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

- Today, Tomorrow, and arbitrary local calendar date navigation
- Create, edit, complete/reopen, reschedule, and delete tasks
- Optional local time and notes; stable ordering for anytime items
- Daily and weekly recurrence with per-day completion and exception records
- Overdue one-time tasks remain on their original date
- Inline Quick Add defaults to the viewed date; optional date, time, recurrence, and notes are under Details
- Today follows local-day changes and refreshes after wake, clock, and time-zone notifications
- Optional menu bar count, completed-task visibility, and login item setting
- English and Simplified Chinese UI strings

## Project layout

- `Sources/FocusBar/Domain.swift`: local-date, navigation, and deterministic list rules
- `Sources/FocusBar/CalendarState.swift`: system calendar lifecycle notifications and badge refresh
- `Sources/FocusBar/Models.swift`: SwiftData task and recurrence occurrence records
- `Sources/FocusBar/TaskStore.swift`: local persistence and task commands
- `Sources/FocusBar/TodayPanel.swift`: menu bar list, date selection, task editing
- `Sources/FocusBar/SettingsView.swift`: local preferences and login item
- `Tests/FocusBarTests`: date, recurrence, ordering, and persistence tests (19 tests)

Data remains in the app's local SwiftData store. There is no import/export or migration UI in this first implementation.
