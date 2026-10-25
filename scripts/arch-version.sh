#!/usr/bin/env bash
# Prints "<pkgver> <pkgrel>" of strongswan as currently shipped in Arch's
# stable repos (core/extra, x86_64).  Fails loudly on anything unexpected.
set -euo pipefail
parse() { jq -r '[.pkgver, .pkgrel] | @tsv' 2>/dev/null; }
out=""
# 1) package details endpoint
out="$(curl -fsSL --retry 3 -m 30 https://archlinux.org/packages/extra/x86_64/strongswan/json/ | parse || true)"
# 2) search endpoint as a fallback (package could move between repos)
if ! grep -Eq '^[0-9][0-9A-Za-z._+~]*[[:space:]]+[0-9]+(\.[0-9]+)?$' <<<"$out"; then
  out="$(curl -fsSL --retry 3 -m 30 'https://archlinux.org/packages/search/json/?name=strongswan&repo=Extra&repo=Core&arch=x86_64' \
        | jq -r '.results[0] | [.pkgver, .pkgrel] | @tsv' || true)"
fi
if ! grep -Eq '^[0-9][0-9A-Za-z._+~]*[[:space:]]+[0-9]+(\.[0-9]+)?$' <<<"$out"; then
  echo "arch-version: could not determine Arch's strongswan version (got: '$out')" >&2
  exit 1
fi
echo "$out" | tr '\t' ' '
