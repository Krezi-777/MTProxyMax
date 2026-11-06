#!/bin/bash
# Test self_update failure paths with no Docker daemon and no network.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Extract exactly the real function under test.
eval "$(sed -n '/^self_update() {$/,/^# ── Section 13c:/p' "$repo/mtproxymax.sh" | sed '$d')"
declare -f self_update >/dev/null

run_failure_case() (
    local scenario="$1"
    local dir="$tmp/$scenario"
    mkdir -p "$dir/install" "$dir/backup"
    INSTALL_DIR="$dir/install"
    BACKUP_DIR="$dir/backup"
    _UPDATE_BADGE="$dir/badge"
    _UPDATE_SHA_FILE="$dir/sha"
    VERSION="1.4.2-LTS"
    GITHUB_REPO="SamNet-dev/MTProxyMax"
    TELEMT_MIN_VERSION="3.5.16"
    TELEMT_COMMIT="84e5b82"
    DOCKER_IMAGE_BASE="telemt-local"
    REGISTRY_IMAGE="ghcr.io/example/telemt"
    TELEGRAM_ENABLED=false
    REPLICATION_ENABLED=false
    BOLD=""
    NC=""
    MTPROXYMAX_ALLOW_UPSTREAM_OVERWRITE=0
    _SCRIPT_NEEDS_REEXEC=false
    printf 'unchanged-script\n' > "$INSTALL_DIR/mtproxymax"
    printf '3.5.14-old\n' > "$INSTALL_DIR/.telemt_version"
    printf 'original-config\n' > "$dir/config"
    sha256sum "$INSTALL_DIR/mtproxymax" "$dir/config" > "$dir/before"

    log_info() { :; }
    log_warn() { :; }
    log_error() { :; }
    log_success() { :; }
    _mktemp() { mktemp "$dir/remote.XXXXXX"; }
    curl() {
        local output="" prev="" arg
        for arg in "$@"; do
            if [ "$prev" = "-o" ]; then output="$arg"; break; fi
            prev="$arg"
        done
        [ -n "$output" ] || return 1
        # Full script validates Bash syntax, known project signature, and size.
        cp "$repo/mtproxymax.sh" "$output"
        printf '\n# simulated upstream change\n' >> "$output"
    }
    get_telemt_version() { printf '3.5.14-old\n'; }
    _version_gte() { return 1; }
    build_telemt_image() {
        echo "build" >> "$dir/calls"
        case "$scenario" in
            restart-failure|restart-not-running)
                printf '3.5.16-84e5b82\n' > "$INSTALL_DIR/.telemt_version"
                return 0 ;;
            *) return 1 ;;
        esac
    }
    is_proxy_running() {
        echo "running-check" >> "$dir/calls"
        if [ "$scenario" = "restart-not-running" ] && [ -e "$dir/restart-attempted" ]; then
            return 1
        fi
        return 0
    }
    load_secrets() { echo "load-secrets" >> "$dir/calls"; }
    restart_proxy_container() {
        echo "restart" >> "$dir/calls"
        : > "$dir/restart-attempted"
        [ "$scenario" != "restart-failure" ]
    }
    docker() { echo "docker $*" >> "$dir/calls"; return 0; }
    if [ "$scenario" != "fork-guard" ]; then
        # Keep the installed script unchanged, to isolate the engine failure path.
        cp "$repo/mtproxymax.sh" "$INSTALL_DIR/mtproxymax"
        cp "$INSTALL_DIR/mtproxymax" "$dir/remote-pinned"
        sha256sum "$INSTALL_DIR/mtproxymax" "$dir/config" > "$dir/before"
        curl() {
            local output="" prev="" arg
            for arg in "$@"; do
                if [ "$prev" = "-o" ]; then output="$arg"; break; fi
                prev="$arg"
            done
            [ -n "$output" ] || return 1
            cp "$dir/remote-pinned" "$output"
        }
    fi
    # Simulate user declining a script change when testing engine failure.
    # For fork protection case, simulate user accepting an upstream replacement.
    if [ "$scenario" != "fork-guard" ]; then
        input="n"
    else
        input="y"
    fi
    if self_update <<< "$input"; then
        echo "FAIL: $scenario unexpectedly returned success" >&2
        exit 1
    fi
    sha256sum -c "$dir/before" >/dev/null
    test "$(cat "$INSTALL_DIR/.telemt_version")" = "3.5.14-old"
    case "$scenario" in
        build-failure)
            test "$(cat "$dir/calls")" = "build" ;;
        restart-failure)
            test "$(cat "$dir/calls")" = "$(printf 'build\nrunning-check\nload-secrets\nrestart')" ;;
        restart-not-running)
            test "$(cat "$dir/calls")" = "$(printf 'build\nrunning-check\nload-secrets\nrestart\nrunning-check')" ;;
        fork-guard)
            test ! -s "$dir/calls" ;;
    esac
    test "$_SCRIPT_NEEDS_REEXEC" = false
    echo "  PASS: $scenario retained prior script, config, version and avoided container changes"
)

run_failure_case build-failure
run_failure_case fork-guard
run_failure_case restart-failure
run_failure_case restart-not-running
echo 'PASS: self_update fail-closed regression tests'
