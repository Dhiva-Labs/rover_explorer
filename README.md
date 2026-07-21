<div align="center">

<img src="assets/icons/rover-explorer.png" width="128" alt="Rover Explorer">

# Rover Explorer

**A Windows XP-style file explorer for Linux and Windows — with the search companion dog, and search that is actually instant.**

A [Dhiva Labs](https://github.com/Dhiva-Labs) project · MIT licensed

</div>

---

## What it is

Rover Explorer recreates the Windows XP Explorer experience — the Luna toolbar,
the task panes, the folder tree, details and icons views — and pairs it with a
modern, Everything-style search index that returns ranked results on every
keystroke across hundreds of thousands of files.

And it brings back the dog.

> The companion is an original character drawn entirely in code (`CustomPaint`).
> No Microsoft artwork, icons or audio are used anywhere in this project.

## Features

### Explorer

- Classic XP Luna chrome: gradient toolbar, beige dialogs, sunken fields.
- Menu bar — **File / Edit / View / Go / Tools / Help**.
- **Common Tasks** pane ("File and Folder Tasks", "Other Places", "Details")
  and a lazily-loaded **Folders** tree pane.
- Address bar with path entry and a **recent locations** drop-down.
- Details and icons views, sortable columns, folders grouped first.
- Full file management: open with the system handler, cut / copy / paste,
  rename, delete, new folder, multi-select, **drag & drop** onto folders,
  hidden-file toggle, **Properties** with background size counting.
- **Folder Options** for hidden files, the companion, sounds and the index.

### Instant search

- A background isolate keeps an in-memory filename index of your home tree
  (~450k entries index in seconds) and answers queries per keystroke.
- The index is cached to disk, so the next launch searches instantly while a
  refresh scan runs behind it.
- Ranked matching: exact > prefix > word-start > substring; extra words match
  anywhere in the full path (e.g. `screen rover_explorer`).
- Filters: All / Folders / Pictures / Music / Videos / Documents, plus
  "only in current folder".

### The companion

Click him, or leave him idle, and he performs the classic repertoire: barking
(with sound), reading a book, jumping, waving, licking, scratching, digging,
ear flaps, head tilts, tail wags, dozing off, and chasing a ball. While a
search runs he puts his nose to the ground and sniffs; when results land he
turns up with a bone.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Search Companion | `Ctrl+F` |
| New folder | `Ctrl+Shift+N` |
| Rename | `F2` |
| Delete | `Del` |
| Refresh | `F5` |
| Select all | `Ctrl+A` |
| Cut / Copy / Paste | `Ctrl+X` / `Ctrl+C` / `Ctrl+V` |
| Properties | `Alt+Enter` |
| Back / Forward / Up | `Alt+←` / `Alt+→` / `Alt+↑` or `Backspace` |

## Install

### Debian / Ubuntu

```bash
sudo apt install ./rover-explorer_1.0.0_amd64.deb
```

### Windows

Run `RoverExplorer-1.0.0-setup.exe`, or unzip the portable build.

## Build from source

Requires Flutter 3.44+.

```bash
flutter pub get

# Linux
flutter build linux --release
./build/linux/x64/release/bundle/rover_explorer

# Debian package
bash packaging/linux/build-deb.sh

# Windows
flutter build windows --release
iscc packaging\windows\rover-explorer.iss   # installer
```

## Development

```bash
dart format lib test
flutter analyze
flutter test
```

## Project layout

| Path | What it is |
|---|---|
| `lib/app_info.dart` | Product identity and version metadata |
| `lib/screens/explorer_screen.dart` | Main window: menus, toolbar, panes, actions |
| `lib/services/search_index.dart` | Indexer isolate: walk, cache, ranked queries |
| `lib/services/fs_service.dart` | Listing, drives, open-with-OS, copy/move/rename/delete |
| `lib/services/sound_service.dart` | Pluginless bark playback |
| `lib/widgets/rover_dog.dart` | The animated companion and his tricks |
| `lib/widgets/search_pane.dart` | Search Companion sidebar |
| `lib/widgets/folder_tree.dart` | Folders navigation pane |
| `lib/widgets/file_list.dart` | Details/icons views, selection, drag & drop |
| `lib/widgets/task_pane.dart` | Common Tasks sidebar |
| `lib/dialogs/` | About, Properties, Folder Options |
| `lib/xp/` | Luna palette, chrome widgets, dialog shell |
| `packaging/` | Debian, Snap and Windows installer manifests |

The index cache lives in the platform application-support directory as
`rover_index.txt`; delete it to force a cold rebuild.

## Licence

MIT — see [LICENSE](LICENSE). Rover Explorer is an independent project and is
not affiliated with or endorsed by Microsoft Corporation.
