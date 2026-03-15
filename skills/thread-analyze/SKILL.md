---
name: thread-analyze
description: Analyze an existing thread dump file for deadlocks, contention, pool issues, and Spring-specific problems
user_invocable: true
usage: /thread-analyze <file-path>
arguments:
  - name: file-path
    description: "Path to thread dump file (.txt, .tdump, .log)"
    required: true
---

# Thread Analyze — Analyze Existing Dump File

You are a JVM thread dump analysis expert. Your task is to analyze an existing thread dump file and produce a structured, actionable analysis report.

## Procedure

### Step 1: Validate the File

1. Read the file and confirm it looks like a JVM thread dump. Look for the characteristic pattern:
   - Lines starting with `"thread-name" #N` (thread headers)
   - `java.lang.Thread.State:` lines
   - Stack trace frames starting with `at `
2. If the file doesn't look like a thread dump, inform the user and suggest what format is expected.
3. If the file contains multiple concatenated dumps (some tools or `kill -3` append to stdout), detect the boundaries (look for `Full thread dump` headers) and note how many dumps are present. Analyze the most recent one, or ask the user which one to analyze.

### Step 2: Parse the Dump

Run the dump parser to get structured sections:
```bash
./scripts/dump-parser.sh <file-path>
```

Read the parser output carefully. It provides:
- Dump metadata (timestamp, JVM version, thread count)
- Thread state summary (counts per state)
- Thread pool breakdown (identified pools with state distribution)
- Deadlock detection
- Blocked thread clusters (grouped by common wait point)
- Lock ownership information
- Raw non-idle thread stacks

### Step 3: Analyze

Work through the analysis systematically using the reference files in `skills/thread-dump/references/` and `skills/thread-analyze/references/`. Check each area:

1. **Thread State Distribution** — Are the percentages healthy? (Reference: thread-states.md)
2. **Deadlocks** — Any detected by JVM? Any implicit circular lock chains?
3. **Blocked Thread Clusters** — What are threads waiting on? Who holds the locks?
4. **Thread Pool Sizing** — Are pools appropriately sized? Any exhausted?
5. **Lock Contention Hotspots** — Which locks have the most waiters?
6. **Spring-Specific Patterns** — Proxy overhead, @Transactional issues, @Async pools, @Scheduled defaults (Reference: spring-thread-patterns.md)
7. **I/O and External Services** — Threads stuck on socket reads? Timeouts configured?

Use the analysis checklist in `skills/thread-analyze/references/analysis-checklist.md` to ensure nothing is missed.

For each finding, classify severity:
- **CRITICAL** — Deadlocks, >30% threads blocked, pool exhaustion
- **WARNING** — 10–30% blocked, suboptimal pool sizes, missing timeouts
- **INFO** — Default configs that could be improved

### Step 4: Report

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
| Source | <file path> |

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

### Spring-Specific Findings
| Severity | Finding | Detail |
|---|---|---|

### Top 3 Actions
1. **[SEVERITY]** <action> — <why> — <concrete config/code fix>
2. **[SEVERITY]** <action> — <why> — <concrete config/code fix>
3. **[SEVERITY]** <action> — <why> — <concrete config/code fix>
```

## Important Notes

- Always strip Spring proxy class names (e.g., `$$EnhancerBySpringCGLIB$$`) and report the real class
- When suggesting config changes, provide the exact YAML property and value
- If the application is not Spring-based, skip Spring-specific analysis sections
- If the dump looks like it was captured during a GC pause (all threads parked), note this prominently
- If the dump file was not captured with dump-collector.sh, some metadata fields may be unavailable — that's fine, work with what's available
