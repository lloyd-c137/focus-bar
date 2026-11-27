# Focus Bar

A quiet, native macOS menu bar checklist for tasks you enter yourself. Tasks are stored locally with SwiftData. Focus Bar has no planned-date field: tasks stay in the list until you complete or delete them. An optional deadline is the only date that can make an unfinished task overdue.

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

- Native menu bar panel with a long-term task list and content-sized scrolling
- Quick add requires only a title; deadline, time, and recurrence are optional
- Tasks without a deadline stay in the list and never become overdue because of age
- Overdue contains only unfinished tasks whose explicitly set deadline has passed
- Time-of-day sorting, anytime tasks, completed-task folding and undoable deletion
- Daily and weekly recurrence with independent per-occurrence completion
- Weekly recurrence lets you choose its weekday
- Per-occurrence deadline for recurring tasks
- Hover and keyboard selection; an ⓘ button opens details for title, notes, optional deadline and time
- Optional menu bar count, completed-task visibility, login item setting
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
| ⌘, | Settings |

## Project layout

- `Sources/FocusBar/Domain.swift`: deadline, recurrence and list rules
- `Sources/FocusBar/CalendarState.swift`: local date lifecycle and badge refresh
- `Sources/FocusBar/Models.swift`: SwiftData task and recurrence occurrence records
- `Sources/FocusBar/TaskStore.swift`: local persistence and task commands
- `Sources/FocusBar/GitHubBackup.swift`: secure credential lookup, consistent SQLite snapshots and GitHub upload/retry queue
- `Sources/FocusBar/TodayPanel.swift`: menu bar panel, list rows, quick add and details
- `Sources/FocusBar/SettingsView.swift`: local preferences and login item
- `Tests/FocusBarTests`: deadline, recurrence, ordering and persistence tests

Existing SwiftData records keep their old date columns for store compatibility, but those planned dates are ignored by the app.

## GitHub backup

After a successful task change (add, edit, complete/reopen, delete, undo, or recurrence edit), Focus Bar creates a consistent SQLite snapshot and updates `FocusBar.sqlite` in the private [`focus-bar-data-backup`](https://github.com/lloyd-c137/focus-bar-data-backup) repository. It also syncs once when the app starts and retries when network connectivity returns. Failed uploads stay pending and are shown in Settings; use **Sync now** to retry manually.

Backups are **not encrypted**. Anyone with access to the private repository can read task titles, notes, deadlines and completion data. The GitHub token is stored in macOS Keychain and is limited to Contents read/write access to this backup repository. To configure it, create a fine-grained token scoped only to that repository, then run `fnox set FOCUS_BAR_GITHUB_TOKEN` in Terminal and restart Focus Bar. Do not commit or share the token.

The repository stores the latest database snapshot; each successful GitHub update also creates a Git commit, so previous snapshots remain available in repository history. Restore instructions are in the backup repository README. GitHub sync needs an internet connection; local task changes remain available offline.
