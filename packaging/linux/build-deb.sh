#!/usr/bin/env bash
#
# Builds a Debian package for Rover Explorer from a release Linux build.
#
#   packaging/linux/build-deb.sh [version]
#
# The release bundle must already exist (flutter build linux --release). The
# package is built for the machine's architecture: amd64 or arm64.
# Output: dist/rover-explorer_<version>_<amd64|arm64>.deb
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

VERSION="${1:-$(grep -m1 '^version:' pubspec.yaml | sed 's/version: *//' | cut -d+ -f1)}"
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64) FLUTTER_ARCH=x64 ;;
  arm64) FLUTTER_ARCH=arm64 ;;
  *)
    echo "error: unsupported architecture '$ARCH' (amd64 or arm64)" >&2
    exit 1
    ;;
esac
BUNDLE="build/linux/${FLUTTER_ARCH}/release/bundle"
STAGE="build/deb/rover-explorer_${VERSION}_${ARCH}"

if [[ ! -x "$BUNDLE/rover_explorer" ]]; then
  echo "error: $BUNDLE/rover_explorer not found — run 'flutter build linux --release' first" >&2
  exit 1
fi

echo "==> Staging ${VERSION} (${ARCH})"
rm -rf "$STAGE"
mkdir -p "$STAGE"/{DEBIAN,opt/rover-explorer,usr/bin,usr/share/applications} \
         "$STAGE/usr/share/icons/hicolor/256x256/apps" \
         "$STAGE/usr/share/doc/rover-explorer"

cp -r "$BUNDLE"/* "$STAGE/opt/rover-explorer/"
cp assets/icons/rover-explorer.png \
   "$STAGE/usr/share/icons/hicolor/256x256/apps/rover-explorer.png"
cp packaging/linux/rover-explorer.desktop "$STAGE/usr/share/applications/"
cp LICENSE "$STAGE/usr/share/doc/rover-explorer/copyright"
gzip -9 -c CHANGELOG.md > "$STAGE/usr/share/doc/rover-explorer/changelog.gz"

cat > "$STAGE/usr/bin/rover-explorer" <<'LAUNCHER'
#!/bin/sh
exec /opt/rover-explorer/rover_explorer "$@"
LAUNCHER
chmod 755 "$STAGE/usr/bin/rover-explorer"

INSTALLED_KB="$(du -sk "$STAGE" | cut -f1)"

cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: rover-explorer
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${ARCH}
Depends: libgtk-3-0, libglib2.0-0
Installed-Size: ${INSTALLED_KB}
Maintainer: Dhiva Labs <dhivakar1010@gmail.com>
Homepage: https://github.com/Dhiva-Labs/rover_explorer
Description: Windows XP-style file explorer with a search companion dog
 Rover Explorer is a file manager for Linux styled after the Windows XP
 Luna interface. It ships an animated search-companion dog and an
 Everything-style indexed filename search that returns ranked results on
 every keystroke across hundreds of thousands of files.
CONTROL

cat > "$STAGE/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
POSTINST
chmod 755 "$STAGE/DEBIAN/postinst"
cp "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/postrm"

chmod -R go-w "$STAGE/opt" "$STAGE/usr"
chmod 755 "$STAGE/opt/rover-explorer/rover_explorer"

mkdir -p dist
OUT="dist/rover-explorer_${VERSION}_${ARCH}.deb"
dpkg-deb --build --root-owner-group "$STAGE" "$OUT"
echo "==> Built $OUT"
sha256sum "$OUT"
