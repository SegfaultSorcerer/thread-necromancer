#!/usr/bin/env bash
# check-prerequisites.sh — Verify JVM diagnostic tools are available
# Part of thread-necromancer: "Raising insights from dead threads"

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass=0
warn=0
fail=0

check_command() {
    local cmd="$1"
    local required="$2"
    local description="$3"

    if command -v "$cmd" &>/dev/null; then
        local location
        location=$(command -v "$cmd")
        printf "${GREEN}[OK]${NC}    %-12s %s (%s)\n" "$cmd" "$description" "$location"
        pass=$((pass + 1))
    elif [ "$required" = "required" ]; then
        printf "${RED}[FAIL]${NC}  %-12s %s — REQUIRED but not found\n" "$cmd" "$description"
        fail=$((fail + 1))
    else
        printf "${YELLOW}[WARN]${NC}  %-12s %s — optional, not found\n" "$cmd" "$description"
        warn=$((warn + 1))
    fi
}

check_java_version() {
    if command -v java &>/dev/null; then
        local version
        version=$(java -version 2>&1 | head -1 | sed 's/.*"\(.*\)".*/\1/')
        local major
        major=$(echo "$version" | cut -d. -f1)
        if [ "$major" -ge 11 ] 2>/dev/null; then
            printf "${GREEN}[OK]${NC}    Java version: %s (>= 11 required)\n" "$version"
        else
            printf "${RED}[FAIL]${NC}  Java version: %s (>= 11 required)\n" "$version"
            fail=$((fail + 1))
        fi
    fi
}

check_java_home() {
    if [ -n "${JAVA_HOME:-}" ]; then
        printf "${GREEN}[OK]${NC}    JAVA_HOME:    %s\n" "$JAVA_HOME"
        if [ -x "${JAVA_HOME}/bin/jcmd" ] && ! command -v jcmd &>/dev/null; then
            printf "${YELLOW}[HINT]${NC}  jcmd found at %s/bin/jcmd but not on PATH\n" "$JAVA_HOME"
            printf "        Add to PATH: export PATH=\"\$JAVA_HOME/bin:\$PATH\"\n"
        fi
    else
        printf "${YELLOW}[WARN]${NC}  JAVA_HOME not set. JDK tools may not be on PATH.\n"
        warn=$((warn + 1))
    fi
}

echo "thread-necromancer — prerequisite check"
echo "========================================"
echo ""

echo "--- Required ---"
check_command "java" "required" "Java runtime"
check_java_version

echo ""
echo "--- JDK Diagnostic Tools ---"
check_command "jcmd" "optional" "JVM diagnostic command (preferred)"
check_command "jstack" "optional" "JVM stack trace tool (fallback)"
check_command "jps" "optional" "JVM process listing"

echo ""
echo "--- Environment ---"
check_java_home

echo ""
echo "--- Shell Tools ---"
check_command "awk" "required" "Text processing"
check_command "sed" "required" "Stream editing"
check_command "grep" "required" "Pattern matching"
check_command "sort" "required" "Sorting"

echo ""
echo "========================================"
printf "Results: ${GREEN}%d passed${NC}, ${YELLOW}%d warnings${NC}, ${RED}%d failed${NC}\n" "$pass" "$warn" "$fail"

if [ "$fail" -gt 0 ]; then
    echo ""
    echo "Some required prerequisites are missing. Please install them before using thread-necromancer."
    exit 1
fi

if ! command -v jcmd &>/dev/null && ! command -v jstack &>/dev/null; then
    echo ""
    printf "${YELLOW}WARNING:${NC} Neither jcmd nor jstack found.\n"
    echo "Thread dump capture requires at least one of these tools."
    echo "Install a full JDK (not just JRE) to get them."
    exit 1
fi

echo ""
echo "All prerequisites met. thread-necromancer is ready."
exit 0
