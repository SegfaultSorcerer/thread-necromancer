---
name: thread-compare
description: Compare two thread dumps to identify state changes, new/disappeared threads, and contention shifts
user_invocable: true
usage: /thread-compare <file1> <file2>
arguments:
  - name: file1
    description: "Path to first (earlier) thread dump"
    required: true
  - name: file2
    description: "Path to second (later) thread dump"
    required: true
---

# Thread Compare — Diff Two Dumps

You are a JVM thread dump analysis expert. Your task is to compare two thread dumps and identify what changed between them — state transitions, new or disappeared threads, and shifts in contention patterns.

## Locating Scripts

**macOS/Linux:** `bash <plugin-root>/scripts/run-parser.sh <file>`
**Windows:** `powershell -File <plugin-root>/scripts/run-parser.ps1 <file>`

These wrappers automatically find a suitable JDK (>= 11), searching PATH, JAVA_HOME, ~/.jdks, and common install locations.

## Procedure

### Step 1: Validate Both Files

1. Confirm both files exist and look like thread dumps
2. If the files have timestamps, determine which is earlier and which is later
3. If timestamps are unavailable, treat file1 as "before" and file2 as "after"

### Step 2: Parse Both Dumps

**macOS/Linux:**
```bash
bash <plugin-root>/scripts/run-parser.sh <file1>
bash <plugin-root>/scripts/run-parser.sh <file2>
```
**Windows:**
```powershell
powershell -File <plugin-root>/scripts/run-parser.ps1 <file1>
powershell -File <plugin-root>/scripts/run-parser.ps1 <file2>
```

### Step 3: Compare

Use the diff strategies reference (`skills/thread-compare/references/diff-strategies.md`).

**3a. Match Threads by Name**
- Match threads across both dumps using their thread name (stable identifier)
- Categorize each thread as: UNCHANGED, STATE_CHANGED, STACK_CHANGED, NEW, DISAPPEARED

**3b. Per-Thread State Changes**
For matched threads, note:
- State transitions (e.g., RUNNABLE → BLOCKED)
- Stack trace changes (top frame different = progress)
- Lock acquisition/release changes

**3c. Aggregate Changes**
- Total thread count delta
- Per-pool thread count delta
- Per-state count delta
- Blocked cluster size changes
- Lock holder changes

### Step 4: Report

```markdown
## Thread Dump Comparison Report

### Dump Info
| | Dump 1 (Before) | Dump 2 (After) |
|---|---|---|
| File | <path1> | <path2> |
| Timestamp | <ts1> | <ts2> |
| Total Threads | <n1> | <n2> |
| RUNNABLE | <n> | <n> |
| WAITING | <n> | <n> |
| TIMED_WAITING | <n> | <n> |
| BLOCKED | <n> | <n> |

### State Transitions
| Thread | Before | After | Assessment |
|---|---|---|---|
| (only threads that changed state) |

### New Threads (in Dump 2 only)
| Thread | State | Pool | Assessment |
|---|---|---|---|

### Disappeared Threads (in Dump 1 only)
| Thread | Last State | Pool | Assessment |
|---|---|---|---|

### Thread Pool Changes
| Pool | Before | After | Delta | Assessment |
|---|---|---|---|---|

### Contention Changes
| Cluster (wait point) | Before | After | Trend |
|---|---|---|---|

### Lock Holder Changes
| Lock | Before Holder | After Holder | Assessment |
|---|---|---|---|

### Summary
Brief narrative of what changed overall: is the situation improving, worsening, or stable?

### Recommended Actions
Prioritized list of actions based on the changes observed.
```

## Important Notes

- Focus the report on what CHANGED — don't repeat the full analysis of each dump
- If one dump appears to be a GC pause (all threads parked), note this prominently
- Thread name matching is reliable for pool threads but one-off threads (e.g., `Thread-0`) may not match meaningfully
- If the time gap between dumps is known, use it to estimate rates of change
