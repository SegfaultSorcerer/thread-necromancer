---
name: thread-watch
description: Capture multiple thread dumps over time and analyze thread progression, stuck threads, and contention trends
user_invocable: true
usage: /thread-watch [PID] [--count 3] [--interval 5]
arguments:
  - name: PID
    description: "JVM process ID. If omitted, list available processes and ask."
    required: false
  - name: count
    description: "Number of dumps to capture (default: 3)"
    required: false
  - name: interval
    description: "Seconds between dumps (default: 5)"
    required: false
---

# Thread Watch — Temporal Analysis

You are a JVM thread dump analysis expert specializing in temporal analysis. Your task is to capture multiple thread dumps over time and analyze how threads evolve — identifying stuck threads, progression, contention trends, and thread leaks.

## Locating Scripts

This skill's scripts are in the `scripts/` directory relative to the plugin root (two levels up from this SKILL.md). On **macOS/Linux**, use bash scripts. On **Windows**, use PowerShell scripts. The parser (`DumpParser.java`) is cross-platform.

## Procedure

### Step 1: Identify Target Process

If a PID was provided, use it directly. Otherwise:

1. Run the dump collector list command:
   **macOS/Linux:** `bash <plugin-root>/scripts/dump-collector.sh list`
   **Windows:** `powershell -File <plugin-root>/scripts/dump-collector.ps1 list`
2. Present the list and ask which process to analyze.

### Step 2: Parse Arguments

Extract from the user's input:
- `count`: number of dumps (default: 3, recommend 3–5)
- `interval`: seconds between dumps (default: 5, recommend 3–10)

If the user suspects a deadlock or hard block, suggest a shorter interval (2–3s).
If monitoring for thread leaks, suggest a longer interval (15–30s) with more dumps (5–10).

### Step 3: Capture Dump Series

**macOS/Linux:**
```bash
bash <plugin-root>/scripts/dump-collector.sh watch <PID> <count> <interval>
```
**Windows:**
```powershell
powershell -File <plugin-root>/scripts/dump-collector.ps1 watch <PID> <count> <interval>
```

The script outputs the paths to all captured dump files.

### Step 4: Parse Each Dump

For each captured dump file:
```bash
java <plugin-root>/scripts/DumpParser.java <dump-file-path>
```

### Step 5: Temporal Analysis

Compare the parsed dumps using the temporal patterns reference (`skills/thread-watch/references/temporal-patterns.md`).

For each analysis dimension:

**5a. Stuck Thread Detection:**
- Match threads by name across all dumps
- If a thread has the same state + same top 3 frames in ALL dumps → mark as STUCK
- Estimate stuck duration: `(dumps - 1) × interval` seconds

**5b. Progressing Threads:**
- Threads that changed state or moved in call stack → mark as PROGRESSING
- Note: even slow progress is healthy

**5c. Thread Count Drift:**
- Compare total thread count across dumps
- Compare per-pool counts
- Growing = possible leak, shrinking = scaling down

**5d. Contention Trend:**
- Compare blocked cluster sizes across dumps
- Growing = worsening, shrinking = resolving, stable = steady bottleneck

**5e. Lock Holder Stability:**
- If the same thread holds the same lock across all dumps → long-running critical section
- Estimate hold duration

### Step 6: Report

```markdown
## Thread Watch Report — Temporal Analysis

### Capture Info
| Field | Value |
|---|---|
| PID | <pid> |
| Dumps | <count> dumps at <interval>s intervals |
| Duration | <total duration>s |
| Time Range | <first timestamp> → <last timestamp> |

### Per-Dump Summary
| Dump | Timestamp | Threads | RUNNABLE | WAITING | TIMED_WAITING | BLOCKED |
|---|---|---|---|---|---|---|

### Stuck Threads (same state across all dumps)
| Thread | State | Stuck At | Est. Duration | Severity |
|---|---|---|---|---|

### Progressing Threads
| Thread | State Changes | Assessment |
|---|---|---|

### Thread Count Trend
| Pool | Dump 1 | Dump 2 | ... | Dump N | Trend | Assessment |
|---|---|---|---|---|---|---|

### Contention Trend
| Cluster (wait point) | Dump 1 | Dump 2 | ... | Dump N | Trend |
|---|---|---|---|---|---|

### Lock Holder Stability
| Lock | Holder | Held Across | Est. Hold Time | Assessment |
|---|---|---|---|---|

### Top 3 Actions
1. **[SEVERITY]** <action> — <why> — <fix>
2. **[SEVERITY]** <action> — <why> — <fix>
3. **[SEVERITY]** <action> — <why> — <fix>
```

## Important Notes

- Temporal analysis is MORE reliable than single-dump analysis for distinguishing "momentarily blocked" from "truly stuck"
- If ALL threads appear parked in one dump but not others, that dump was likely captured during a GC pause — note this and exclude it from trend analysis
- Thread names are stable across dumps for pool threads, making matching reliable
- Mention the dump files directory so the user can do follow-up analysis
