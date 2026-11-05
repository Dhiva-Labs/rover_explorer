# Changelog

All notable changes to Rover Explorer are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Packages for other Linux distributions, for x64 and arm64, built from the
  same build as the `.deb` and installed and started on each target in CI:
  an `.rpm` for Fedora and openSUSE, an Arch Linux package, an AppImage and a
  Flatpak bundle, plus an AUR recipe (`rover-explorer-bin`). Tagged releases
  include them.
- Search understands XP-style wildcards (`*.pdf`, `IMG_????.jpg`, `report*`),
  quoted phrases (`"annual report"`) and words with a `/` that match the
  folder path (`src/main`).
- Search keyboard: `Esc` clears the query, `↓` moves into the results, the
  arrow keys walk them and `Enter` opens one. `Ctrl+F` with the pane already
  open puts the cursor back in the query box with the text selected.
- "Only in current folder" now also works outside the indexed home folder
  (other drives, `/mnt`, hidden folders): that folder is walked on demand.

### Fixed

- Search: Backspace in the query box went up one folder (and hid the
  results) instead of deleting a character. The window-wide Backspace, which
  means "up one level", was taken before any text box saw the key; the same
  hit the address bar. Shortcuts now leave keys to whichever text box has
  focus.
- Search: opening the Search Companion (toolbar or `Ctrl+F`) did not put the
  cursor in the query box, so typing went nowhere until the box was clicked.
- Search: word order changed the result. `rover screen` and `screen rover`
  now find the same files; any word may be the one in the file name.
- Search: clearing the query, or navigating away, while a search was still
  running could bring its stale results back over the folder.
- Search: after renaming, deleting, moving or creating items in the app, the
  results kept the old names until the next full rescan. The index is now
  updated on the spot, and files deleted outside the app are dropped from
  results (and the index) instead of listing with a 1970 date.
- Search: on a first run (no index cache yet) searches came back empty while
  the index was being built, and stayed that way. Results now fill in as the
  scan progresses and refresh when it finishes.
- Search: "only in current folder" for `~/foo` also matched `~/foobar`.
- Search: closing the pane left the keyboard nowhere, so shortcuts such as
  Backspace and `Ctrl+F` stopped working until the address bar was clicked.
  Clicking a file now also gives the file list the keyboard (Del, F2, Ctrl+A).
- Search: an error inside the background indexer could stop all further
  searches with the dog sniffing forever; errors are now reported per query.
- Search results are shown best match first (they were re-sorted by name),
  until a column header is clicked.

### Changed

- Searches typed while another is still running no longer queue up: only
  the newest waits, so fast typing cannot build a backlog. One- and
  two-letter searches over a ~420k-entry index dropped from ~70 ms to ~12 ms.
- The index cache is written to a temporary file and renamed into place, so
  a crash mid-write cannot leave a truncated cache. Names containing a line
  break are no longer written to it (they corrupted the line format).

## [1.0.1] - 2026-10-16

Linux and Windows ARM64 builds, Windows fixes and packaging work.

### Added

- Linux and Windows ARM64 builds. CI builds, tests and smoke-runs the app on
  native x64 and arm64 runners, and each release now also carries
  `rover-explorer-<version>-linux-arm64.tar.gz`,
  `rover-explorer_<version>_arm64.deb`,
  `rover-explorer-<version>-windows-arm64.zip` and
  `RoverExplorer-<version>-arm64-setup.exe`, all listed in `SHA256SUMS.txt`.
  The snap and the Microsoft Store package (`--architecture arm64`) build for
  arm64 too.
- Microsoft Store packaging: an `msix_config` block in `pubspec.yaml`
  (`dart run msix:create --store` builds the unsigned Store package) and a
  1024 px logo at `packaging/windows/rover-explorer-logo.png`.
- The Windows executable now carries the Rover icon instead of the default
  Flutter one.
- A privacy policy (`PRIVACY.md`).

### Fixed

- Windows: the window came up empty (a grey area below the address bar) on
  machines with a card reader or DVD drive and no media in it. Probing that
  drive letter throws "The device is not ready", which failed the task pane
  and folder tree builds; such drives are now skipped. The drive list is also
  cached for a few seconds instead of being probed on every rebuild.
- Windows: files and folders with the hidden attribute (`AppData`,
  `NTUSER.DAT`, `desktop.ini`, the legacy profile junctions) are treated like
  dotfiles: hidden unless "show hidden files" is on, and kept out of the
  search index.
- Windows: the bark was cut off before it was heard, because
  `SoundPlayer.Play()` returns immediately and PowerShell exited with it. It
  now uses `PlaySync()`.
- Windows: the bark stayed silent when the temp path contained an apostrophe
  (for example a user name like `O'Neil`).
- The indexer writes its cache file before it reports the scan as finished,
  so "done" means the cache is on disk. Before, anything that acted right
  after the status changed (a test, or deleting the indexed folder) raced the
  write and could find no cache or a file still in use.
- Debian source packages for the PPA now ship the Flutter bundle as
  `bundle.tar.gz`. As a plain directory, `dpkg-source`'s default
  `--tar-ignore` patterns silently dropped `libflutter_linux_gtk.so` and
  `libapp.so`, producing a package that installed but could not start
  (`1.0.0~noble1`). `debian/rules` now asserts both libraries are present so
  the build fails instead of shipping an unusable package.
- Snap: under strict confinement Rover opened and indexed the snap's private
  data directory instead of your home folder. The app now gets
  `HOME=$SNAP_REAL_HOME`, and the snap ships a `.desktop` file so it appears
  in the application menu.
- The snap build no longer inherits a local `build/` directory, whose stale
  `CMakeCache.txt` pointed at the host path and made CMake refuse the
  in-container build.

### Changed

- The snapcraft manifest moved to the canonical `snap/snapcraft.yaml`.
- Debian packaging for the PPA added under `packaging/ppa/`.

## [1.0.0] - 2026-07-22

First public release.

### Added

- **Explorer shell** styled after the Windows XP Luna theme: gradient toolbar,
  menu bar (File / Edit / View / Go / Tools / Help), address bar with a recent
  locations drop-down, status bar, and the beige classic chrome.
- **Common Tasks pane** ("File and Folder Tasks" / "Other Places" / "Details")
  and a lazily-loaded **Folders tree** navigation pane.
- **Search Companion** with an original animated dog: idle tricks (bark with
  sound, read, jump, wave, lick, scratch, floor-scratch, dig, ear flap, head
  tilt, tail wag, sleep, ball), a nose-down sniffing pose while searching, and
  a bone-in-mouth celebration when results arrive.
- **Instant indexed search**: a background isolate keeps an in-memory filename
  index (hundreds of thousands of entries), answers ranked queries on every
  keystroke, and caches the index to disk for an instant next launch.
- Search filters for All / Folders / Pictures / Music / Videos / Documents,
  plus a "only in current folder" scope, and multi-word queries that match
  across the full path.
- **File management**: open with the system handler, cut / copy / paste,
  rename, delete, new folder, multi-select (Ctrl and Shift), drag & drop onto
  folders, sortable columns, details and icons views, hidden-file toggle.
- **Properties dialog** with background size and item counting, and a
  **Folder Options** dialog for hidden files, companion, sounds and index
  rebuilding.
- **About dialog** reporting version, vendor, licence, platform and index size.
- Keyboard shortcuts: `F2` rename, `Del` delete, `F5` refresh, `Ctrl+A` select
  all, `Ctrl+C/X/V`, `Alt+Enter` properties, `Alt+Left/Right/Up` and
  `Backspace` navigation, `Ctrl+F` search, `Ctrl+Shift+N` new folder.
- Packaging for Debian (`.deb`), Snap, and Windows (Inno Setup), plus GitHub
  Actions workflows for CI and releases.

[Unreleased]: https://github.com/Dhiva-Labs/rover_explorer/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/Dhiva-Labs/rover_explorer/releases/tag/v1.0.1
[1.0.0]: https://github.com/Dhiva-Labs/rover_explorer/releases/tag/v1.0.0
