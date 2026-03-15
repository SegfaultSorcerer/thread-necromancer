#!/usr/bin/env bash
# on-startup.sh — Capture baseline thread dump after Spring Boot startup
# Triggered by PostToolUse hook when Spring Boot startup message detected

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR="${SCRIPT_DIR}/../dump-collector.sh"
OUTPUT_DIR=".thread-necromancer/dumps/baselines"
FLAG_FILE=".thread-necromancer/startup-baseline.enabled"

# Check opt-in flag
if [ ! -f "$FLAG_FILE" ]; then
    exit 0
fi

# Find Spring Boot application processes
find_spring_boot_jvms() {
    local pids=()

    if command -v jcmd &>/dev/null; then
        while IFS= read -r line; do
            local pid main_class
            pid=$(echo "$line" | awk '{print $1}')
            main_class=$(echo "$line" | awk '{print $2}')

            # Skip JDK tools
            case "$main_class" in
                *jcmd*|*jps*|*jstack*|*surefire*|*failsafe*|*ForkedBooter*)
                    continue
                    ;;
            esac

            # Check if it's a Spring Boot app by looking for spring-related args
            local cmdline
            cmdline=$(jcmd "$pid" VM.command_line 2>/dev/null || true)
            if echo "$cmdline" | grep -qiE 'spring|boot' 2>/dev/null; then
                pids+=("$pid")
            fi
        done < <(jcmd 2>/dev/null || true)
    fi

    echo "${pids[@]}"
}

# Wait for application to fully initialize
echo "[thread-necromancer] Waiting 10s for application to stabilize..." >&2
sleep 10

pids=$(find_spring_boot_jvms)

if [ -z "$pids" ]; then
    echo "[thread-necromancer] No Spring Boot JVM found for baseline dump." >&2
    exit 0
fi

mkdir -p "$OUTPUT_DIR"

for pid in $pids; do
    echo "[thread-necromancer] Capturing startup baseline for PID $pid..." >&2
    dump_file=$("$COLLECTOR" capture "$pid" "$OUTPUT_DIR" 2>/dev/null || true)

    if [ -n "$dump_file" ] && [ -f "$dump_file" ]; then
        echo "[thread-necromancer] Baseline saved: $dump_file" >&2
        echo "[thread-necromancer] Use '/thread-analyze $dump_file' to analyze." >&2
    else
        echo "[thread-necromancer] Failed to capture baseline for PID $pid" >&2
    fi
done
