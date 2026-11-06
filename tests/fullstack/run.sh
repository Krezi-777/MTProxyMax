#!/usr/bin/env bash
# Test the pinned Telemt image with HAProxy and MTProxyMax's actual upgrade helper.
# Ephemeral GitHub runner ONLY. No production secrets or host-network containers.
set -euo pipefail
cd "$(dirname "$0")/../.."
export COMPOSE_PROJECT_NAME="mtproxy-fullstack-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
export PROXY_CONTAINER="${COMPOSE_PROJECT_NAME}-telemt"
export HAPROXY_CONTAINER="${COMPOSE_PROJECT_NAME}-haproxy"
export TEST_NETWORK="${COMPOSE_PROJECT_NAME}-internal"
stack_dir="$PWD/tests/fullstack"
config_dir="$stack_dir/config"
compose_file="$stack_dir/compose.yml"
backup_name=""
expected_hash=""
cleanup() {
    local name
    # Remove both new and renamed rollback containers first, then Compose resources.
    while IFS= read -r name; do
        case "$name" in
            "$COMPOSE_PROJECT_NAME"*) command docker rm -f "$name" >/dev/null 2>&1 || true ;;
        esac
    done < <(command docker ps -a --format '{{.Names}}' 2>/dev/null || true)
    command docker compose -f "$compose_file" down --remove-orphans >/dev/null 2>&1 || true
    command docker network rm "$TEST_NETWORK" >/dev/null 2>&1 || true
    rm -rf "$config_dir"
}
trap cleanup EXIT

mkdir -p "$config_dir"
cat > "$config_dir/config.toml" <<'TOML'
[general]
use_middle_proxy = false
log_level = "normal"

[general.modes]
classic = true
secure = false
tls = false

[server]
port = 18080

[[server.listeners]]
ip = "0.0.0.0"

[censorship]
tls_domain = "example.org"
mask = false
tls_emulation = false

[access.users]
smoke_test = "0123456789abcdef0123456789abcdef"
TOML
expected_hash="$(sha256sum "$config_dir/config.toml" | cut -d' ' -f1)"
command docker compose -f "$compose_file" config --quiet
command docker compose -f "$compose_file" up -d --no-build

# Both connection and HAProxy's own backend health status must be good.
assert_stack_healthy() {
    local tries=30
    for ((i=1; i<=tries; i++)); do
        if python3 - "$HAPROXY_CONTAINER" <<'PY'
import csv, io, subprocess, sys
name = sys.argv[1]
try:
    # With an internal Docker network, host-published ports are not a valid
    # reachability test. Probe HAProxy from inside its own network namespace.
    subprocess.run(["docker", "exec", name, "sh", "-c",
                    "nc -z -w 2 127.0.0.1 18081"],
                   check=True, capture_output=True, text=True, timeout=5)
    result = subprocess.run(
        ["docker", "exec", name, "wget", "-qO-", "http://127.0.0.1:8404/stats;csv"],
        check=True, capture_output=True, text=True, timeout=5)
    rows = list(csv.DictReader(io.StringIO(result.stdout.lstrip("# "))))
    matches = [row for row in rows if row.get("pxname") == "telemt_backend"
               and row.get("svname") == "telemt"]
    assert matches, "HAProxy backend entry missing in CSV"
    assert any(row.get("status") == "UP" for row in matches), (
        "HAProxy backend not UP: " + repr([row.get("status") for row in matches]))
except Exception as error:
    print(f"health probe: {type(error).__name__}: {error}", file=sys.stderr)
    raise SystemExit(1)
PY
        then
            return 0
        fi
        sleep 1
    done
    echo 'FAIL: HAProxy TCP listener/backend did not become healthy' >&2
    command docker logs --tail 50 "$HAPROXY_CONTAINER" >&2 || true
    command docker logs --tail 50 "$PROXY_CONTAINER" >&2 || true
    return 1
}
assert_config_unchanged() {
    test "$(sha256sum "$config_dir/config.toml" | cut -d' ' -f1)" = "$expected_hash"
}
assert_stack_healthy
assert_config_unchanged
echo '  PASS: pinned Telemt started and HAProxy reports healthy TCP backend'

# Exercise the real upgrade function from the manager. Only its side-effect
# helpers are replaced; the Docker lifecycle inside it uses the real daemon.
fn="$(mktemp)"
sed -n '/^upgrade_proxy_container_with_rollback() {$/,/^restart_proxy_container() {$/p' mtproxymax.sh | sed '$d' > "$fn"
source "$fn"
rm -f "$fn"
CONTAINER_NAME="$PROXY_CONTAINER"
log_info() { echo "INFO: $*"; }
log_warn() { echo "WARN: $*" >&2; }
log_error() { echo "ERROR: $*" >&2; }
flush_traffic_to_disk() { :; }
_start_all_instances() { :; }
apply_firewall_rules() { :; }
speed_limit_apply() { :; }
is_proxy_running() {
    test "$(command docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" = true
}
run_proxy_container() {
    if [ "${INJECT_FAILURE:-0}" = 1 ]; then
        command docker run -d --name "$CONTAINER_NAME" --network "$TEST_NETWORK" \
          --entrypoint /bin/does-not-exist telemt:fullstack-test >/dev/null 2>&1
        return $?
    fi
    # The actual MTProxyMax run_proxy_container uses --network host.
    # The test substitutes an internal bridge with the required DNS alias.
    command docker run -d --name "$CONTAINER_NAME" --network "$TEST_NETWORK" \
      --network-alias telemt --read-only --cap-drop ALL \
      -v "$config_dir:/etc/telemt:ro" --tmpfs /run/telemt:rw,size=4m,mode=1777 \
      -w /run/telemt telemt:fullstack-test /etc/telemt/config.toml >/dev/null
}

original_id="$(command docker inspect -f '{{.Id}}' "$CONTAINER_NAME")"
INJECT_FAILURE=1
if upgrade_proxy_container_with_rollback; then
    echo 'FAIL: manager accepted broken engine' >&2
    exit 1
fi
INJECT_FAILURE=0
test "$(command docker inspect -f '{{.Id}}' "$CONTAINER_NAME")" = "$original_id"
is_proxy_running
assert_stack_healthy
assert_config_unchanged
echo '  PASS: manager rollback preserved original Docker ID, config and HAProxy traffic'

# Now perform a successful protected replacement with the exact Telemt image.
upgrade_proxy_container_with_rollback
is_proxy_running
new_id="$(command docker inspect -f '{{.Id}}' "$CONTAINER_NAME")"
test "$new_id" != "$original_id"
backup_name="$(command docker ps -a --format '{{.Names}}' | grep -E "^$CONTAINER_NAME-rollback-" | head -n1)"
test -n "$backup_name"
test "$(command docker inspect -f '{{.Id}}' "$backup_name")" = "$original_id"
test "$(command docker inspect -f '{{.State.Running}}' "$backup_name")" = false
assert_stack_healthy
assert_config_unchanged
echo '  PASS: manager upgrade switched container while preserving old one and HAProxy routing'
echo 'PASS: Telemt + HAProxy + MTProxyMax full-stack integration (3/3)'
