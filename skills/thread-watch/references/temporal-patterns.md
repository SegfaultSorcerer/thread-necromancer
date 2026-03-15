# Temporal Analysis Patterns

When analyzing multiple thread dumps captured over time, look for these patterns.

## Stuck Thread Detection

**Criteria:** Same thread name + same state + same top 3 stack frames across 3+ dumps.

**What it means:** The thread is truly blocked, not just momentarily paused. A thread that appears BLOCKED in a single dump might just be experiencing brief contention, but if it's in the same position across multiple dumps seconds apart, it's stuck.

**Duration estimate:** `(number_of_dumps - 1) × interval_seconds` = minimum time stuck.

**Severity:**
- Stuck BLOCKED thread → CRITICAL (holding up other threads)
- Stuck RUNNABLE at I/O → WARNING (waiting for external response)
- Stuck WAITING → depends on what it's waiting for

## Progression Detection

**Criteria:** Thread changed state OR moved in call stack between dumps.

**What it means:** The thread is making progress, even if slowly. This is healthy behavior.

**Useful for:** Distinguishing "slow but working" from "completely stuck."

## Oscillating Threads

**Criteria:** Thread alternates between RUNNABLE and WAITING/BLOCKED across dumps.

**What it means:** Possible lock contention — thread acquires lock, does work, releases, immediately contends again. Also seen with polling patterns.

**Detection:** Track state sequence per thread: R-W-R-W = oscillating, R-R-R = stuck runnable, W-W-W = stuck waiting.

## Thread Count Drift

**Criteria:** Total thread count or per-pool thread count changes across dumps.

| Trend | Meaning | Severity |
|---|---|---|
| Growing | Thread leak or runaway pool | WARNING → CRITICAL if unbounded |
| Shrinking | Pool scaling down, or threads dying | INFO (usually healthy) |
| Stable | Normal operation | OK |

**Key pools to watch:**
- `SimpleAsyncTaskExecutor` threads growing = thread leak (no pooling)
- `pool-*-thread-*` growing = possible `newCachedThreadPool` under load
- Tomcat threads growing toward max = increasing load

## Contention Trend

**Criteria:** Size of blocked thread clusters across dumps.

| Trend | Meaning | Action |
|---|---|---|
| Growing clusters | Contention worsening, bottleneck deepening | CRITICAL — investigate lock holder |
| Shrinking clusters | Contention resolving (transient issue) | INFO — may self-resolve |
| Stable large clusters | Steady-state bottleneck | WARNING — needs architectural fix |
| Stable small clusters | Normal minor contention | OK |

## Lock Holder Stability

**Criteria:** Same thread holds the same lock across all dumps.

**What it means:** Long-running critical section. The lock holder is doing something slow while holding the lock.

**Common causes:**
- Database query inside synchronized block
- External HTTP call inside synchronized block
- File I/O inside synchronized block
- Expensive computation inside synchronized block

**Duration estimate:** `(dumps - 1) × interval` = minimum hold time.

## New/Disappeared Threads

**Between dumps:**
- New threads appearing = thread creation (pool growth, new connections, new tasks)
- Threads disappearing = thread death (task completion, error, pool shrinking)

**Watch for:**
- Rapid thread creation without corresponding death = leak
- All threads in a pool disappearing = pool shutdown or crash
- New thread names from unexpected pools = unintended thread creation
