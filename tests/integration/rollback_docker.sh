#!/usr/bin/env bash
# Integration test: real Docker container lifecycle with isolated Alpine test containers.
# Never use production names, secrets, networks, or volumes.
set -euo pipefail
cd "$(dirname "$0")/../.."
test "$(id -u)" -ne 0 || true
command -v docker >/dev/null
docker info >/dev/null

# Run the actual production helper, extracted without loading daemon/installation code.
fn="$(mktemp)"
trap 'rm -f "$fn"; cleanup_all' EXIT
sed -n '/^upgrade_proxy_container_with_rollback() {$/,/^restart_proxy_container() {$/p' mtproxymax.sh | sed '$d' > "$fn"
grep -q '^upgrade_proxy_container_with_rollback() {' "$fn"
source "$fn"

prefix="mtproxy-rollback-ci-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
scratch="$(mktemp -d)"
cleanup_all() {
    local name
    while IFS= read -r name; do
        case "$name" in
            "$prefix"*) command docker rm -f "$name" >/dev/null 2>&1 || true ;;
        esac
    done < <(command docker ps -a --format '{{.Names}}')
    rm -rf "$scratch"
}
# The image is fetched only for the isolated test runner.
command docker pull alpine:3.20 >/dev/null
image_before="$(command docker image inspect alpine:3.20 -f '{{.Id}}')"

log_error() { echo "ERROR: $*" >&2; }
log_warn() { echo "WARN: $*" >&2; }
log_info() { echo "INFO: $*" >&2; }
flush_traffic_to_disk() { :; }
_start_all_instances() { :; }
apply_firewall_rules() { :; }
speed_limit_apply() { :; }
is_proxy_running() {
    [ "$(command docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" = "true" ]
}
# Fault injection is limited to one Docker rename on the current test's rollback path.
docker() {
    if [ "${FAULT_RESTORE_RENAME:-0}" = "1" ] &&
       [ "$1" = rename ] && [[ "$2" == *-rollback-* ]]; then
        echo "INJECTED: rollback rename fails" >&2
        return 1
    fi
    command docker "$@"
}
run_proxy_container() {
    case "$mode" in
        success)
            docker run -d --name "$CONTAINER_NAME" --network none \
              -v "$scratch/config:/test/config:ro" alpine:3.20 sleep 600 >/dev/null ;;
        start-fails)
            # Container creation fails; real Docker returns a nonzero status.
            docker run -d --name "$CONTAINER_NAME" --network none \
              --entrypoint /nonexistent-telemt-smoke-command alpine:3.20 >/dev/null 2>&1 ;;
        new-crashes|restore-rename-fails)
            docker run -d --name "$CONTAINER_NAME" --network none \
              alpine:3.20 sh -c 'exit 17' >/dev/null
            # Wait until Docker has observed the crash, eliminating race conditions.
            command docker wait "$CONTAINER_NAME" >/dev/null
            return 0 ;;
        *) return 1 ;;
    esac
}

printf 'test-configuration-must-survive\n' > "$scratch/config"
config_hash="$(sha256sum "$scratch/config" | cut -d' ' -f1)"

for mode in success start-fails new-crashes restore-rename-fails; do
    CONTAINER_NAME="$prefix-$mode"
    FAULT_RESTORE_RENAME=0
    docker run -d --name "$CONTAINER_NAME" --network none \
      -v "$scratch/config:/test/config:ro" alpine:3.20 sleep 600 >/dev/null
    is_proxy_running
    original_id="$(command docker inspect -f '{{.Id}}' "$CONTAINER_NAME")"

    if [ "$mode" = restore-rename-fails ]; then
        FAULT_RESTORE_RENAME=1
    fi
    if [ "$mode" = success ]; then
        upgrade_proxy_container_with_rollback
    else
        if upgrade_proxy_container_with_rollback; then
            echo "FAIL: $mode falsely reported a successful upgrade" >&2
            exit 1
        fi
    fi
    FAULT_RESTORE_RENAME=0

    # The backup name is created by the actual helper.
    backup="$(command docker ps -a --format '{{.Names}}' | grep -E "^$CONTAINER_NAME-rollback-" | head -n 1 || true)"
    case "$mode" in
        success)
            is_proxy_running
            [ -n "$backup" ]
            [ "$(command docker inspect -f '{{.Id}}' "$backup")" = "$original_id" ]
            [ "$(command docker inspect -f '{{.State.Running}}' "$backup")" = false ]
            [ "$(command docker inspect -f '{{.Id}}' "$CONTAINER_NAME")" != "$original_id" ] ;;
        restore-rename-fails)
            ! is_proxy_running
            [ -n "$backup" ]
            [ "$(command docker inspect -f '{{.Id}}' "$backup")" = "$original_id" ]
            [ "$(command docker inspect -f '{{.State.Running}}' "$backup")" = false ] ;;
        *)
            is_proxy_running
            [ -z "$backup" ]
            [ "$(command docker inspect -f '{{.Id}}' "$CONTAINER_NAME")" = "$original_id" ]
            [ "$(command docker exec "$CONTAINER_NAME" cat /test/config)" = "test-configuration-must-survive" ] ;;
    esac
    [ "$(sha256sum "$scratch/config" | cut -d' ' -f1)" = "$config_hash" ]
    [ "$(command docker image inspect alpine:3.20 -f '{{.Id}}')" = "$image_before" ]
    echo "  PASS: real Docker transaction $mode"
done
echo 'PASS: real-Docker container upgrade and rollback (4/4 scenarios)'
