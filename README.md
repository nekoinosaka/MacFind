# MacFind

[中文](README.zh-CN.md) | English

A Spotlight-backed file search panel for macOS — a personal replacement for Spotlight's UI.

<p align="center"><img src="docs/icon.png" width="128" alt="MacFind icon"></p>

MacFind does **not** build its own index. It queries the system **Spotlight index in-process** via `NSMetadataQuery`, so a full-disk filename search returns in a few hundred milliseconds — with no background daemon, no local database, and (for the Spotlight path) no Full Disk Access required.

> If you dislike Spotlight's UI but are fine with its index, this is the thin wrapper for you.

## Features

- Full-disk filename search (Spotlight index)
- Rich filters: `ext:` / `size:` / `date:` / `kind:` / `in:` and `!` negation
- Live narrowing as you type (100 ms debounce)
- Results table (name / size / modified / path), default sort by modified time
- Open, Reveal in Finder, Copy path
- Single-instance enforced (`LSMultipleInstancesProhibited` + a runtime guard)
- No network calls, no telemetry
- macOS 13+, Apple Silicon (arm64)

## Query syntax

Wrap the query in single quotes so your shell doesn't eat special characters.

| Filter | Example | Meaning |
|---|---|---|
| literal | `'report'` | name contains `report` |
| negation | `'!ext:tmp'` | exclude `.tmp` |
| `ext:` | `'ext:pdf,epub'` | extensions (comma-separated) |
| `size:` | `'size:>10M'`, `'size:<=1K'` | `>` `>=` `<` `<=`, suffixes `K`/`M`/`G` |
| `date:` | `'date:7d'`, `'date:today'`, `'date:>2024-01-01'` | modified after… |
| `kind:` | `'kind:file'`, `'kind:dir'`, `'kind:symlink'` | item type |
| `in:` | `'in:~/Downloads'` | restrict to a directory (`~` expanded by MacFind) |
| `name:` | `'name:config'` | match the file name |

```sh
report
ext:pdf size:>5M
in:~/Downloads ext:zip
'!node_modules' ext:ts
date:today ext:log
```

## Build & Run

Requires **Xcode** (project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)).

```sh
git clone https://github.com/nekoinosaka/MacFind.git
cd MacFind

brew install xcodegen        # if you don't have it
xcodegen generate            # writes MacFindApp.xcodeproj from project.yml

xcodebuild -project MacFindApp.xcodeproj -scheme MacFindApp \
  -configuration Release -derivedDataPath build build
open build/Build/Products/Release/MacFind.app
```

Or just open `MacFindApp.xcodeproj` in Xcode and press ⌘R.

### Install to /Applications

```sh
rm -rf /Applications/MacFind.app
ditto build/Build/Products/Release/MacFind.app /Applications/MacFind.app
codesign --force --deep --sign - /Applications/MacFind.app
```

## Tests

```sh
xcodebuild test -project MacFindApp.xcodeproj -scheme MacFindApp -destination 'platform=macOS'
```

19 tests: 16 for the query DSL parser + 3 live integration tests against the real Spotlight index.

## Project layout

```
MacFindApp/
├── project.yml                 # XcodeGen definition (source of truth)
├── MacFindKit/                 # query layer (static library, unit-testable without the GUI)
│   ├── QueryParser.swift       # DSL -> NSPredicate
│   ├── SpotlightBackend.swift  # NSMetadataQuery wrapper
│   └── ResultItem.swift
├── MacFindApp/                 # SwiftUI app
│   ├── ContentView.swift       # search field + Table + status bar
│   ├── SearchViewModel.swift   # input debounce + result actions
│   └── AppDelegate.swift       # single-instance guard
├── MacFindKitTests/            # 16 parser + 3 Spotlight integration tests
└── Tools/make_icon.swift       # CoreGraphics icon generator
```

## Known limitations

- **Depends on the Spotlight index.** Files inside `.git` and hidden directories are not indexed and won't be found; brand-new files may lag by seconds.
- Results are only as deterministic as Spotlight — it can silently omit items.
- **No content search** (use [`ripgrep`](https://github.com/BurntSushi/ripgrep)).
- External volumes are searchable only if Spotlight indexes them.
- macOS 13+ / Apple Silicon (arm64) only.

## Tech notes

- The query layer lives in a separate `MacFindKit` static library, so the test target never has to launch the GUI host.
- `NSMetadataQuery` only accepts metadata predicates. It **rejects** `NSPredicate(value: true)` and single-child `NSCompoundPredicate`s — both are guarded in `QueryParser` / `SpotlightBackend`.
- The icon is generated from code: `swift Tools/make_icon.swift <out.iconset>` then `iconutil -c icns <out.iconset> -o MacFindApp/Resources/AppIcon.icns`.
