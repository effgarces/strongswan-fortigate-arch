#!/usr/bin/env bash
# Moves the pin to a newer commit of the patch repo and shows what changed.
# usage: scripts/update-lock.sh <new-commit-sha>      (then REVIEW the diff!)
# The list/order of patches is taken from PATCHES=(...) in the upstream build.sh.
set -euo pipefail
NEW="${1:?usage: update-lock.sh <40-hex-commit>}"
[[ "$NEW" =~ ^[0-9a-f]{40}$ ]] || { echo "need a full 40-hex commit sha" >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/patches.lock"
repo="$(sed -n 's/^PATCH_REPO=//p' "$LOCK")"
old="$(sed -n 's/^PATCH_COMMIT=//p' "$LOCK")"
rev="$(sed -n 's/^PATCH_REV=//p' "$LOCK")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fetch_set() {  # <commit> <dir>
  local base="${PATCH_RAW_BASE:-https://raw.githubusercontent.com/$repo/$1}"
  mkdir -p "$2"
  curl -fsSL --retry 3 -m 60 -o "$2/build.sh" "$base/build.sh"
  awk '/^PATCHES=\(/{f=1;next} f&&/^\)/{exit} f{gsub(/[[:space:]]/,""); if($0!="") print}' "$2/build.sh" > "$2/list"
  [ -s "$2/list" ] || { echo "could not read the PATCHES=(...) list from upstream build.sh" >&2; exit 1; }
  while read -r n; do curl -fsSL --retry 3 -m 60 -o "$2/$n.patch" "$base/patches/$n.patch"; done < "$2/list"
}
fetch_set "$old" "$T/old"; fetch_set "$NEW" "$T/new"
echo "=== patch list (old -> new) ==="; diff "$T/old/list" "$T/new/list" && echo "(same list and order)"
echo "=== patch content changes ==="
changed=0
while read -r n; do
  if [ -f "$T/old/$n.patch" ]; then
    diff -u "$T/old/$n.patch" "$T/new/$n.patch" && continue || changed=1
  else echo "NEW PATCH: $n"; changed=1; fi
done < "$T/new/list"
[ "$changed" = 1 ] || echo "(no patch content changed)"
{
  sed -n '1,/^PATCH_REPO=/{/^PATCH_REPO=/!p}' "$LOCK"
  echo "PATCH_REPO=$repo"; echo "PATCH_COMMIT=$NEW"; echo "PATCH_REV=$((rev+1))"; echo
  echo "# name  sha512   (listed in the order they are applied -- order matters)"
  while read -r n; do echo "$n $(sha512sum "$T/new/$n.patch" | cut -d' ' -f1)"; done < "$T/new/list"
} > "$T/lock.new"
cp "$T/lock.new" "$LOCK"
echo; echo "patches.lock updated (PATCH_REV -> $((rev+1))). Read the diff above, then commit."
