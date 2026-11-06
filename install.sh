#!/usr/bin/env bash
# Unofficial MTProxyMax fork installer — development only.
# NO DEFAULT SOURCE: caller must explicitly pin and verify a reviewed revision.
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo 'ERROR: this installer requires root; it never calls sudo automatically' >&2
    exit 1
fi

repo='Krezi-777/MTProxyMax'
revision="${MTPROXYMAX_SOURCE_COMMIT:-}"
expected_sha="${MTPROXYMAX_SOURCE_SHA256:-}"

if [[ ! "$revision" =~ ^[[:xdigit:]]{40}$ ]] ||
   [[ ! "$expected_sha" =~ ^[[:xdigit:]]{64}$ ]]; then
    echo 'ERROR: supply MTPROXYMAX_SOURCE_COMMIT (40 hex) and MTPROXYMAX_SOURCE_SHA256 (64 hex)' >&2
    echo 'No moving branch and no unchecked installer payload is allowed.' >&2
    exit 1
fi
expected_sha="${expected_sha,,}"
url="https://raw.githubusercontent.com/${repo}/${revision}/mtproxymax.sh"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

curl -fsSL --max-time 90 --max-filesize 5242880 --output "$tmp" "$url"
actual_sha="$(sha256sum "$tmp" | cut -d' ' -f1)"
if [[ "$actual_sha" != "$expected_sha" ]]; then
    echo "ERROR: installer checksum mismatch; refusing to execute (actual: $actual_sha)" >&2
    exit 1
fi
bash -n "$tmp"
if ! grep -Fq 'GITHUB_REPO="SamNet-dev/MTProxyMax"' "$tmp"; then
    echo 'ERROR: downloaded file is not recognizable as MTProxyMax' >&2
    exit 1
fi
if [[ "$(wc -c < "$tmp")" -lt 10000 ]]; then
    echo 'ERROR: unexpected short installer payload' >&2
    exit 1
fi

echo "Verified unofficial fork source: ${repo}@${revision}"
echo "SHA256: $actual_sha"
bash "$tmp" install
