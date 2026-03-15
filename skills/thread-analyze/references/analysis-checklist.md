# Thread Dump Analysis Checklist

Use this checklist to systematically analyze a thread dump. Work through each section in order.

## 1. Metadata Check
- [ ] What JVM version is running? (impacts available diagnostics)
- [ ] How many total threads? (baseline: Spring Boot typically 50–300)
- [ ] How many daemon vs non-daemon threads?

## 2. Thread State Distribution
- [ ] Calculate percentages for each state
- [ ] BLOCKED > 10%? → Lock contention (CRITICAL)
- [ ] RUNNABLE > 50% all doing the same thing? → Hot loop (CRITICAL)
- [ ] All threads WAITING? → Possible GC pause or no load
- [ ] Any NEW or TERMINATED? → Unusual, investigate

## 3. Deadlock Check
- [ ] Does the JVM report "Found one Java-level deadlock"? → CRITICAL
- [ ] If no JVM-detected deadlock, check for implicit cycles in lock ownership chains

## 4. Thread Pool Assessment
For each identified pool:
- [ ] Is the pool the right size for its workload?
- [ ] Are there idle threads? (healthy pool has some idle capacity)
- [ ] Are all threads busy? → Pool exhaustion risk
- [ ] Are threads BLOCKED? → Downstream bottleneck

### Key pool checks:
- [ ] **Tomcat (http-nio-exec):** All 200 busy? → Request overload or slow handlers
- [ ] **@Scheduled (scheduling-):** Only 1 thread? → Default pool, tasks will queue
- [ ] **@Async (task-):** Pool full? → Async tasks backing up
- [ ] **HikariCP:** All connections busy? → DB bottleneck
- [ ] **ForkJoinPool.commonPool:** All busy? → Parallel stream contention

## 5. Blocked Thread Clusters
- [ ] Group BLOCKED threads by the lock they're waiting on
- [ ] Identify the lock holder for each group
- [ ] What is the lock holder doing? (RUNNABLE = working, BLOCKED = also waiting)
- [ ] How many threads are affected per cluster?

## 6. Lock Contention Analysis
- [ ] Which locks have the most waiters?
- [ ] Are lock holders doing I/O while holding locks?
- [ ] Are there nested locks? (risk of deadlock)
- [ ] Is the lock on a singleton bean? (Spring default scope)

## 7. Spring-Specific Analysis
- [ ] Check @Scheduled pool size (default = 1, almost always too small)
- [ ] Check for @Transactional + external I/O (holding DB connection during HTTP call)
- [ ] Check for open-in-view lazy loading (Hibernate proxies in controller layer)
- [ ] Check for Spring proxy overhead in hot paths (CGLIB in tight loops)
- [ ] Check @Async executor configuration (default SimpleAsyncTaskExecutor = no pooling!)

## 8. I/O and External Service Analysis
- [ ] Threads at SocketInputStream.read → External service calls
- [ ] Are timeouts configured?
- [ ] How many threads are waiting on the same external endpoint?
- [ ] Is there a circuit breaker?

## 9. Severity Assessment
Rate each finding:
- **CRITICAL:** Deadlocks, >30% threads blocked, pool exhaustion with request queueing
- **WARNING:** 10–30% blocked, suboptimal pool sizes, missing timeouts
- **INFO:** Default configurations that could be improved, minor inefficiencies

## 10. Top Actions
Produce 3 prioritized, actionable recommendations:
1. Most impactful fix (addresses the most threads/biggest bottleneck)
2. Second most impactful
3. Quick win or preventive measure

Each action should include:
- What to change (specific config property or code change)
- Why (which threads/problem it addresses)
- Expected impact
