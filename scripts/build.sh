#!/usr/bin/env bash
# Builds Arch's current strongswan with the pinned FortiGate patches.
# Must run as a NON-root user inside an Arch environment (makepkg refuses root);
# the workflow does that in an archlinux:base-devel container.
# Output goes to ./out : package, PKGBUILD, patches, checksums, release notes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/work"; OUT="$ROOT/out"
die() { echo "build: $*" >&2; exit 1; }
rm -rf "$WORK" "$OUT"; mkdir -p "$WORK" "$OUT"

read -r PKGVER PKGREL < <("$ROOT/scripts/arch-version.sh")
REV="$(sed -n 's/^PATCH_REV=//p' "$ROOT/patches.lock")"
PATCH_REPO="$(sed -n 's/^PATCH_REPO=//p' "$ROOT/patches.lock")"
PATCH_COMMIT="$(sed -n 's/^PATCH_COMMIT=//p' "$ROOT/patches.lock")"
echo "== Arch ships strongswan $PKGVER-$PKGREL; building $PKGVER-$PKGREL.$REV"

# Arch's own packaging repo, at the tag of the version that is in the repos
git clone --quiet https://gitlab.archlinux.org/archlinux/packaging/packages/strongswan.git "$WORK/pkg"
cd "$WORK/pkg"
if git rev-parse -q --verify "refs/tags/$PKGVER-$PKGREL" >/dev/null; then
  git checkout -q "$PKGVER-$PKGREL"
else
  echo "::warning::tag $PKGVER-$PKGREL not found in Arch's packaging repo, using the default branch"
fi
PKGING_COMMIT="$(git rev-parse HEAD)"
got_ver="$(sed -n 's/^pkgver=//p' PKGBUILD | head -1)"; got_rel="$(sed -n 's/^pkgrel=//p' PKGBUILD | head -1)"
[ "$got_ver-$got_rel" = "$PKGVER-$PKGREL" ] \
  || die "packaging repo has $got_ver-$got_rel but Arch ships $PKGVER-$PKGREL (retry later, a rebuild may be in flight)"

# PGP keys for makepkg's signature check -- never skipped
if compgen -G "keys/pgp/*.asc" >/dev/null; then
  gpg --batch --import keys/pgp/*.asc
else
  for fpr in $(sed -n '/^validpgpkeys/,/)/p' PKGBUILD | grep -oE '[0-9A-Fa-f]{40}'); do
    ok=0
    for try in 1 2 3; do
      gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "$fpr" && { ok=1; break; }; sleep 5
    done
    [ "$ok" = 1 ] || die "could not fetch signing key $fpr"
  done
fi

"$ROOT/scripts/fetch-patches.sh" "$WORK/pkg"
python3 -I "$ROOT/scripts/patch-pkgbuild.py" PKGBUILD "$WORK/pkg"

export MAKEFLAGS="-j$(nproc)"
makepkg --syncdeps --noconfirm --nocheck --cleanbuild 2>&1 | tee "$WORK/makepkg.log"

pkgs=(strongswan-[0-9]*.pkg.tar.*)
[ "${#pkgs[@]}" -eq 1 ] && [ -f "${pkgs[0]}" ] || die "expected exactly one strongswan package, found: ${pkgs[*]}"
PKG="${pkgs[0]}"
cp "$PKG" "$OUT/"
cp PKGBUILD "$OUT/PKGBUILD"
makepkg --printsrcinfo > "$OUT/.SRCINFO"
cp ./*.patch "$OUT/"   # flat, next to the PKGBUILD: releases can only hold files, and makepkg expects them here
cat > "$OUT/BUILD_INFO.txt" <<INFO
package:          $PKG
arch version:     $PKGVER-$PKGREL
patch revision:   $REV
arch packaging:   https://gitlab.archlinux.org/archlinux/packaging/packages/strongswan/-/tree/$PKGING_COMMIT
patches:          https://github.com/$PATCH_REPO/tree/$PATCH_COMMIT  (SHA-512 pinned in patches.lock)
built (UTC):      $(date -u +%Y-%m-%dT%H:%M:%SZ)
INFO
(cd "$OUT" && sha256sum "$PKG" PKGBUILD ./*.patch > SHA256SUMS)

cat > "$OUT/RELEASE_NOTES.md" <<NOTES
Arch Linux \`strongswan\` **$PKGVER-$PKGREL** with the FortiGate compatibility patches from
[$PATCH_REPO@${PATCH_COMMIT:0:12}](https://github.com/$PATCH_REPO/tree/$PATCH_COMMIT) applied.

**Install** (x86_64 Arch/CachyOS):

\`\`\`bash
sha256sum -c SHA256SUMS --ignore-missing
sudo pacman -U $PKG
sudo systemctl restart strongswan
\`\`\`

Not signed with a PGP key: verify the checksum, or build it yourself from the attached \`PKGBUILD\` and \`.patch\` files (put them in one folder and run \`makepkg -s\`).
Source: strongSwan $PKGVER from download.strongswan.org (signature verified by makepkg) + the patches listed in \`BUILD_INFO.txt\`.
NOTES
echo "== done: $OUT"; ls -la "$OUT"
