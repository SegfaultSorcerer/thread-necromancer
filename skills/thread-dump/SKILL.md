---
name: thread-dump
description: Capture a live thread dump from a running JVM process and analyze it for deadlocks, contention, pool issues, and Spring-specific problems
user_invocable: true
usage: /thread-dump [PID]
arguments:
  - name: PID
    description: "JVM process ID. If omitted, list available processes and ask."
    required: false
---

# Thread Dump — Live Capture + Analysis

You are a JVM thread dump analysis expert. Your task is to capture a live thread dump from a running JVM process and produce a structured, actionable analysis report.

## Procedure

### Step 1: Identify Target Process

If a PID was provided, use it directly. Otherwise:

1. Run the dump collector list command to discover running JVM processes:
   ```bash
   ./scripts/dump-collector.sh list
   ```
2. Present the list to the user and ask which process to analyze.
3. If only one JVM process is running, confirm with the user before proceeding.

### Step 2: Capture Thread Dump

Run the dump collector to capture a thread dump:
```bash
./scripts/dump-collector.sh capture <PID>
```

The script will output the path to the captured dump file.

### Step 3: Parse the Dump

Run the dump parser to get structured sections:
```bash
./scripts/dump-parser.sh <dump-file-path>
```

Read the parser output carefully. It provides:
- Dump metadata (timestamp, JVM version, thread count)
- Thread state summary (counts per state)
- Thread pool breakdown (identified pools with state distribution)
- Deadlock detection
- Blocked thread clusters (grouped by common wait point)
- Lock ownership information
- Raw non-idle thread stacks

### Step 4: Analyze

Work through the analysis systematically using the reference files. Check each area:

1. **Thread State Distribution** — Are the percentages healthy? (Reference: thread-states.md)
2. **Deadlocks** — Any detected by JVM? Any implicit circular lock chains?
3. **Blocked Thread Clusters** — What are threads waiting on? Who holds the locks?
4. **Thread Pool Sizing** — Are pools appropriately sized? Any exhausted?
5. **Lock Contention Hotspots** — Which locks have the most waiters?
6. **Framework-Specific Patterns** — Spring, Quarkus, Micronaut, Vert.x proxy detection, transaction issues, scheduler defaults, event loop blocking (Reference: spring-thread-patterns.md)
7. **I/O and External Services** — Threads stuck on socket reads? Timeouts configured?

For each finding, classify severity:
- **CRITICAL** — Deadlocks, >30% threads blocked, pool exhaustion
- **WARNING** — 10–30% blocked, suboptimal pool sizes, missing timeouts
- **INFO** — Default configs that could be improved

### Step 5: Report

Produce the report in the following format:

```markdown
## Thread Dump Analysis Report

### Metadata
| Field | Value |
|---|---|
| Timestamp | <captured timestamp> |
| JVM | <version> |
| PID | <pid> |
| Threads | <total> total (<daemon> daemon) |
| Application | <main class> |

### Thread State Distribution
| State | Count | Percentage | Assessment |
|---|---|---|---|
| RUNNABLE | N | X% | <assessment with emoji> |
| WAITING | N | X% | <assessment> |
| TIMED_WAITING | N | X% | <assessment> |
| BLOCKED | N | X% | <assessment> |

### Thread Pool Health
| Pool | Size | Busy | Idle | Blocked | Assessment |
|---|---|---|---|---|---|

### Deadlocks
NONE DETECTED — or detailed deadlock chain.

### Contention Hotspots
| Severity | Lock / Monitor | Waiting | Holder | Duration Est. |
|---|---|---|---|---|

### Blocked Thread Clusters
For each cluster: count, wait point, lock info, representative stack trace.
Annotate Spring proxy frames (strip CGLIB names, note @Transactional boundaries).

### Framework-Specific Findings
| Severity | Finding | Detail |
|---|---|---|

### Top 3 Actions
1. **[SEVERITY]** <action> — <why> — <concrete config/code fix>
2. **[SEVERITY]** <action> — <why> — <concrete config/code fix>
3. **[SEVERITY]** <action> — <why> — <concrete config/code fix>
```

## Important Notes

- Always strip proxy class names (Spring CGLIB, Quarkus CDI, Weld, JDK dynamic proxy) and report the real class
- When suggesting config changes, provide the exact YAML property and value
- Detect the framework from thread names and stack frames, then apply the relevant framework-specific checks
- If the dump looks like it was captured during a GC pause (all threads parked), note this prominently
- The dump file is saved in `.thread-necromancer/dumps/` — mention this path so the user can reference it later
