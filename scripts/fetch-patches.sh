#!/usr/bin/env bash
# Downloads the pinned patches into <dest> and verifies every SHA-512.
# usage: scripts/fetch-patches.sh <dest-dir>
# PATCH_RAW_BASE (optional) overrides the download root, used by the tests.
set -euo pipefail
DEST="${1:?usage: fetch-patches.sh <dest-dir>}"
LOCK="${PATCH_LOCK:-$(cd "$(dirname "$0")/.." && pwd)/patches.lock}"
repo=""; commit=""; n=0
while read -r a b; do
  case "$a" in
    ''|\#*) continue ;;
    PATCH_REPO=*)   repo="${a#*=}"; continue ;;
    PATCH_COMMIT=*) commit="${a#*=}"; continue ;;
    PATCH_REV=*)    continue ;;
  esac
  [ -n "$repo" ] && [ -n "$commit" ] || { echo "patches.lock: PATCH_REPO/PATCH_COMMIT must come first" >&2; exit 1; }
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || { echo "patches.lock: PATCH_COMMIT must be a full 40-hex commit" >&2; exit 1; }
  [[ "$b" =~ ^[0-9a-f]{128}$ ]]     || { echo "patches.lock: bad SHA-512 for $a" >&2; exit 1; }
  base="${PATCH_RAW_BASE:-https://raw.githubusercontent.com/$repo/$commit}"
  mkdir -p "$DEST"
  curl -fsSL --retry 3 -m 60 -o "$DEST/$a.patch" "$base/patches/$a.patch"
  echo "$b  $DEST/$a.patch" | sha512sum -c --status - \
    || { echo "CHECKSUM MISMATCH for $a.patch (pinned commit $commit) - refusing to build" >&2; exit 1; }
  echo "ok  $a"
  n=$((n+1))
done < "$LOCK"
[ "$n" -gt 0 ] || { echo "patches.lock lists no patches" >&2; exit 1; }
