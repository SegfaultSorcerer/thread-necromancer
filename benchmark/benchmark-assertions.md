# Benchmark Assertions

## `/thread-dump` Assertions (~25)

### Detection
1. Detects connection pool exhaustion (threads WAITING at HikariPool.getConnection)
2. Reports correct HikariCP pool name
3. Reports cluster size for connection pool waiters
4. Detects synchronized bottleneck (threads BLOCKED at LegacySynchronizedService)
5. Identifies lock holder thread for synchronized bottleneck
6. Reports waiter count for synchronized bottleneck
7. Detects deadlock if present (JVM-reported)
8. Reports deadlock chain (which threads, which locks)
9. Reports correct Tomcat thread pool name and size
10. Reports correct @Scheduled pool (scheduling-1, size 1)
11. Reports correct @Async pool name and size
12. Identifies leaked threads (leaked-thread-* pattern)

### Spring-Specific
13. Identifies @Scheduled pool size = 1 as WARNING
14. Identifies @Transactional holding connection during I/O
15. Reports open-in-view as INFO finding
16. Strips CGLIB proxy class names when present

### Analysis Quality
17. Thread state distribution percentages are correct
18. BLOCKED percentage flagged as concerning (> 10%)
19. Severity table includes CRITICAL/WARNING/INFO ratings
20. Produces Top 3 Actions
21. Actions include concrete config YAML suggestions
22. Actions include code fix suggestions where applicable
23. Output follows specified table format

### Metadata
24. Reports JVM version correctly
25. Reports total thread count correctly

## `/thread-watch` Assertions (~20)

### Stuck Thread Detection
1. Identifies threads stuck in same state across all dumps
2. Reports stuck thread names correctly
3. Estimates stuck duration (dumps-1 * interval)
4. BLOCKED stuck threads rated CRITICAL

### Progression Detection
5. Identifies threads that changed state between dumps
6. Reports state transition sequence per thread
7. Progressing threads rated as healthy

### Thread Count Drift
8. Reports total thread count per dump
9. Reports per-pool thread count per dump
10. Detects growing thread count (leaked-thread-* pattern)
11. Growing count flagged as WARNING

### Contention Trend
12. Reports blocked cluster sizes per dump
13. Detects growing cluster = worsening contention
14. Detects stable cluster = steady bottleneck
15. Detects shrinking cluster = resolving

### Lock Holder Stability
16. Identifies same lock holder across all dumps
17. Estimates lock hold duration

### Report Quality
18. Per-dump summary table present
19. Temporal comparison between dumps
20. Top 3 Actions present

## `/thread-compare` Assertions (~15)

### Thread Matching
1. Matches threads by name across both dumps
2. Reports threads that changed state
3. Reports state transitions correctly (before → after)
4. Reports new threads (in dump 2 only)
5. Reports disappeared threads (in dump 1 only)

### Aggregate Changes
6. Reports total thread count delta
7. Reports per-pool thread count delta
8. Reports blocked cluster size changes
9. Detects growing cluster = worsening
10. Detects shrinking cluster = resolving

### Lock Changes
11. Reports lock holder changes between dumps
12. Identifies new lock contention points

### Report Quality
13. Comparison table format correct
14. Summary narrative present
15. Recommended actions present

## `/thread-analyze` Assertions

Same as `/thread-dump` assertions (operates on a file instead of live capture).

## Benchmark Targets

| Skill | Target (with skill) | Expected baseline | Expected delta |
|---|---|---|---|
| /thread-dump | > 95% | ~75-80% | +15-20% |
| /thread-watch | > 95% | ~70-75% | +20-25% |
| /thread-compare | > 90% | ~65-70% | +20-25% |
| /thread-analyze | Same as /thread-dump | Same | Same |
