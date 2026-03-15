#!/usr/bin/env bash
# on-test-hang.sh — Capture thread dump when test JVM appears hung
# Triggered by PostToolUse hook when test command output contains timeout indicators

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR="${SCRIPT_DIR}/../dump-collector.sh"
PARSER="${SCRIPT_DIR}/../dump-parser.sh"
OUTPUT_DIR=".thread-necromancer/dumps/test-hangs"
FLAG_FILE=".thread-necromancer/dump-on-test-hang.enabled"

# Check opt-in flag
if [ ! -f "$FLAG_FILE" ]; then
    exit 0
fi

# Find test JVM processes (surefire, failsafe, gradle test worker)
find_test_jvms() {
    local pids=()

    if command -v jcmd &>/dev/null; then
        while IFS= read -r line; do
            local pid main_class
            pid=$(echo "$line" | awk '{print $1}')
            main_class=$(echo "$line" | awk '{print $2}')

            case "$main_class" in
                *surefire*|*failsafe*|*ForkedBooter*|*GradleWorkerMain*|*gradle*worker*)
                    pids+=("$pid")
                    ;;
            esac
        done < <(jcmd 2>/dev/null || true)
    elif command -v jps &>/dev/null; then
        while IFS= read -r line; do
            local pid main_class
            pid=$(echo "$line" | awk '{print $1}')
            main_class=$(echo "$line" | awk '{$1=""; print $0}')

            case "$main_class" in
                *surefire*|*failsafe*|*ForkedBooter*|*GradleWorkerMain*|*gradle*worker*)
                    pids+=("$pid")
                    ;;
            esac
        done < <(jps -l 2>/dev/null || true)
    fi

    echo "${pids[@]}"
}

pids=$(find_test_jvms)

if [ -z "$pids" ]; then
    echo "[thread-necromancer] No test JVM processes found to dump." >&2
    exit 0
fi

mkdir -p "$OUTPUT_DIR"

for pid in $pids; do
    echo "[thread-necromancer] Capturing thread dump for hung test JVM (PID: $pid)..." >&2
    dump_file=$("$COLLECTOR" capture "$pid" "$OUTPUT_DIR" 2>/dev/null || true)

    if [ -n "$dump_file" ] && [ -f "$dump_file" ]; then
        echo "[thread-necromancer] Thread dump saved: $dump_file" >&2
        echo "[thread-necromancer] Parsing dump..." >&2
        "$PARSER" "$dump_file" 2>/dev/null || true
    else
        echo "[thread-necromancer] Failed to capture dump for PID $pid" >&2
    fi
done
