#!/usr/bin/env bash
# No network or Docker: verify the explicit pinned fork update path.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
eval "$(sed -n '/^self_update() {$/,/^# ── Section 13c:/p' "$repo/mtproxymax.sh" | sed '$d')"
declare -f self_update >/dev/null
pinned_commit='496ae9f19e78f8e6095cbd14ff23c1bd9c2adaed'
real_sha="$(sha256sum "$repo/mtproxymax.sh" | cut -d' ' -f1)"

verify_case() (
    local mode="$1"
    local dir="$tmp/$mode"
    mkdir -p "$dir/install" "$dir/backups"
    INSTALL_DIR="$dir/install"
    BACKUP_DIR="$dir/backups"
    _UPDATE_BADGE="$dir/badge"
    _UPDATE_SHA_FILE="$dir/sha"
    VERSION="1.4.2-LTS"
    GITHUB_REPO="SamNet-dev/MTProxyMax"
    TELEMT_MIN_VERSION="3.5.16"
    TELEMT_COMMIT="84e5b82"
    TELEGRAM_ENABLED=false
    REPLICATION_ENABLED=false
    BOLD="" NC=""
    _SCRIPT_NEEDS_REEXEC=false
    MTPROXYMAX_ALLOW_UPSTREAM_OVERWRITE=0
    MTPROXYMAX_FORK_UPDATE_COMMIT="$pinned_commit"
    MTPROXYMAX_FORK_UPDATE_SHA256="$real_sha"
    test "$mode" = valid || MTPROXYMAX_FORK_UPDATE_SHA256="$(printf '%064d' 0)"
    printf 'old-script\n' > "$INSTALL_DIR/mtproxymax"
    printf '3.5.16-84e5b82\n' > "$INSTALL_DIR/.telemt_version"
    printf 'unchanged-config\n' > "$dir/config"
    sha256sum "$dir/config" > "$dir/config.sha"
    log_info() { :; }; log_warn() { :; }; log_error() { :; }; log_success() { :; }
    _mktemp() { mktemp "$dir/remote.XXXXXX"; }
    get_telemt_version() { printf '3.5.16-84e5b82\n'; }
    _version_gte() { return 0; }
    curl() {
        local output="" prior="" arg found_url=false
        for arg in "$@"; do
            [ "$arg" != "https://raw.githubusercontent.com/Krezi-777/MTProxyMax/$pinned_commit/mtproxymax.sh" ] || found_url=true
            if [ "$prior" = "-o" ]; then output="$arg"; fi
            prior="$arg"
        done
        [ -n "$output" ] && [ "$found_url" = true ] || return 1
        cp "$repo/mtproxymax.sh" "$output"
    }
    if [ "$mode" = valid ]; then
        self_update <<< y
        cmp -s "$INSTALL_DIR/mtproxymax" "$repo/mtproxymax.sh"
        test "$(find "$BACKUP_DIR" -type f | wc -l)" -eq 1
        test "$(cat "$_UPDATE_SHA_FILE")" = "$pinned_commit"
        test "$_SCRIPT_NEEDS_REEXEC" = true
    else
        if self_update <<< y; then
            echo 'FAIL: mismatched SHA256 accepted' >&2; exit 1
        fi
        test "$(cat "$INSTALL_DIR/mtproxymax")" = old-script
        test -z "$(find "$BACKUP_DIR" -type f)"
    fi
    sha256sum -c "$dir/config.sha" >/dev/null
    printf '  PASS: pinned fork source %s\n' "$mode"
)

verify_case valid
verify_case invalid-sha
echo 'PASS: verified fork source update tests (2/2)'
