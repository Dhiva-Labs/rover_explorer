#!/usr/bin/env bash
# Renders the AUR PKGBUILD for one release and proves it builds.
#
# usage: aur.sh <amd64.deb> <arm64.deb> <outdir>
#
# Fills PKGBUILD.in with the version, the release download URL and the
# sha256 of both .debs, then, in an archlinux:latest container, generates
# .SRCINFO and runs makepkg on the x86_64 source (the .deb is placed next to
# the PKGBUILD, so makepkg verifies the checksum without downloading), and
# installs the result. Writes <name>-bin-<version>-aur.tar.gz holding
# PKGBUILD and .SRCINFO, ready to push to the AUR.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ $# -eq 3 ] || { echo "usage: $0 <amd64.deb> <arm64.deb> <outdir>" >&2; exit 2; }
deb_amd64="$(readlink -f "$1")"; deb_arm64="$(readlink -f "$2")"
mkdir -p "$3"; out="$(cd "$3" && pwd)"
# shellcheck source=/dev/null
. "$here/../linux-distros/distro.conf"
: "${VERSION:?set VERSION}"
: "${GITHUB_REPO:?distro.conf must set GITHUB_REPO, e.g. Dhiva-Labs/BranchPilot}"
tag="${TAG_PREFIX-v}$VERSION"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
deps=""; for d in "${ARCH_DEPENDS[@]}"; do deps+="'$d' "; done
sed -e "s|@NAME@|$NAME|g" -e "s|@VERSION@|$VERSION|g" \
    -e "s|@SUMMARY@|${SUMMARY//\'/}|g" -e "s|@HOMEPAGE@|$HOMEPAGE|g" \
    -e "s|@LICENSE@|$LICENSE|g" -e "s|@ARCH_DEPENDS@|${deps% }|g" \
    -e "s|@RELEASE_URL@|https://github.com/$GITHUB_REPO/releases/download/$tag|g" \
    -e "s|@RAW_URL@|https://raw.githubusercontent.com/$GITHUB_REPO/$tag|g" \
    -e "s|@SHA_LICENSE@|$(sha256sum "$here/../../$LICENSE_FILE" | cut -d' ' -f1)|g" \
    -e "s|@DEB_AMD64@|$(basename "$deb_amd64")|g" -e "s|@DEB_ARM64@|$(basename "$deb_arm64")|g" \
    -e "s|@SHA_AMD64@|$(sha256sum "$deb_amd64" | cut -d' ' -f1)|g" \
    -e "s|@SHA_ARM64@|$(sha256sum "$deb_arm64" | cut -d' ' -f1)|g" \
    "$here/PKGBUILD.in" > "$work/PKGBUILD"
# The files the Arch package from pack.sh leaves out are removed here too.
removes="" sep=$'\n  '
for p in "${EXCLUDE[@]}" "${PACKAGE_EXCLUDE[@]}"; do
  removes+="${removes:+$sep}rm -r \"\$pkgdir/$p\""
done
removes="${removes:-:}"
pkgbuild="$(cat "$work/PKGBUILD")"
printf '%s\n' "${pkgbuild//@REMOVE@/$removes}" > "$work/PKGBUILD"
cp "$deb_amd64" "$work/"
cp "$here/../../$LICENSE_FILE" "$work/LICENSE-$VERSION"
if grep -n '@[A-Z0-9_]*@' "$work/PKGBUILD"; then echo "unfilled placeholder" >&2; exit 1; fi

docker run --rm -v "$work:/build" archlinux:latest bash -euo pipefail -c '
  pacman -Syu --noconfirm --needed -q base-devel namcap
  useradd -m builder
  chown -R builder /build
  cd /build
  su builder -c "makepkg --printsrcinfo > .SRCINFO"
  su builder -c "makepkg --noconfirm --nodeps -f"
  namcap PKGBUILD
  pacman -U --noconfirm ./*-x86_64.pkg.tar.zst
  # Every ELF file the package installed finds its libraries on Arch.
  missing=0
  for f in $(pacman -Qlq "$(sed -n "s/^pkgname = //p" .SRCINFO)"); do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    [ "$(head -c 4 "$f" | od -An -tx1 | tr -d " \n")" = 7f454c46 ] || continue
    if ldd "$f" | grep "not found"; then echo "^ $f"; missing=1; fi
  done
  [ "$missing" = 0 ]
  cat .SRCINFO
'
tar -C "$work" -czf "$out/$NAME-bin-$VERSION-aur.tar.gz" PKGBUILD .SRCINFO
ls -l "$out/$NAME-bin-$VERSION-aur.tar.gz"
