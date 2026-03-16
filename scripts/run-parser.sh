#!/usr/bin/env bash
# run-parser.sh — Find a suitable JDK (>= 11) and run DumpParser.java
# Part of thread-necromancer: "Raising insights from dead threads."

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/DumpParser.java"

if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: run-parser.sh <thread-dump-file>"
    echo ""
    echo "Finds a suitable JDK (>= 11) and runs DumpParser.java."
    echo "Searches: PATH, JAVA_HOME, ~/.jdks, /usr/lib/jvm, /usr/local/opt, SDKMAN, common install dirs."
    exit 1
fi

# Extract major version from java -version output
get_java_major_version() {
    local java_bin="$1"
    local version_output
    version_output=$("$java_bin" -version 2>&1 | head -1) || return 1
    # Handles both "1.8.0_xxx" (old) and "11.0.x" / "17.0.x" (new) formats
    local version
    version=$(echo "$version_output" | sed -E 's/.*"([^"]+)".*/\1/')
    local major
    major=$(echo "$version" | cut -d. -f1)
    # Java 8 reports as 1.8
    if [ "$major" = "1" ]; then
        major=$(echo "$version" | cut -d. -f2)
    fi
    echo "$major"
}

# Check if a java binary is suitable (>= 11)
is_suitable_java() {
    local java_bin="$1"
    [ -x "$java_bin" ] || return 1
    local major
    major=$(get_java_major_version "$java_bin" 2>/dev/null) || return 1
    [ "$major" -ge 11 ] 2>/dev/null || return 1
}

# Try to find a suitable java binary
find_java() {
    # 1. Check java on PATH
    if command -v java &>/dev/null; then
        local path_java
        path_java=$(command -v java)
        if is_suitable_java "$path_java"; then
            echo "$path_java"
            return 0
        fi
        echo "INFO: java on PATH is version $(get_java_major_version "$path_java") (need >= 11), searching for alternatives..." >&2
    fi

    # 2. Check JAVA_HOME
    if [ -n "${JAVA_HOME:-}" ] && is_suitable_java "$JAVA_HOME/bin/java"; then
        echo "$JAVA_HOME/bin/java"
        return 0
    fi

    # 3. Common JDK locations
    local search_dirs=(
        # IntelliJ / JetBrains managed JDKs
        "$HOME/.jdks"
        # SDKMAN
        "$HOME/.sdkman/candidates/java"
        # Homebrew (macOS)
        "/opt/homebrew/opt/openjdk@17/bin"
        "/opt/homebrew/opt/openjdk@21/bin"
        "/opt/homebrew/opt/openjdk@11/bin"
        "/usr/local/opt/openjdk@17/bin"
        "/usr/local/opt/openjdk@21/bin"
        "/usr/local/opt/openjdk@11/bin"
        "/opt/homebrew/opt/openjdk/bin"
        "/usr/local/opt/openjdk/bin"
        # Linux package managers
        "/usr/lib/jvm"
        # macOS system Java
        "/Library/Java/JavaVirtualMachines"
        # Common manual installs
        "/usr/local/java"
        "/opt/java"
    )

    for dir in "${search_dirs[@]}"; do
        [ -d "$dir" ] || continue

        # Direct bin check (e.g., /opt/homebrew/opt/openjdk@17/bin/java)
        if [ -x "$dir/java" ] && is_suitable_java "$dir/java"; then
            echo "$dir/java"
            return 0
        fi

        # Subdirectory search (e.g., ~/.jdks/openjdk-17.0.2/bin/java)
        while IFS= read -r java_bin; do
            if is_suitable_java "$java_bin"; then
                echo "$java_bin"
                return 0
            fi
        done < <(find "$dir" -maxdepth 4 -name "java" -path "*/bin/java" -type f 2>/dev/null | sort -rV | head -10)
    done

    # 4. macOS: java_home utility
    if command -v /usr/libexec/java_home &>/dev/null; then
        local mac_java
        mac_java=$(/usr/libexec/java_home -v 11+ 2>/dev/null || true)
        if [ -n "$mac_java" ] && is_suitable_java "$mac_java/bin/java"; then
            echo "$mac_java/bin/java"
            return 0
        fi
    fi

    return 1
}

# --- Main ---

JAVA_BIN=""
if JAVA_BIN=$(find_java); then
    JAVA_VERSION=$(get_java_major_version "$JAVA_BIN")
    echo "Using Java $JAVA_VERSION: $JAVA_BIN" >&2
    exec "$JAVA_BIN" "$PARSER" "$@"
else
    echo "ERROR: No suitable JDK (>= 11) found." >&2
    echo "" >&2
    echo "DumpParser.java requires JDK 11+ for single-file source execution." >&2
    echo "" >&2
    echo "Searched:" >&2
    echo "  - java on PATH" >&2
    echo "  - JAVA_HOME ($JAVA_HOME)" >&2
    echo "  - ~/.jdks, ~/.sdkman, /usr/lib/jvm, /opt/homebrew/opt/openjdk*" >&2
    echo "  - /Library/Java/JavaVirtualMachines (macOS)" >&2
    echo "" >&2
    echo "Please either:" >&2
    echo "  1. Install JDK 11+: https://adoptium.net" >&2
    echo "  2. Set JAVA_HOME to point to a JDK 11+ installation" >&2
    echo "  3. Add a JDK 11+ bin directory to your PATH" >&2
    exit 1
fi
