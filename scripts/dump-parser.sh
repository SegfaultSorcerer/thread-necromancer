#!/usr/bin/env bash
# dump-parser.sh — Parse raw thread dumps into structured sections
# Part of thread-necromancer: "Raising insights from dead threads"

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: dump-parser.sh <thread-dump-file>

Parses a raw JVM thread dump into structured sections for analysis.

Output sections:
  DUMP METADATA         Timestamp, JVM version, PID, thread count
  THREAD STATE SUMMARY  Counts by thread state
  THREAD POOLS          Grouped threads by pool with state breakdown
  DEADLOCKS             Detected deadlocks (from JVM output)
  BLOCKED CLUSTERS      Groups of threads blocked at the same point
  LOCK OWNERS           Threads holding locks with waiter info
  RAW THREADS           Non-idle threads with collapsed JDK frames
EOF
}

if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 1
fi

DUMP_FILE="$1"

if [ ! -f "$DUMP_FILE" ]; then
    echo "Error: File not found: $DUMP_FILE" >&2
    exit 1
fi

# Helper: grep -c that returns 0 instead of failing on no match
count_grep() {
    grep -c "$@" || true
}

# --- Extract metadata from header (if captured by dump-collector) ---

print_metadata() {
    echo "=== DUMP METADATA ==="

    local captured_at pid jvm_version
    captured_at=$(grep -m1 '^captured_at:' "$DUMP_FILE" 2>/dev/null | sed 's/^captured_at: //' || true)
    pid=$(grep -m1 '^pid:' "$DUMP_FILE" 2>/dev/null | sed 's/^pid: //' || true)
    jvm_version=$(grep -m1 '^jvm_version:' "$DUMP_FILE" 2>/dev/null | sed 's/^jvm_version: //' || true)

    if [ -z "$captured_at" ]; then
        captured_at=$(grep -m1 -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' "$DUMP_FILE" || true)
    fi
    if [ -z "$jvm_version" ]; then
        jvm_version=$(grep -m1 -i 'VM version' "$DUMP_FILE" | sed 's/.*: //' || true)
    fi

    local total_threads daemon_threads
    total_threads=$(count_grep '^"' "$DUMP_FILE")
    daemon_threads=$(count_grep 'daemon' "$DUMP_FILE")

    echo "timestamp: ${captured_at:-unknown}"
    echo "jvm_version: ${jvm_version:-unknown}"
    echo "pid: ${pid:-unknown}"
    echo "total_threads: $total_threads"
    echo "daemon_threads: $daemon_threads"
    echo ""
}

# --- Thread State Summary ---

print_state_summary() {
    echo "=== THREAD STATE SUMMARY ==="

    # Use exact patterns to avoid TIMED_WAITING matching WAITING
    local runnable waiting timed_waiting blocked new terminated
    runnable=$(count_grep 'java.lang.Thread.State: RUNNABLE' "$DUMP_FILE")
    timed_waiting=$(count_grep 'java.lang.Thread.State: TIMED_WAITING' "$DUMP_FILE")
    blocked=$(count_grep 'java.lang.Thread.State: BLOCKED' "$DUMP_FILE")
    new=$(count_grep 'java.lang.Thread.State: NEW' "$DUMP_FILE")
    terminated=$(count_grep 'java.lang.Thread.State: TERMINATED' "$DUMP_FILE")
    # grep 'State: WAITING' does NOT match 'State: TIMED_WAITING' — no subtraction needed
    waiting=$(count_grep 'java.lang.Thread.State: WAITING' "$DUMP_FILE")

    echo "RUNNABLE: $runnable"
    echo "WAITING: $waiting"
    echo "TIMED_WAITING: $timed_waiting"
    echo "BLOCKED: $blocked"
    echo "NEW: $new"
    echo "TERMINATED: $terminated"
    echo ""
}

# --- Thread Pool Detection ---

print_thread_pools() {
    echo "=== THREAD POOLS ==="

    local tmpfile
    tmpfile=$(mktemp)

    # Build name-state pairs using POSIX-compatible awk
    # Thread name is between first pair of quotes on lines starting with "
    awk '
    /^"/ {
        # Extract thread name: everything between first " and second "
        line = $0
        sub(/^"/, "", line)
        idx = index(line, "\"")
        if (idx > 0) {
            thread_name = substr(line, 1, idx - 1)
        } else {
            thread_name = ""
        }
    }
    /java\.lang\.Thread\.State:/ {
        # Extract just the state name (e.g. RUNNABLE, WAITING, etc.)
        line = $0
        sub(/.*State: /, "", line)
        # Remove any trailing description in parens
        sub(/ .*/, "", line)
        state = line
        if (thread_name != "") {
            print thread_name "\t" state
            thread_name = ""
        }
    }
    ' "$DUMP_FILE" > "$tmpfile"

    # Pool patterns in order, pipe-separated: pattern|label
    local pool_defs=(
        # Tomcat
        "http-nio-.*-exec-|Tomcat NIO Executor"
        "http-nio-.*-Poller|Tomcat NIO Poller"
        "http-nio-.*-Acceptor|Tomcat Acceptor"
        # Jetty
        "qtp.*-|Jetty QueuedThreadPool"
        # Undertow
        "XNIO-.*-task-|Undertow Worker"
        "XNIO-.*-I/O-|Undertow I/O"
        # Spring
        "scheduling-|Spring @Scheduled"
        "task-|Spring @Async"
        "taskScheduler-|Spring TaskScheduler"
        "AsyncExecutor-|Async Executor"
        # Quarkus / Vert.x
        "executor-thread-|Quarkus Worker Pool"
        "vert.x-eventloop-thread-|Vert.x Event Loop"
        "vert.x-worker-thread-|Vert.x Worker Pool"
        "vert.x-internal-blocking-|Vert.x Internal Blocking"
        "quarkus-scheduler-|Quarkus Scheduler"
        # Micronaut
        "default-nioEventLoopGroup-|Micronaut Event Loop"
        "io-executor-thread-|Micronaut I/O Pool"
        "scheduled-executor-thread-|Micronaut Scheduler"
        # Reactive
        "reactor-http-nio-|WebFlux/Netty"
        "parallel-|Reactor Parallel"
        "boundedElastic-|Reactor BoundedElastic"
        # Database pools
        "HikariPool-.*housekeeper|HikariCP Housekeeper"
        "HikariPool-.*connection|HikariCP Connection"
        "C3P0PooledConnectionPool|C3P0 Connection Pool"
        # Clients / Messaging
        "lettuce-nioEventLoop-|Redis Lettuce"
        "redisson-netty-|Redisson Redis"
        "kafka-producer-network-|Kafka Producer"
        "kafka-coordinator-|Kafka Coordinator"
        "Eureka-|Eureka Discovery"
        "Hystrix-|Hystrix Circuit Breaker"
        # JDK
        "ForkJoinPool.commonPool|ForkJoinPool Common"
        "ForkJoinPool-|ForkJoinPool Custom"
        "pool-.*-thread-|Generic Thread Pool"
    )

    local matched_file
    matched_file=$(mktemp)

    for def in "${pool_defs[@]}"; do
        local pattern="${def%%|*}"
        local label="${def##*|}"

        local total
        total=$(grep -cE "^${pattern}" "$tmpfile" 2>/dev/null || true)
        if [ "$total" -gt 0 ]; then
            local pool_lines runnable waiting timed_waiting blocked
            pool_lines=$(grep -E "^${pattern}" "$tmpfile")
            runnable=$(echo "$pool_lines" | count_grep "RUNNABLE")
            timed_waiting=$(echo "$pool_lines" | count_grep "TIMED_WAITING")
            blocked=$(echo "$pool_lines" | count_grep "BLOCKED")
            # In tmpfile, state column is exact (WAITING, TIMED_WAITING etc.)
            # grep "WAITING" also matches TIMED_WAITING, so subtract
            local all_w
            all_w=$(echo "$pool_lines" | count_grep "WAITING")
            waiting=$((all_w - timed_waiting))

            echo "pool: ${label}"
            echo "  total: ${total}, RUNNABLE: ${runnable}, WAITING: ${waiting}, TIMED_WAITING: ${timed_waiting}, BLOCKED: ${blocked}"

            grep -E "^${pattern}" "$tmpfile" >> "$matched_file" 2>/dev/null || true
        fi
    done

    local total_threads matched_count other_count
    total_threads=$(wc -l < "$tmpfile" | tr -d ' ')
    matched_count=$(sort -u "$matched_file" | wc -l | tr -d ' ')
    other_count=$((total_threads - matched_count))

    if [ "$other_count" -gt 0 ]; then
        echo "pool: Other/System"
        echo "  total: ${other_count}"
    fi

    rm -f "$tmpfile" "$matched_file"
    echo ""
}

# --- Deadlock Detection ---

print_deadlocks() {
    echo "=== DEADLOCKS ==="

    local deadlock_section
    deadlock_section=$(sed -n '/Found.*[Dd]eadlock/,/^$/p' "$DUMP_FILE" 2>/dev/null || true)

    if [ -n "$deadlock_section" ]; then
        echo "$deadlock_section"
    else
        echo "NONE DETECTED"
    fi
    echo ""
}

# --- Blocked Thread Clusters ---

print_blocked_clusters() {
    echo "=== BLOCKED THREAD CLUSTERS ==="

    awk '
    /^"/ {
        line = $0
        sub(/^"/, "", line)
        idx = index(line, "\"")
        if (idx > 0) {
            current_thread = substr(line, 1, idx - 1)
        } else {
            current_thread = ""
        }
        frame_count = 0
        state = ""
        lock_info = ""
        for (i in frames) delete frames[i]
    }

    /java\.lang\.Thread\.State:/ {
        state = $0
        sub(/.*State: /, "", state)
    }

    /^\tat / {
        frame_count++
        if (frame_count <= 5) {
            frames[frame_count] = $0
        }
    }

    /- waiting to lock/ || /- parking to wait/ || /- locked/ {
        if (lock_info == "") {
            lock_info = $0
        } else {
            lock_info = lock_info "|||" $0
        }
    }

    /^$/ {
        if (current_thread != "" && (state ~ /BLOCKED/ || (state ~ /WAITING/ && lock_info != ""))) {
            key = ""
            lim = 3
            if (frame_count < lim) lim = frame_count
            for (i = 1; i <= lim; i++) {
                key = key frames[i] "|"
            }
            if (key != "") {
                cluster_threads[key] = cluster_threads[key] current_thread "|||"
                cluster_count[key]++
                cluster_state[key] = state
                cluster_frames[key] = ""
                flim = 5
                if (frame_count < flim) flim = frame_count
                for (i = 1; i <= flim; i++) {
                    cluster_frames[key] = cluster_frames[key] frames[i] "|||"
                }
                if (cluster_lock[key] == "") {
                    cluster_lock[key] = lock_info
                }
            }
        }
        current_thread = ""
    }

    END {
        n = 0
        for (key in cluster_count) {
            n++
            printf "cluster_%d: %d threads\n", n, cluster_count[key]
            printf "  state: %s\n", cluster_state[key]
            printf "  top_frames:\n"

            nf = split(cluster_frames[key], f, "\\|\\|\\|")
            for (i = 1; i <= nf; i++) {
                if (f[i] != "") printf "  %s\n", f[i]
            }

            if (cluster_lock[key] != "") {
                printf "  lock_info:\n"
                nl = split(cluster_lock[key], l, "\\|\\|\\|")
                for (i = 1; i <= nl; i++) {
                    if (l[i] != "") printf "  %s\n", l[i]
                }
            }

            nt = split(cluster_threads[key], t, "\\|\\|\\|")
            printf "  representative: \"%s\"\n", t[1]
            printf "\n"
        }

        if (n == 0) {
            print "NONE"
        }
    }
    ' "$DUMP_FILE"

    echo ""
}

# --- Lock Owners ---

print_lock_owners() {
    echo "=== LOCK OWNERS ==="

    awk '
    /^"/ {
        line = $0
        sub(/^"/, "", line)
        idx = index(line, "\"")
        if (idx > 0) {
            current_thread = substr(line, 1, idx - 1)
        } else {
            current_thread = ""
        }
        state = ""
        hold_count = 0
        wait_count = 0
        for (i in holds) delete holds[i]
        for (i in waits) delete waits[i]
    }

    /java\.lang\.Thread\.State:/ {
        state = $0
        sub(/.*State: /, "", state)
    }

    /- locked </ {
        hold_count++
        holds[hold_count] = $0
    }

    /- waiting to lock </ || /- parking to wait for/ {
        wait_count++
        waits[wait_count] = $0
    }

    /^$/ {
        if (current_thread != "" && (hold_count > 0 || wait_count > 0)) {
            printf "Thread \"%s\":\n", current_thread
            printf "  state: %s\n", state
            for (i = 1; i <= hold_count; i++) {
                printf "  holds: %s\n", holds[i]
            }
            for (i = 1; i <= wait_count; i++) {
                printf "  waiting_for: %s\n", waits[i]
            }
            printf "\n"
        }
        current_thread = ""
    }
    ' "$DUMP_FILE"

    echo ""
}

# --- Raw Non-Idle Threads ---

print_raw_threads() {
    echo "=== RAW THREADS (non-idle) ==="

    awk '
    /^"/ {
        thread_block = $0 "\n"
        in_thread = 1
        is_idle = 0
        state = ""
    }

    in_thread && /java\.lang\.Thread\.State:/ {
        state = $0
        thread_block = thread_block $0 "\n"
        next
    }

    in_thread && /^\tat / {
        thread_block = thread_block $0 "\n"
    }

    in_thread && /^[ \t]*-/ {
        thread_block = thread_block $0 "\n"
    }

    in_thread && /^\tat sun\.misc\.Unsafe\.park/ && state ~ /WAITING|TIMED_WAITING/ {
        is_idle = 1
    }

    in_thread && /^\tat jdk\.internal\.misc\.Unsafe\.park/ && state ~ /WAITING|TIMED_WAITING/ {
        is_idle = 1
    }

    in_thread && /^$/ {
        if (!is_idle || state ~ /BLOCKED/) {
            printf "%s\n", thread_block
        }
        in_thread = 0
        thread_block = ""
    }
    ' "$DUMP_FILE"
}

# --- Main ---

print_metadata
print_state_summary
print_thread_pools
print_deadlocks
print_blocked_clusters
print_lock_owners
print_raw_threads
