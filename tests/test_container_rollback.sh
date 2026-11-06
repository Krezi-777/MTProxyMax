#!/bin/bash
# Fully mocked Docker transaction tests; never accesses a real Docker daemon.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Load the actual helper, not a copied implementation.
eval "$(sed -n '/^upgrade_proxy_container_with_rollback() {$/,/^restart_proxy_container() {$/p' "$repo/mtproxymax.sh" | sed '$d')"
declare -f upgrade_proxy_container_with_rollback >/dev/null

check_case() (
    local scenario="$1"
    local work="$tmp/$scenario"
    mkdir -p "$work"
    CONTAINER_NAME=mtproxymax
    CONFIG_DIR="$work"
    old_name=mtproxymax
    old_running=true
    new_exists=false
    new_running=false
    backup_name=""
    printf 'config-original\n' > "$work/config.toml"
    cp "$work/config.toml" "$work/config.before"
    : > "$work/calls"

    log_info() { :; }
    log_warn() { :; }
    log_error() { :; }
    sleep() { :; }
    flush_traffic_to_disk() { :; }
    _start_all_instances() { :; }
    apply_firewall_rules() { :; }
    speed_limit_apply() { :; }
    is_proxy_running() {
        if [ "$new_exists" = true ]; then
            [ "$new_running" = true ]
        else
            [ "$old_name" = "$CONTAINER_NAME" ] && [ "$old_running" = true ]
        fi
    }
    run_proxy_container() {
        printf '%s\n' run_proxy_container >> "$work/calls"
        new_exists=true
        printf "config-modified\\n" > "$work/config.toml"
        case "$scenario" in
            start-fails) new_running=false; return 1 ;;
            new-crashes) new_running=false; return 0 ;;
            *) new_running=true; return 0 ;;
        esac
    }
    docker() {
        printf 'docker %s\n' "$*" >> "$work/calls"
        case "$1" in
            inspect)
                # Rollback-name collision preflight uses plain inspect.
                # Health probes use formatted inspect and must simulate the
                # stable Docker ID and RestartCount of the replacement.
                if [ "${2:-}" = "-f" ]; then
                    [ "$new_exists" = true ] || return 1
                    case "${3:-}" in
                        '{{.Id}}') printf 'mock-new-container-id\\n' ;;
                        '{{.RestartCount}}') printf '0\\n' ;;
                        *) return 1 ;;
                    esac
                    return 0
                fi
                return 1 ;;
            update) return 0 ;;
            stop)
                [ "$scenario" != "stop-fails" ] || return 1
                old_running=false ;;
            rename)
                if [ "$2" = "$CONTAINER_NAME" ]; then
                    [ "$scenario" != "rename-fails" ] || return 1
                    old_name="$3"
                    backup_name="$3"
                elif [ "$2" = "$backup_name" ] && [ "$3" = "$CONTAINER_NAME" ]; then
                    old_name="$CONTAINER_NAME"
                    backup_name=""
                else
                    return 1
                fi ;;
            rm)
                new_exists=false
                new_running=false ;;
            start)
                old_running=true ;;
            rmi)
                echo 'FAIL: Docker image deleted during protected upgrade' >&2
                return 1 ;;
            *)
                echo "FAIL: unexpected Docker action: $*" >&2
                return 1 ;;
        esac
    }

    if [ "$scenario" = "success" ]; then
        upgrade_proxy_container_with_rollback
        test "$new_exists" = true
        test "$new_running" = true
        test "$old_running" = false
        test "$old_name" != "$CONTAINER_NAME"
        test -n "$backup_name"
    else
        if upgrade_proxy_container_with_rollback; then
            echo "FAIL: $scenario returned success" >&2
            exit 1
        fi
        test "$old_running" = true
        test "$old_name" = "$CONTAINER_NAME"
        test "$new_exists" = false
    fi
    if [ "$scenario" = success ]; then
        grep -Fq "config-modified" "$work/config.toml"
    else
        cmp -s "$work/config.toml" "$work/config.before"
    fi
    ! grep -q '^docker rmi ' "$work/calls"
    printf '  PASS: %s\n' "$scenario"
)

cases=(success start-fails new-crashes stop-fails rename-fails)
passed=0
for scenario in "${cases[@]}"; do
    check_case "$scenario"
    passed=$((passed+1))
done
test "$passed" -eq 5
echo 'PASS: protected container upgrade transaction (5/5 scenarios)'
