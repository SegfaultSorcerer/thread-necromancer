---
name: thread-dump
description: Capture a live thread dump from a running JVM process and analyze it for deadlocks, contention, pool issues, and framework-specific problems. Use this skill when users want to debug a hanging JVM, investigate thread contention, capture a thread dump, or diagnose a slow/unresponsive Java application. Also trigger when users mention jstack, jcmd, thread states, or deadlocks.
user_invocable: true
usage: /thread-dump [PID]
arguments:
  - name: PID
    description: "JVM process ID. If omitted, list available processes and ask."
    required: false
---

# Thread Dump — Live Capture + Analysis

You are a JVM thread dump analysis expert. Your task is to capture a live thread dump from a running JVM process and produce a structured, actionable analysis report.

Production thread dumps can be thousands of lines long. The dump parser compresses them into ~200 structured lines — always use it.

## Locating Scripts

This skill's scripts are in the `scripts/` directory relative to the plugin root. To find them, look for the `DumpParser.java` and `dump-collector.sh`/`dump-collector.ps1` files near this skill file. The plugin root is typically two levels up from this SKILL.md (e.g., if this file is at `skills/thread-dump/SKILL.md`, the scripts are at `../../scripts/`).

On **macOS/Linux**, use the bash collector: `bash <plugin-root>/scripts/dump-collector.sh`
On **Windows**, use the PowerShell collector: `powershell -File <plugin-root>/scripts/dump-collector.ps1`
The **parser** is cross-platform: `java <plugin-root>/scripts/DumpParser.java`

## Procedure

### Step 1: Identify Target Process

If a PID was provided, use it directly. Otherwise, list running JVM processes:

**macOS/Linux:**
```bash
bash <plugin-root>/scripts/dump-collector.sh list
```
**Windows:**
```powershell
powershell -File <plugin-root>/scripts/dump-collector.ps1 list
```

Present the process list and ask which one to analyze. If only one JVM is running, confirm before proceeding.

### Step 2: Capture Thread Dump

**macOS/Linux:**
```bash
bash <plugin-root>/scripts/dump-collector.sh capture <PID>
```
**Windows:**
```powershell
powershell -File <plugin-root>/scripts/dump-collector.ps1 capture <PID>
```

The script outputs the path to the captured dump file.

### Step 3: Parse the Dump (CRITICAL — always do this)

**macOS/Linux:**
```bash
bash <plugin-root>/scripts/run-parser.sh <dump-file-path>
```
**Windows:**
```powershell
powershell -File <plugin-root>/scripts/run-parser.ps1 <dump-file-path>
```

These wrappers automatically find a suitable JDK (>= 11), searching PATH, JAVA_HOME, ~/.jdks, and common install locations.

This compresses the raw dump (potentially thousands of lines) into ~200 lines of structured sections:
- **DUMP METADATA** — timestamp, JVM version, PID, thread count
- **THREAD STATE SUMMARY** — counts per state
- **THREAD POOLS** — identified pools with per-pool state breakdown
- **DEADLOCKS** — JVM-detected deadlocks
- **BLOCKED THREAD CLUSTERS** — threads grouped by common wait point
- **LOCK OWNERS** — threads holding locks
- **NOTABLE THREADS** — up to 20 RUNNABLE threads with stack traces

Analyze the parser output, NOT the raw dump file. Only read the raw dump if you need to investigate a specific thread in detail.

### Step 4: Analyze

Work through the parser output systematically:

1. **Thread State Distribution** — Calculate percentages. BLOCKED > 10% is serious. (Reference: `skills/thread-dump/references/thread-states.md`)
2. **Deadlocks** — From DEADLOCKS section. Always CRITICAL if present.
3. **Blocked Thread Clusters** — Cluster size, wait target, lock holder.
4. **Thread Pool Health** — Any pool with 0 idle? All BLOCKED?
5. **Lock Contention** — Which lock holders block the most threads?
6. **Framework-Specific** — Detect framework from thread names. (Reference: `skills/thread-dump/references/spring-thread-patterns.md`)
7. **I/O Issues** — RUNNABLE threads at `SocketInputStream.read` = missing timeouts.

Severity:
- **CRITICAL** — Deadlocks, >30% BLOCKED, pool exhaustion
- **WARNING** — 10–30% BLOCKED, suboptimal pools, missing timeouts
- **INFO** — Default configs that could be improved

### Step 5: Report

```markdown
## Thread Dump Analysis Report

### Metadata
| Field | Value |
|---|---|
| Timestamp | <from parser> |
| JVM | <version> |
| PID | <pid> |
| Threads | <total> total (<daemon> daemon) |
| Application | <main class> |

### Thread State Distribution
| State | Count | Percentage | Assessment |
|---|---|---|---|

### Thread Pool Health
| Pool | Size | Busy | Idle | Blocked | Assessment |
|---|---|---|---|---|---|

### Deadlocks
NONE DETECTED — or deadlock chain from parser.

### Contention Hotspots
| Severity | Lock / Monitor | Waiting | Holder | Duration Est. |
|---|---|---|---|---|

### Blocked Thread Clusters
Per cluster from parser: count, wait point, lock info, representative stack.
Strip proxy class names.

### Framework-Specific Findings
| Severity | Finding | Detail |
|---|---|---|

### Top 3 Actions
1. **[SEVERITY]** <action> — <why> — <concrete config/code fix>
2. **[SEVERITY]** <action> — <why> — <concrete config/code fix>
3. **[SEVERITY]** <action> — <why> — <concrete config/code fix>
```

## Important Notes

- Always run the parser first — it's the key differentiator for large dumps
- The dump file is saved in `.thread-necromancer/dumps/` — mention this path
- Strip proxy class names, provide exact config properties in fixes
- Detect framework from thread names, apply relevant checks only
