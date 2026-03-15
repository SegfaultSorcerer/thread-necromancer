# Thread Dump Diff Strategies

## Matching Threads Across Dumps

Threads are matched by **thread name**, which is stable across dumps for pooled threads.

**Matching rules:**
1. Exact name match (e.g., `http-nio-8080-exec-42` → `http-nio-8080-exec-42`)
2. Thread names are unique within a single dump
3. If a thread name exists in dump 1 but not dump 2, it was destroyed
4. If a thread name exists in dump 2 but not dump 1, it was created

## What to Compare

### Per-Thread Changes
For each matched thread:
- **State change:** RUNNABLE → BLOCKED, WAITING → RUNNABLE, etc.
- **Stack change:** Did the thread move in its call stack? (top frame different = progress)
- **Lock change:** Did the thread acquire or release locks?

### Aggregate Changes
- **Thread count delta:** total, per pool, per state
- **Blocked cluster size change:** more or fewer threads in each cluster
- **Lock holder changes:** different thread now holds the lock
- **New pools appearing / pools disappearing**

## Reporting Format

### State Transition Table
```
Thread Name               | Dump 1 State    | Dump 2 State    | Assessment
--------------------------|-----------------|-----------------|------------------
http-nio-8080-exec-42     | RUNNABLE        | BLOCKED         | Became blocked
http-nio-8080-exec-17     | BLOCKED         | RUNNABLE        | Unblocked
scheduling-1              | TIMED_WAITING   | TIMED_WAITING   | No change (idle)
```

### Thread Count Delta
```
Pool                     | Dump 1 | Dump 2 | Delta | Assessment
-------------------------|--------|--------|-------|------------------
http-nio-8080-exec       | 200    | 200    | 0     | Stable
task-                    | 8      | 12     | +4    | Growing (load?)
custom-pool              | 5      | 0      | -5    | Pool disappeared!
```

### Cluster Size Changes
```
Cluster (wait point)              | Dump 1 | Dump 2 | Trend
----------------------------------|--------|--------|----------
HikariPool.getConnection          | 47     | 89     | GROWING — worsening
LegacyService.processOrder        | 23     | 23     | STABLE — persistent
CacheManager.get                  | 12     | 3      | SHRINKING — resolving
```

## Interpretation Guidelines

### Healthy Signs
- Threads move between states between dumps
- Blocked clusters shrink or remain small
- Thread counts are stable
- Lock holders change (lock is being passed around)

### Unhealthy Signs
- Same threads blocked in both dumps at the same point → stuck
- Blocked clusters growing → worsening contention
- Thread counts growing unbounded → thread leak
- Same lock holder in both dumps → long-running critical section
- New threads appearing from `SimpleAsyncTaskExecutor` → no pooling
