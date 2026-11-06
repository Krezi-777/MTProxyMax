#!/usr/bin/env bash
# REAL manager launch and config generation on an ephemeral GitHub-hosted runner.
# No production configuration, Docker remote context, or deployment permitted.
set -eo pipefail
cd "$(dirname "$0")/../.."
test -n "${GITHUB_ACTIONS:-}" || { echo 'GitHub Actions only'; exit 1; }
test "${DOCKER_HOST:-}" = "" || { echo 'Remote Docker hosts not permitted'; exit 1; }
test "$(docker context show)" = default || { echo 'Unexpected Docker context'; exit 1; }
test "$(id -u)" -ne 0 || { echo 'Run as ordinary GitHub runner user'; exit 1; }
docker info >/dev/null

repo="$PWD"
base="$RUNNER_TEMP/mtproxy-real-manager-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
CONFIG_DIR="$base/config"
INSTALL_DIR="$base/install"
CONTAINER_NAME="mtproxy-real-manager-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
SECONDARY_CONTAINER="mtproxymax-19082"
INSTANCES_FILE="$base/instances.conf"
haproxy_name="$CONTAINER_NAME-haproxy"
DOCKER_IMAGE_BASE=mtproxymax-telemt
TELEMT_MIN_VERSION=3.5.16
TELEMT_COMMIT=84e5b82
PROXY_PORT=19080
PROXY_METRICS_PORT=19190
PROXY_DOMAIN=example.org
PROXY_BIND_IPV4=127.0.0.1
PROXY_BIND_IPV6=::1
PROXY_PROTOCOL=false
PROXY_PROTOCOL_TRUSTED_CIDRS=""
PROXY_CPUS=""
PROXY_MEMORY=""
CLIENT_MSS=""
MASKING_ENABLED=false
MASKING_HOST=""
MASKING_PORT=443
CUSTOM_IP=""
AD_TAG=""
COVER_SHIELD_ENABLED=false
FAKE_CERT_LEN=2048
STEALTH_PRESET=normal
QUOTA_ENFORCEMENT_MODE=manager
UNKNOWN_SNI_ACTION=drop
declare -a SECRETS_LABELS=(smoke_test)
declare -a SECRETS_KEYS=(0123456789abcdef0123456789abcdef)
declare -a SECRETS_ENABLED=(true)
declare -a SECRETS_MAX_CONNS=(0) SECRETS_MAX_IPS=(0) SECRETS_QUOTA=(0)
declare -a SECRETS_EXPIRES=(0) SECRETS_AD_TAGS=("")
declare -a UPSTREAM_NAMES=() UPSTREAM_ENABLED=() UPSTREAM_TYPES=() UPSTREAM_WEIGHTS=()
declare -a UPSTREAM_ADDRS=() UPSTREAM_USERS=() UPSTREAM_PASSES=() UPSTREAM_IFACES=()
BOLD="" DIM="" NC="" CYAN=""
mkdir -p "$CONFIG_DIR" "$INSTALL_DIR"
printf '3.5.16-84e5b82\n' > "$INSTALL_DIR/.telemt_version"

cleanup() {
    command docker rm -f "$CONTAINER_NAME" "$haproxy_name" "$SECONDARY_CONTAINER" >/dev/null 2>&1 || true
    local name
    while IFS= read -r name; do
        case "$name" in
            "$CONTAINER_NAME-rollback-"*|"$SECONDARY_CONTAINER-rollback-"*) command docker rm -f "$name" >/dev/null 2>&1 || true ;;
        esac
    done < <(command docker ps -a --format '{{.Names}}' || true)
    rm -rf "$base"
}
trap cleanup EXIT

# Extract exact production functions; all privileged host-dependent helpers are
# stubbed. The real Docker launch flags, real image selection, and real TOML
# generator remain intact.
fn="$base/production-functions.sh"
for item in 'get_telemt_version() {' 'get_docker_image() {' \
            'generate_telemt_config() {' 'run_proxy_container() {' \
            '_start_all_instances() {' '_instance_container_running() {' 'upgrade_proxy_container_with_rollback() {' \
            'upgrade_all_proxy_instances_with_rollback() {'; do
    awk -v header="$item" '
        $0==header {active=1}
        active {print}
        active && $0=="}" {exit}
    ' "$repo/mtproxymax.sh" >> "$fn"
done
source "$fn"
for required in get_telemt_version get_docker_image generate_telemt_config run_proxy_container upgrade_proxy_container_with_rollback; do
    declare -f "$required" >/dev/null || { echo "Missing real function $required" >&2; exit 1; }
done
_mktemp() { mktemp "$1/.mtproxymax.XXXXXX"; }
get_enabled_labels_quoted() { printf '"smoke_test"'; }
_emit_tunings_for_section() { :; }
build_telemt_image() { command docker image inspect "$DOCKER_IMAGE_BASE:$TELEMT_MIN_VERSION-$TELEMT_COMMIT" >/dev/null; }
log_info() { echo "INFO: $*"; }
log_warn() { echo "WARN: $*" >&2; }
log_error() { echo "ERROR: $*" >&2; }
log_success() { echo "INFO: $*"; }
get_public_ip() { :; }
is_proxy_running() { [ "$(command docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || true)" = true ]; }
is_port_available() { :; }
traffic_tracking_setup() { :; }
geoblock_reapply_all() { :; }
bans_reapply() { :; }
maintenance_reapply() { :; }
_startup_warnings() { :; }
telegram_notify_proxy_started() { :; }
flush_traffic_to_disk() { :; }
load_instances() {
    INSTANCE_PORTS=(19082)
    INSTANCE_METRICS_PORTS=(19192)
    INSTANCE_ENABLED=(true)
    INSTANCE_LABELS=(isolated-secondary)
}
apply_firewall_rules() { :; }
speed_limit_apply() { :; }
# The actual run_proxy_container uses docker run. Fault injection intercepts only
# a launch command; no systemctl restart or daemon recovery path is triggered.
docker() {
    if [ "${FAIL_DOCKER_RUN:-0}" = 1 ] && [ "$1" = run ]; then
        echo "intentional isolated launch failure" >&2
        return 51
    fi
    command docker "$@"
}

command docker tag telemt:fullstack-test "$DOCKER_IMAGE_BASE:$TELEMT_MIN_VERSION-$TELEMT_COMMIT"
command docker pull haproxy:3.1-alpine >/dev/null
cat > "$base/haproxy.cfg" <<'EOF'
global
    maxconn 100
defaults
    mode tcp
    timeout connect 2s
    timeout client 10s
    timeout server 10s
frontend incoming
    bind 127.0.0.1:19081
    default_backend telemt
backend telemt
    option tcp-check
    server engine 127.0.0.1:19080 check inter 1s fall 2 rise 2
listen stats
    bind 127.0.0.1:18404
    mode http
    stats enable
    stats uri /stats
EOF
command docker run -d --name "$haproxy_name" --network host \
    -v "$base/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro" \
    haproxy:3.1-alpine >/dev/null

health() {
    if python3 - <<'PY'
import csv,io,socket,time,urllib.request
for attempt in range(25):
    try:
        with socket.create_connection(('127.0.0.1',19081),timeout=2): pass
        response=urllib.request.urlopen('http://127.0.0.1:18404/stats;csv',timeout=2).read().decode()
        rows=list(csv.DictReader(io.StringIO(response.lstrip('# '))))
        assert any(row.get('pxname')=='telemt' and row.get('svname')=='engine' and row.get('status')=='UP' for row in rows)
        break
    except Exception:
        time.sleep(1)
else:
    raise SystemExit('HAProxy backend not healthy')
PY
    then
        return 0
    fi
    echo 'DIAGNOSTICS: real manager network health failed' >&2
    command docker ps -a --filter "name=$CONTAINER_NAME" >&2 || true
    command docker logs --tail 80 "$CONTAINER_NAME" >&2 || true
    command docker logs --tail 80 "$haproxy_name" >&2 || true
    command ss -ltnp 2>&1 | grep -E '19080|19081|18404|State' >&2 || true
    curl --max-time 5 --silent --show-error 'http://127.0.0.1:18404/stats;csv' \
        | grep -E 'telemt,engine|# pxname' >&2 || true
    return 1
}
run_proxy_container
is_proxy_running
health
test "$(command docker inspect -f '{{.HostConfig.NetworkMode}}' "$CONTAINER_NAME")" = host
test "$(command docker inspect -f '{{.Config.Image}}' "$CONTAINER_NAME")" = "$DOCKER_IMAGE_BASE:$TELEMT_MIN_VERSION-$TELEMT_COMMIT"
old_id="$(command docker inspect -f '{{.Id}}' "$CONTAINER_NAME")"
old_sha="$(sha256sum "$CONFIG_DIR/config.toml" | cut -d' ' -f1)"
echo '  PASS: genuine manager run_proxy_container and generate_telemt_config with host networking'

# Check the real multi-instance start routine. Existing instances must survive
# primary engine updates; version consistency is a separate release gate.
printf '19082|19192|true|isolated-secondary\n' > "$INSTANCES_FILE"
_start_all_instances
sleep 3
test "$(command docker inspect -f '{{.State.Running}}' "$SECONDARY_CONTAINER")" = true
secondary_id="$(command docker inspect -f '{{.Id}}' "$SECONDARY_CONTAINER")"
if python3 - <<'PY'
import socket,time
for attempt in range(20):
    try:
        with socket.create_connection(('127.0.0.1',19082),timeout=2): pass
        break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit('secondary instance port 19082 not ready')
PY
then
    echo '  PASS: real secondary instance starts with independent config and port'
else
    echo 'DIAGNOSTICS: secondary instance launch failed' >&2
    command docker ps -a --filter "name=$SECONDARY_CONTAINER" >&2 || true
    command docker logs --tail 90 "$SECONDARY_CONTAINER" >&2 || true
    command ss -ltnp 2>&1 | grep -E '19082|19192|State' >&2 || true
    return 1
fi

FAIL_DOCKER_RUN=1
if upgrade_proxy_container_with_rollback; then
    echo 'FAIL: broken replacement unexpectedly accepted' >&2; exit 1
fi
FAIL_DOCKER_RUN=0
is_proxy_running
test "$(command docker inspect -f '{{.Id}}' "$CONTAINER_NAME")" = "$old_id"
test "$(sha256sum "$CONFIG_DIR/config.toml" | cut -d' ' -f1)" = "$old_sha"
health
test "$(command docker inspect -f '{{.Id}}' "$SECONDARY_CONTAINER")" = "$secondary_id"
echo '  PASS: genuine launch failure restored original container and config with HAProxy UP'

upgrade_proxy_container_with_rollback
is_proxy_running
new_id="$(command docker inspect -f '{{.Id}}' "$CONTAINER_NAME")"
test "$new_id" != "$old_id"
backup="$(command docker ps -a --format '{{.Names}}' | grep -E "^$CONTAINER_NAME-rollback-" | head -n1)"
test -n "$backup"
test "$(command docker inspect -f '{{.Id}}' "$backup")" = "$old_id"
health
test "$(command docker inspect -f '{{.Id}}' "$SECONDARY_CONTAINER")" = "$secondary_id"
test "$(command docker inspect -f '{{.State.Running}}' "$SECONDARY_CONTAINER")" = true
echo '  PASS: genuine manager upgrade retained old container and HAProxy remained UP'
echo '  PASS: active secondary instance preserved across primary restart (no secondary upgrade performed)'
echo 'PASS: primary production launch and multi-instance continuity on isolated GitHub runner (5/5)'

# Group upgrade: the original secondary must also be replaced and retained.
before_group_secondary=$(command docker inspect -f '{{.Id}}' "$SECONDARY_CONTAINER")
upgrade_all_proxy_instances_with_rollback
health
after_group_secondary=$(command docker inspect -f '{{.Id}}' "$SECONDARY_CONTAINER")
test "$before_group_secondary" != "$after_group_secondary"
test "$(command docker inspect -f '{{.State.Running}}' "$SECONDARY_CONTAINER")" = true
test "$(command docker inspect -f '{{.Id}}' "$CONTAINER_NAME")" != "$new_id"
python3 - <<'PY'
import socket
for port in (19080, 19082):
    with socket.create_connection(('127.0.0.1', port), timeout=3):
        pass
PY
echo '  PASS: both upgraded Telemt listening ports accept connections'
echo '  PASS: group upgrade replaced both running instances'

# Inject a failure ONLY on the secondary Docker launch, after the primary
# replacement succeeds. Both original container IDs must be restored.
command docker update --restart=always "$CONTAINER_NAME" "$SECONDARY_CONTAINER" >/dev/null
before_fail_primary=$(command docker inspect -f '{{.Id}}' "$CONTAINER_NAME")
before_fail_secondary=$(command docker inspect -f '{{.Id}}' "$SECONDARY_CONTAINER")
before_fail_primary_config=$(sha256sum "$CONFIG_DIR/config.toml" | cut -d' ' -f1)
before_fail_secondary_config=$(sha256sum "$CONFIG_DIR/config-19082.toml" | cut -d' ' -f1)
docker() {
    if [ "$1" = run ] && [[ " $* " == *" --name $SECONDARY_CONTAINER "* ]]; then
        echo 'Injected secondary update failure' >&2
        return 51
    fi
    command docker "$@"
}
if upgrade_all_proxy_instances_with_rollback; then
    echo 'FAIL: group upgrade accepted failed secondary launch' >&2; exit 1
fi
unset -f docker
test "$(command docker inspect -f '{{.Id}}' "$CONTAINER_NAME")" = "$before_fail_primary"
test "$(command docker inspect -f '{{.Id}}' "$SECONDARY_CONTAINER")" = "$before_fail_secondary"
test "$(sha256sum "$CONFIG_DIR/config.toml" | cut -d' ' -f1)" = "$before_fail_primary_config"
test "$(sha256sum "$CONFIG_DIR/config-19082.toml" | cut -d' ' -f1)" = "$before_fail_secondary_config"
test "$(command docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER_NAME")" = always
test "$(command docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$SECONDARY_CONTAINER")" = always
python3 - <<'PY'
import socket
for port in (19080, 19082):
    with socket.create_connection(('127.0.0.1', port), timeout=3):
        pass
PY
health
echo '  PASS: failed secondary update preserves restart policies and both listening ports'
echo '  PASS: failed secondary update restores both original Docker IDs and configs'

# Fault inside the rollback itself: do not report success and retain the old
# immutable container plus snapshots for manual recovery.
before_partial_secondary=$(command docker inspect -f '{{.Id}}' "$SECONDARY_CONTAINER")
docker() {
    if [ "$1" = run ] && [[ " $* " == *" --name $SECONDARY_CONTAINER "* ]]; then
        return 51
    fi
    if [ "$1" = rename ] && [[ "$2" == "$SECONDARY_CONTAINER-rollback-"* ]] &&
       [ "$3" = "$SECONDARY_CONTAINER" ]; then
        echo 'Injected secondary rollback rename failure' >&2
        return 52
    fi
    command docker "$@"
}
if upgrade_all_proxy_instances_with_rollback >"$base/rollback-failure.log" 2>&1; then
    echo 'FAIL: incomplete rollback reported success' >&2; exit 1
fi
unset -f docker
grep -q 'Group rollback incomplete' "$base/rollback-failure.log"
test "$(command docker inspect -f '{{.Id}}' "$before_partial_secondary")" = "$before_partial_secondary"
test "$(command docker inspect -f '{{.Id}}' "$CONTAINER_NAME")" = "$before_fail_primary"
compgen -G "$CONFIG_DIR/.group-rollback.*" >/dev/null
echo '  PASS: rollback failure is reported; old Docker ID and snapshots retained'


