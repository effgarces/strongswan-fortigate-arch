#!/usr/bin/env bash
# Offline tests for patch-pkgbuild.py and fetch-patches.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok   $*"; }

names="$(awk '!/^#/ && NF==2 && $1 !~ /=/ {print $1}' patches.lock)"
count="$(wc -l <<<"$names")"
rev="$(sed -n 's/^PATCH_REV=//p' patches.lock)"
mkdir "$T/p"; for n in $names; do echo "dummy $n" > "$T/p/$n.patch"; done

# 1. normal case
cp tests/fixtures/PKGBUILD "$T/PKGBUILD"
python3 scripts/patch-pkgbuild.py "$T/PKGBUILD" "$T/p" >/dev/null
grep -qx "pkgrel=2.$rev" "$T/PKGBUILD"                     || fail "pkgrel not bumped"
for n in $names; do grep -q "^        $n.patch)\?$" "$T/PKGBUILD" || fail "$n missing in source"; done
first="$(head -1 <<<"$names")"; h="$(sha512sum "$T/p/$first.patch" | cut -d' ' -f1)"
grep -q "'$h'" "$T/PKGBUILD"                               || fail "checksum of $first missing"
[ "$(grep -cE "^ +'[0-9a-f]{128}'" "$T/PKGBUILD")" -ge "$count" ] || fail "too few checksums"
grep -q -- '--fuzz=0' "$T/PKGBUILD"                        || fail "fuzz=0 missing"
bash -n "$T/PKGBUILD"                                      || fail "syntax"
pass "patches added to source, checksums, pkgrel and prepare()"

# 2. refuses to patch twice
python3 scripts/patch-pkgbuild.py "$T/PKGBUILD" "$T/p" >/dev/null 2>&1 && fail "second run should fail"
pass "refuses double patching"

# 3. no checksum array -> must fail
grep -v '^sha512sums\|^            .SKIP' tests/fixtures/PKGBUILD | sed "/^[[:space:]]*$/d" > "$T/nosum"
sed -i '/^validpgpkeys/d' "$T/nosum"
python3 scripts/patch-pkgbuild.py "$T/nosum" "$T/p" >/dev/null 2>&1 && fail "should fail without checksums"
pass "fails loudly without a checksum array"

# 4. no prepare() -> one is created before build()
awk '/^prepare\(\)/{skip=1} skip&&/^}/{skip=0;next} !skip' tests/fixtures/PKGBUILD > "$T/noprep"
python3 scripts/patch-pkgbuild.py "$T/noprep" "$T/p" >/dev/null
grep -q '^prepare() {' "$T/noprep" && bash -n "$T/noprep"  || fail "prepare() not created"
pass "creates prepare() when missing"

# 5. fetch-patches: good and bad checksums
mkdir -p "$T/raw/patches"; : > "$T/lock"
{ echo "PATCH_REPO=x/y"; echo "PATCH_COMMIT=$(printf '0%.0s' {1..40})"; echo "PATCH_REV=1"; } > "$T/lock"
for n in $names; do cp "$T/p/$n.patch" "$T/raw/patches/"; echo "$n $(sha512sum "$T/p/$n.patch" | cut -d' ' -f1)" >> "$T/lock"; done
PATCH_LOCK="$T/lock" PATCH_RAW_BASE="file://$T/raw" scripts/fetch-patches.sh "$T/dl" >/dev/null || fail "good fetch failed"
echo tampered >> "$T/raw/patches/$first.patch"
PATCH_LOCK="$T/lock" PATCH_RAW_BASE="file://$T/raw" scripts/fetch-patches.sh "$T/dl2" >/dev/null 2>&1 && fail "tampered patch accepted"
pass "fetch-patches accepts good and rejects tampered patches"
echo "all tests passed"
