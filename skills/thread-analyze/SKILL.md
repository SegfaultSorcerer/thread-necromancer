---
name: thread-analyze
description: Analyze an existing JVM thread dump file for deadlocks, contention, pool issues, and framework-specific problems. Use this skill whenever someone asks to analyze, look at, or debug a thread dump file, a .tdump file, or mentions thread-related JVM problems. Also trigger when users share a file that looks like a thread dump (contains thread states and stack traces).
user_invocable: true
usage: /thread-analyze <file-path>
arguments:
  - name: file-path
    description: "Path to thread dump file (.txt, .tdump, .log)"
    required: true
---

# Thread Analyze — Analyze Existing Dump File

You are a JVM thread dump analysis expert. Your task is to analyze an existing thread dump file and produce a structured, actionable analysis report.

Production thread dumps can be thousands of lines long (5000–20000 lines for apps with 500–2000 threads). Reading the raw dump directly wastes tokens and makes it easy to miss patterns buried in noise. The dump parser compresses this into ~200 structured lines, which is what you should analyze.

## Locating Scripts

The parser is at `scripts/DumpParser.java` relative to the plugin root. The plugin root is two levels up from this SKILL.md (this file is at `skills/thread-analyze/SKILL.md`, so scripts are at `../../scripts/`).

The parser is cross-platform (Java): `java <plugin-root>/scripts/DumpParser.java <file>`

## Procedure

### Step 1: Parse the Dump (CRITICAL — always do this first)

Run the dump parser to compress the raw dump into structured sections:

```bash
java <plugin-root>/scripts/DumpParser.java <file-path>
```

The parser output gives you everything you need for analysis:
- **DUMP METADATA** — timestamp, JVM version, PID, total thread count
- **THREAD STATE SUMMARY** — counts per state (RUNNABLE, WAITING, TIMED_WAITING, BLOCKED)
- **THREAD POOLS** — identified pools with state breakdown per pool
- **DEADLOCKS** — JVM-detected deadlocks with lock chain
- **BLOCKED THREAD CLUSTERS** — groups of threads blocked at the same point, with representative stack traces and lock info
- **LOCK OWNERS** — threads that hold locks (the bottlenecks)
- **NOTABLE THREADS** — up to 20 RUNNABLE non-idle threads with full stack traces

This structured output is the primary input for your analysis. Do NOT read the raw dump file directly unless the parser fails or you need to investigate a specific thread in detail.

**If the parser is not available** (e.g., permission issues, Java not on PATH): Read the raw file, but focus your reading on the deadlock section (search for "Found.*deadlock"), BLOCKED threads, and thread headers — do not try to read every single thread's stack trace.

### Step 2: Validate

From the parser output, confirm the data looks like a valid thread dump:
- Total threads > 0
- Thread states are present
- If the file contains multiple concatenated dumps (parser may note this), focus on the most recent one.

### Step 3: Analyze

Work through the parser output systematically. The structured sections map directly to the analysis areas:

1. **Thread State Distribution** — Calculate percentages from the STATE SUMMARY. Flag BLOCKED > 10% as serious. (Reference: `skills/thread-dump/references/thread-states.md`)
2. **Deadlocks** — Check the DEADLOCKS section. If present, this is always CRITICAL.
3. **Blocked Thread Clusters** — The parser groups these for you. Focus on: cluster size, what lock they're waiting on, who holds the lock.
4. **Thread Pool Health** — From THREAD POOLS section: any pool with 0 idle threads? Any pool with all threads BLOCKED?
5. **Lock Contention** — From LOCK OWNERS: which holders appear in cluster wait targets?
6. **Framework-Specific Patterns** — Detect framework from thread names in THREAD POOLS. Read `skills/thread-dump/references/spring-thread-patterns.md` only for the relevant framework section.
7. **I/O Issues** — From NOTABLE THREADS: threads RUNNABLE at `SocketInputStream.read` = missing timeouts.

Use the checklist in `skills/thread-analyze/references/analysis-checklist.md` to ensure completeness.

Severity classification:
- **CRITICAL** — Deadlocks, >30% BLOCKED, pool exhaustion
- **WARNING** — 10–30% BLOCKED, suboptimal pool sizes, missing timeouts
- **INFO** — Default configs that could be improved

### Step 4: Report

Produce the report in this exact format:

```markdown
## Thread Dump Analysis Report

### Metadata
| Field | Value |
|---|---|
| Timestamp | <from parser DUMP METADATA> |
| JVM | <version> |
| PID | <pid> |
| Threads | <total> total (<daemon> daemon) |
| Source | <file path> |

### Thread State Distribution
| State | Count | Percentage | Assessment |
|---|---|---|---|
| RUNNABLE | N | X% | <assessment> |
| WAITING | N | X% | <assessment> |
| TIMED_WAITING | N | X% | <assessment> |
| BLOCKED | N | X% | <assessment> |

### Thread Pool Health
| Pool | Size | Busy | Idle | Blocked | Assessment |
|---|---|---|---|---|---|

### Deadlocks
NONE DETECTED — or detailed deadlock chain from parser output.

### Contention Hotspots
| Severity | Lock / Monitor | Waiting | Holder | Duration Est. |
|---|---|---|---|---|

### Blocked Thread Clusters
For each cluster from parser: count, wait point, lock info, representative stack.
Strip proxy class names ($$SpringCGLIB$$, _Subclass, $Proxy → report real class).

### Framework-Specific Findings
| Severity | Finding | Detail |
|---|---|---|

### Top 3 Actions
1. **[SEVERITY]** <action> — <why> — <concrete config/code fix>
2. **[SEVERITY]** <action> — <why> — <concrete config/code fix>
3. **[SEVERITY]** <action> — <why> — <concrete config/code fix>
```

## Important Notes

- The parser output is your primary data source — trust its structured sections over reading raw dumps
- Strip proxy class names and report the real class
- Provide exact config properties (YAML/properties) in fix suggestions
- Detect the framework from thread names, apply relevant checks only
- If the dump was captured during a GC pause (all threads parked, 0 RUNNABLE), note this prominently
