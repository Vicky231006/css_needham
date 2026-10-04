#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python}"
DEMO_TIMEOUT="${DEMO_TIMEOUT:-30}"
RUN_DIR=''
KDC_PID=''
BOB_PID=''
ALICE_PID=''
WATCHDOG_PID=''

if [[ ! "$DEMO_TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
    printf 'DEMO_TIMEOUT must be a positive integer number of seconds.\n' >&2
    exit 2
fi

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    printf 'Python executable not found: %s (set PYTHON_BIN to its path).\n' "$PYTHON_BIN" >&2
    exit 2
fi

cleanup() {
    for pid in "$ALICE_PID" "$BOB_PID" "$KDC_PID"; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    for pid in "$ALICE_PID" "$BOB_PID" "$KDC_PID"; do
        if [[ -n "$pid" ]]; then
            wait "$pid" 2>/dev/null || true
        fi
    done
    if [[ -n "$WATCHDOG_PID" ]]; then
        kill "$WATCHDOG_PID" 2>/dev/null || true
        wait "$WATCHDOG_PID" 2>/dev/null || true
    fi
    if [[ -n "$RUN_DIR" ]]; then
        rm -rf -- "$RUN_DIR"
    fi
}
trap cleanup EXIT

wait_for_output() {
    local pid="$1"
    local log_file="$2"
    local expected="$3"
    local attempt

    for ((attempt = 0; attempt < 100; attempt++)); do
        if grep -Fq -- "$expected" "$log_file"; then
            return 0
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            printf 'A Python process exited before becoming ready:\n' >&2
            cat "$log_file" >&2
            return 1
        fi
        sleep 0.1
    done

    printf 'Timed out waiting for "%s".\n' "$expected" >&2
    cat "$log_file" >&2
    return 1
}

show_log() {
    printf '\n===== %s: actual Python process output =====\n' "$1"
    cat "$2"
}

cd "$SCRIPT_DIR"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/needham-demo.XXXXXX")"

printf 'Needham-Schroeder end-to-end demo\n'
printf 'Running server.py, clientB.py, and client.py with real sockets and the project encryption code.\n'
printf 'The demo supplies scripted menu/chat input so it can run unattended.\n'

"$PYTHON_BIN" -u server.py >"$RUN_DIR/kdc.log" 2>&1 &
KDC_PID=$!
wait_for_output "$KDC_PID" "$RUN_DIR/kdc.log" 'Socket now listening...'

printf 'wait\nHi Alice!\nquit\n' | "$PYTHON_BIN" -u clientB.py >"$RUN_DIR/bob.log" 2>&1 &
BOB_PID=$!
wait_for_output "$BOB_PID" "$RUN_DIR/bob.log" 'Waiting for connection.....'

printf 'connect|00000001\nHello Bob!\nq\nquit\n' | "$PYTHON_BIN" -u client.py >"$RUN_DIR/alice.log" 2>&1 &
ALICE_PID=$!

(
    sleep "$DEMO_TIMEOUT"
    if kill -0 "$ALICE_PID" 2>/dev/null; then
        printf 'Timed out after %s seconds while waiting for the clients to finish.\n' \
            "$DEMO_TIMEOUT" >"$RUN_DIR/timeout"
        kill "$ALICE_PID" 2>/dev/null || true
    fi
) &
WATCHDOG_PID=$!

if wait "$ALICE_PID"; then
    ALICE_PID=''
else
    status=$?
    if [[ -f "$RUN_DIR/timeout" ]]; then
        cat "$RUN_DIR/timeout" >&2
    fi
    show_log Alice "$RUN_DIR/alice.log" >&2
    show_log Bob "$RUN_DIR/bob.log" >&2
    exit "$status"
fi

kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true
WATCHDOG_PID=''

if wait "$BOB_PID"; then
    BOB_PID=''
else
    status=$?
    show_log Bob "$RUN_DIR/bob.log" >&2
    exit "$status"
fi

show_log KDC "$RUN_DIR/kdc.log"
show_log Bob "$RUN_DIR/bob.log"
show_log Alice "$RUN_DIR/alice.log"
printf '\nDemo finished: all three Python processes ran and exited successfully.\n'
