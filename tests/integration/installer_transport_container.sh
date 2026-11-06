#!/usr/bin/env bash
# Disposable container validates the genuine installer; manager execution intercepted.
set -euo pipefail
test -n "${GITHUB_ACTIONS:-}" || { echo 'GitHub Actions only' >&2; exit 1; }
test -z "${DOCKER_HOST:-}" || { echo 'Remote Docker prohibited' >&2; exit 1; }
test "$(docker context show)" = default
test "$(id -u)" -ne 0 || { echo 'Run as non-root runner user' >&2; exit 1; }
docker run --rm --network bridge --tmpfs /tmp:rw,size=32m,mode=1777 \
  -v "$PWD/install.sh:/sandbox/install.sh:ro" \
  -e MTPROXYMAX_SOURCE_COMMIT="$GITHUB_SHA" \
  -e MTPROXYMAX_SOURCE_SHA256="aa527da3314d29ec9ed5e59ca09a1e0c96d1fd5db397c5f705c4831cce1abf7e" \
  ubuntu:24.04 /bin/bash -euc '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    apt-get install -y -qq curl ca-certificates coreutils >/dev/null
    # Exported shell function takes precedence over PATH lookup in the child
    # bash process. It intercepts the exact verified manager execution.
    bash() {
        if [ "$1" = "-n" ]; then
            /bin/bash "$@"
            return $?
        fi
        if [ "${2:-}" = "install" ]; then
            sha256sum "$1" | grep -q "^${MTPROXYMAX_SOURCE_SHA256} "
            echo "Manager execution intercepted after checksum validation"
            touch /tmp/install-verified
            return 0
        fi
        /bin/bash "$@"
    }
    export -f bash
    /bin/bash /sandbox/install.sh
    test -f /tmp/install-verified
    rm -f /tmp/install-verified
    if MTPROXYMAX_SOURCE_SHA256="$(printf "0%.0s" {1..64})" /bin/bash /sandbox/install.sh >/tmp/bad-hash.log 2>&1; then
        echo "FAIL: installer accepted deliberately wrong digest" >&2
        exit 1
    fi
    test ! -e /tmp/install-verified
    grep -q "checksum mismatch" /tmp/bad-hash.log
    echo "PASS: isolated root installer verified immutable download; incorrect hash rejected"
    echo "NOTE: full manager installation intentionally NOT executed"
  '
