# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a pure Xcode project — no Makefile, SPM package, or CLI build scripts.

```bash
open CompTIAAcronymTester.xcodeproj   # Open in Xcode, then Cmd-B to build, Cmd-R to run
```

There are no automated tests. Debug builds (via Xcode's DEBUG flag) include an extra "Test" acronym list and a **Settings → Debug → Print Duplicates** action that logs duplicate analysis to the console.

## Architecture

Two `ObservableObject` singletons are injected as `@EnvironmentObject` from `CompTIAAcronymTesterApp.swift` into the entire view tree:

- **`QuizStore`** — single source of truth for all quiz state. Holds the active acronym pool, per-item results, navigation index, and all user-configurable settings (persisted in UserDefaults). When any setting changes (enabled lists, strict mode, length filter, review mode), the store recomputes `activeItems` and resets navigation.
- **`UpdateManager`** — manages the data update lifecycle: seeds bundled JSON to the Documents directory on first launch, checks a remote GitHub repo for newer versions, and stages downloads atomically before applying them. It calls back into `QuizStore` (via `configure(quizStore:)`) to trigger a reload after a successful update.

Initialization order matters: `UpdateManager.seedIfNeeded()` runs synchronously before `QuizStore` is initialized, guaranteeing that Documents-directory JSON files exist before the store reads them.

## Data Layer

Acronym files follow this JSON schema:

```json
{
  "version": 1,
  "acronyms": [
    { "itemkey": "TCP", "itemvalue": "Transmission Control Protocol", "itemlink": "https://...", "strict": true }
  ]
}
```

`JSONLoader.loadRows(resourceName:)` reads from Documents first, falling back to the app bundle. `QuizStore` calls this for each enabled list, then merges duplicate keys (case-insensitive) into a single `Acronym` with multiple `values` and `links` arrays.

`MasterList.json` is a manifest listing all available files with per-file version numbers. `UpdateManager` compares the remote manifest version against the locally-stored version to decide whether to download.

Adding a new acronym list requires: (1) placing a JSON file in `Resources/`, (2) adding an entry to `MasterList.json`, and (3) registering it in `AcronymList.swift`.

## Session Persistence

When session restore is enabled, `QuizStore` serializes only the *tested* items (correct/incorrect) to `Documents/session.json` on every mark action. On relaunch it reconstructs the tested items first, then appends the remaining untested items in a fresh shuffle. Items belonging to since-disabled lists are silently dropped during restore.

## Key Files

| File | Role |
|------|------|
| `Models/QuizStore.swift` | All quiz state, filtering, navigation, marking, session save/restore |
| `Models/UpdateManager.swift` | Seed, update check, staged download, apply/discard |
| `Models/JSONLoader.swift` | File I/O and JSON decoding for acronym files |
| `Models/AcronymList.swift` | Catalog of available lists (reads MasterList.json at runtime) |
| `Views/QuizView.swift` | Main card UI; swipe gestures map to prev/next |
| `Views/JumpToView.swift` | Search sheet with prefix and subsequence matching |

## Remote Data

The remote base URL is `https://raw.githubusercontent.com/stuartbrussell/CompTIA-Acronym-Tester-data/refs/heads/main/CompTIAAcronymTester/Resources`. The data files live in a separate `CompTIA-Acronym-Tester-data` GitHub repository. All data changes (adding acronyms, editing values) are made there, not in this repo.
