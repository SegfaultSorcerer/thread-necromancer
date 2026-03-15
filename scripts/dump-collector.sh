#!/usr/bin/env bash
# dump-collector.sh — Discover JVM processes and capture thread dumps
# Part of thread-necromancer: "Raising insights from dead threads"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_OUTPUT_DIR=".thread-necromancer/dumps"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat <<'EOF'
Usage: dump-collector.sh <command> [options]

Commands:
  list                              List running JVM processes
  capture <PID> [output-dir]        Capture a single thread dump
  watch <PID> [count] [interval] [output-dir]
                                    Capture multiple dumps over time
  deadlock <PID>                    Check for deadlocks only

Options:
  output-dir    Directory for dump files (default: .thread-necromancer/dumps/)
  count         Number of dumps for watch mode (default: 3)
  interval      Seconds between dumps in watch mode (default: 5)

Examples:
  dump-collector.sh list
  dump-collector.sh capture 12345
  dump-collector.sh watch 12345 5 3
  dump-collector.sh deadlock 12345
EOF
}

# --- JVM Process Discovery ---

list_processes() {
    echo "PID       MAIN_CLASS                                    UPTIME      ARGS"
    echo "--------- --------------------------------------------- ----------- ----"

    if command -v jcmd &>/dev/null; then
        list_via_jcmd
    elif command -v jps &>/dev/null; then
        list_via_jps
    else
        printf "${RED}Error:${NC} Neither jcmd nor jps found. Cannot list JVM processes.\n" >&2
        printf "Install a full JDK or ensure JAVA_HOME/bin is on PATH.\n" >&2
        exit 1
    fi
}

list_via_jcmd() {
    # jcmd without args lists JVM processes: <PID> <main-class>
    jcmd 2>/dev/null | grep -v "^$" | while IFS= read -r line; do
        local pid main_class uptime args
        pid=$(echo "$line" | awk '{print $1}')
        main_class=$(echo "$line" | awk '{print $2}')

        # Skip jcmd itself
        [ "$main_class" = "jdk.jcmd/sun.tools.jcmd.JCmd" ] && continue
        [ "$main_class" = "sun.tools.jcmd.JCmd" ] && continue

        # Try to get uptime
        uptime=$(jcmd "$pid" VM.uptime 2>/dev/null | grep -oE '[0-9.]+ s' | head -1 || echo "N/A")
        if [ "$uptime" != "N/A" ]; then
            local secs
            secs=$(echo "$uptime" | grep -oE '[0-9]+' | head -1)
            uptime=$(format_uptime "$secs")
        fi

        # Try to get command line args
        args=$(jcmd "$pid" VM.command_line 2>/dev/null | grep -v "^[0-9]" | head -1 || echo "")
        args="${args#*: }"

        # Truncate main class for display
        if [ ${#main_class} -gt 45 ]; then
            main_class="${main_class:0:42}..."
        fi

        printf "%-9s %-45s %-11s %s\n" "$pid" "$main_class" "$uptime" "$args"
    done
}

list_via_jps() {
    jps -l 2>/dev/null | grep -v "^$" | while IFS= read -r line; do
        local pid main_class
        pid=$(echo "$line" | awk '{print $1}')
        main_class=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ //')

        # Skip jps itself
        [ "$main_class" = "jdk.jcmd/sun.tools.jps.Jps" ] && continue
        [ "$main_class" = "sun.tools.jps.Jps" ] && continue

        if [ ${#main_class} -gt 45 ]; then
            main_class="${main_class:0:42}..."
        fi

        printf "%-9s %-45s %-11s %s\n" "$pid" "$main_class" "N/A" ""
    done
}

format_uptime() {
    local total_secs=$1
    local hours=$((total_secs / 3600))
    local mins=$(((total_secs % 3600) / 60))
    printf "%dh %02dm" "$hours" "$mins"
}

# --- Thread Dump Capture ---

validate_pid() {
    local pid="$1"

    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        printf "${RED}Error:${NC} '%s' is not a valid PID.\n" "$pid" >&2
        exit 1
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
        printf "${RED}Error:${NC} Process %s not found or not accessible.\n" "$pid" >&2
        printf "Run '${0##*/} list' to see available JVM processes.\n" >&2
        exit 1
    fi
}

ensure_output_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        printf "${GREEN}Created${NC} output directory: %s\n" "$dir" >&2
    fi
}

capture_dump() {
    local pid="$1"
    local output_dir="${2:-$DEFAULT_OUTPUT_DIR}"
    local suffix="${3:-}"

    validate_pid "$pid"
    ensure_output_dir "$output_dir"

    local timestamp
    timestamp=$(date +"%Y%m%d-%H%M%S")
    local filename="thread-dump-${pid}-${timestamp}${suffix}.txt"
    local filepath="${output_dir}/${filename}"

    # Capture JVM version info as header
    {
        echo "=== THREAD DUMP ==="
        echo "captured_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        echo "pid: ${pid}"

        # Try to get JVM version
        if command -v jcmd &>/dev/null; then
            local version
            version=$(jcmd "$pid" VM.version 2>/dev/null | grep -v "^${pid}:" || echo "")
            if [ -n "$version" ]; then
                echo "jvm_version: $(echo "$version" | head -1)"
            fi
        fi
        echo "==="
        echo ""
    } > "$filepath"

    # Capture thread dump using best available method
    if command -v jcmd &>/dev/null; then
        capture_via_jcmd "$pid" "$filepath"
    elif command -v jstack &>/dev/null; then
        capture_via_jstack "$pid" "$filepath"
    else
        printf "${RED}Error:${NC} Neither jcmd nor jstack available.\n" >&2
        rm -f "$filepath"
        exit 1
    fi

    printf "${GREEN}Captured${NC} thread dump: %s\n" "$filepath" >&2
    echo "$filepath"
}

capture_via_jcmd() {
    local pid="$1"
    local filepath="$2"

    if ! jcmd "$pid" Thread.print -l >> "$filepath" 2>/dev/null; then
        printf "${YELLOW}Warning:${NC} jcmd failed, trying jstack as fallback...\n" >&2
        if command -v jstack &>/dev/null; then
            capture_via_jstack "$pid" "$filepath"
        else
            printf "${RED}Error:${NC} Failed to capture thread dump for PID %s.\n" "$pid" >&2
            printf "Possible causes:\n" >&2
            printf "  - Process is not a JVM\n" >&2
            printf "  - Insufficient permissions (try with sudo)\n" >&2
            printf "  - JVM too old (< JDK 7)\n" >&2
            rm -f "$filepath"
            exit 1
        fi
    fi
}

capture_via_jstack() {
    local pid="$1"
    local filepath="$2"

    if ! jstack -l "$pid" >> "$filepath" 2>/dev/null; then
        printf "${RED}Error:${NC} jstack failed for PID %s.\n" "$pid" >&2
        printf "Possible causes:\n" >&2
        printf "  - Process is not a JVM\n" >&2
        printf "  - Insufficient permissions (try with sudo)\n" >&2
        printf "  - Process has exited\n" >&2
        rm -f "$filepath"
        exit 1
    fi
}

# --- Watch Mode (Multiple Dumps) ---

watch_process() {
    local pid="$1"
    local count="${2:-3}"
    local interval="${3:-5}"
    local output_dir="${4:-$DEFAULT_OUTPUT_DIR}"

    validate_pid "$pid"

    printf "Capturing %d thread dumps at %ds intervals for PID %s...\n" "$count" "$interval" "$pid" >&2

    local files=()
    for i in $(seq 1 "$count"); do
        printf "\n--- Dump %d/%d ---\n" "$i" "$count" >&2
        local file
        file=$(capture_dump "$pid" "$output_dir" "-${i}")
        files+=("$file")

        if [ "$i" -lt "$count" ]; then
            printf "Waiting %ds...\n" "$interval" >&2
            sleep "$interval"
        fi
    done

    printf "\n${GREEN}Done.${NC} Captured %d dumps:\n" "$count" >&2
    for f in "${files[@]}"; do
        echo "$f"
    done
}

# --- Deadlock Detection ---

check_deadlock() {
    local pid="$1"
    validate_pid "$pid"

    printf "Checking for deadlocks in PID %s...\n" "$pid" >&2

    local output=""
    if command -v jcmd &>/dev/null; then
        output=$(jcmd "$pid" Thread.print -l 2>/dev/null || true)
    elif command -v jstack &>/dev/null; then
        output=$(jstack -l "$pid" 2>/dev/null || true)
    else
        printf "${RED}Error:${NC} Neither jcmd nor jstack available.\n" >&2
        exit 1
    fi

    if [ -z "$output" ]; then
        printf "${RED}Error:${NC} Could not capture thread info for PID %s.\n" "$pid" >&2
        exit 1
    fi

    # Extract deadlock section
    local deadlock_info
    deadlock_info=$(echo "$output" | sed -n '/Found.*deadlock/,/^$/p')

    if [ -n "$deadlock_info" ]; then
        printf "${RED}DEADLOCK DETECTED${NC}\n\n"
        echo "$deadlock_info"
    else
        printf "${GREEN}No deadlocks detected.${NC}\n"
    fi
}

# --- Main ---

if [ $# -lt 1 ]; then
    usage
    exit 1
fi

command="$1"
shift

case "$command" in
    list)
        list_processes
        ;;
    capture)
        if [ $# -lt 1 ]; then
            printf "${RED}Error:${NC} capture requires a PID.\n" >&2
            echo "Usage: ${0##*/} capture <PID> [output-dir]" >&2
            exit 1
        fi
        capture_dump "$@"
        ;;
    watch)
        if [ $# -lt 1 ]; then
            printf "${RED}Error:${NC} watch requires a PID.\n" >&2
            echo "Usage: ${0##*/} watch <PID> [count] [interval] [output-dir]" >&2
            exit 1
        fi
        watch_process "$@"
        ;;
    deadlock)
        if [ $# -lt 1 ]; then
            printf "${RED}Error:${NC} deadlock requires a PID.\n" >&2
            echo "Usage: ${0##*/} deadlock <PID>" >&2
            exit 1
        fi
        check_deadlock "$1"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        printf "${RED}Error:${NC} Unknown command '%s'\n" "$command" >&2
        usage
        exit 1
        ;;
esac
