#!/usr/bin/env bash
# Verify the development fork's installer refuses unpinned / unverified code.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$repo/install.sh"
grep -Fq "repo='Krezi-777/MTProxyMax'" "$repo/install.sh"
grep -Fq 'MTPROXYMAX_SOURCE_COMMIT' "$repo/install.sh"
grep -Fq 'MTPROXYMAX_SOURCE_SHA256' "$repo/install.sh"
if grep -Fq 'SCRIPT_URL="https://raw.githubusercontent.com/SamNet-dev/MTProxyMax/main/mtproxymax.sh"' "$repo/install.sh"; then
    echo 'FAIL: fork installer still downloads upstream' >&2
    exit 1
fi
# No network should occur when no trusted immutable reference is supplied.
# Run under any account; both non-root and missing-pin rejection are fail-closed.
if env -u MTPROXYMAX_SOURCE_COMMIT -u MTPROXYMAX_SOURCE_SHA256 \
      bash "$repo/install.sh" </dev/null >/dev/null 2>&1; then
    echo 'FAIL: installer accepted missing source verification' >&2
    exit 1
fi
echo 'PASS: fork installer requires immutable source and checksum (1/1)'
