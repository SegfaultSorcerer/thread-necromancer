# Common Thread Dump Patterns

## 1. Connection Pool Exhaustion

**Signature:**
Many threads WAITING at `HikariPool.getConnection()` or `C3P0PooledConnectionPoolManager.checkout()`.
```
java.lang.Thread.State: WAITING (parking)
  at com.zaxxer.hikari.pool.HikariPool.getConnection(HikariPool.java:181)
```

**Root Cause:**
All database connections are in use. Incoming requests queue up waiting for a free connection.

**Common Triggers:**
- Pool size too small for request volume
- Long-running queries holding connections
- `@Transactional` methods doing non-DB work (HTTP calls, file I/O) while holding a connection
- N+1 query patterns consuming connections longer than necessary
- Connection leak (connection not returned to pool)

**Fix:**
```yaml
# Increase pool size (rule of thumb: connections = (CPU cores * 2) + disk spindles)
spring.datasource.hikari.maximum-pool-size: 20
# Add connection timeout to fail fast instead of waiting forever
spring.datasource.hikari.connection-timeout: 5000
# Detect leaks
spring.datasource.hikari.leak-detection-threshold: 30000
```

**Code Fix:**
- Move non-DB operations outside `@Transactional` boundaries
- Fix N+1 queries with JOIN FETCH or `@EntityGraph`
- Ensure connections are always returned (try-with-resources for manual JDBC)

---

## 2. Synchronized Bottleneck

**Signature:**
Many threads BLOCKED at the same `synchronized` method or block.
```
java.lang.Thread.State: BLOCKED (on object monitor)
  at com.example.service.LegacyService.processOrder(LegacyService.java:89)
  - waiting to lock <0x000000076cd40120> (a com.example.service.LegacyService)
```
One thread is RUNNABLE holding the lock:
```
  - locked <0x000000076cd40120> (a com.example.service.LegacyService)
```

**Root Cause:**
A `synchronized` method/block on a shared object serializes all access. Under concurrent load, threads queue up.

**Fix:**
- Replace `synchronized` with `ReentrantLock` (allows tryLock with timeout)
- Use `ConcurrentHashMap.computeIfAbsent()` instead of `synchronized` + `HashMap`
- Reduce scope of synchronized block to minimum critical section
- Use `@Scope("prototype")` if the synchronized state is per-request
- Consider lock striping for map-like structures

---

## 3. External Service Timeout

**Signature:**
Threads RUNNABLE at socket read with no progress:
```
java.lang.Thread.State: RUNNABLE
  at java.net.SocketInputStream.socketRead0(Native Method)
  at com.example.client.ExternalApiClient.call(ExternalApiClient.java:45)
```

**Root Cause:**
HTTP/TCP call to external service with no timeout configured. If the external service hangs, threads accumulate here.

**Fix:**
```yaml
# RestTemplate
spring.rest-template.connect-timeout: 3000
spring.rest-template.read-timeout: 5000

# WebClient (reactive)
spring.webflux.client.connect-timeout: 3000
```

```java
// RestTemplate with timeouts
@Bean
public RestTemplate restTemplate(RestTemplateBuilder builder) {
    return builder
        .connectTimeout(Duration.ofSeconds(3))
        .readTimeout(Duration.ofSeconds(5))
        .build();
}

// OkHttp / Apache HttpClient — set connectTimeout + readTimeout + writeTimeout
```

**Also consider:** Circuit breaker (Resilience4j) to fail fast when external service is down.

---

## 4. GC-Induced Thread Suspension

**Signature:**
ALL threads appear parked/waiting simultaneously in a single dump. No threads are RUNNABLE.

**Root Cause:**
Thread dump was captured during a Stop-The-World (STW) GC pause. All application threads are suspended.

**How to confirm:**
- Check GC logs for long pauses at the dump timestamp
- Capture multiple dumps — if only one shows this pattern, it was a GC pause

**Fix:**
- Tune GC: switch to G1/ZGC/Shenandoah for lower pause times
- Reduce allocation rate
- Increase heap if GC is too frequent
```
-XX:+UseG1GC -XX:MaxGCPauseMillis=200
# or for ultra-low pause:
-XX:+UseZGC
```

---

## 5. Thread Pool Exhaustion

**Signature:**
All threads in a pool are busy (RUNNABLE or BLOCKED), none WAITING for work:
```
pool: http-nio-8080-exec
  total: 200, RUNNABLE: 45, WAITING: 0, BLOCKED: 155, TIMED_WAITING: 0
```

**Root Cause:**
Request rate exceeds processing capacity. All worker threads are occupied.

**Fix:**
```yaml
# Increase Tomcat thread pool (but also fix the root cause)
server.tomcat.threads.max: 400
# Set a minimum to avoid cold-start delays
server.tomcat.threads.min-spare: 20
# Set accept count (queue size before rejecting)
server.tomcat.accept-count: 100
```

**Root causes to investigate:**
- Slow database queries (check connection pool)
- Slow external service calls (check timeouts)
- Lock contention (check BLOCKED threads)
- CPU-intensive operations on request threads

---

## 6. Deadlock

**Signature:**
JVM explicitly reports: `"Found one Java-level deadlock:"`
```
Found one Java-level deadlock:
=============================
"Thread-1":
  waiting to lock monitor 0x00007f8b1c004e18 (object 0x000000076ab30, a com.example.ServiceA)
  which is held by "Thread-2"
"Thread-2":
  waiting to lock monitor 0x00007f8b1c004f28 (object 0x000000076cd40, a com.example.ServiceB)
  which is held by "Thread-1"
```

**Root Cause:**
Two or more threads each hold a lock the other needs, forming a circular dependency.

**Fix:**
- Establish a global lock ordering (always acquire locks in the same order)
- Use `tryLock(timeout)` instead of `synchronized`
- Reduce lock granularity
- Use lock-free data structures where possible

---

## 7. @Async Pool Starvation

**Signature:**
`SimpleAsyncTaskExecutor` creating unlimited threads (thread count grows unbounded), or
`ThreadPoolTaskExecutor` fully occupied with all tasks queued.

Thread names: `task-1`, `task-2`, ... or `SimpleAsyncTaskExecutor-1`, `SimpleAsyncTaskExecutor-2`, ...

**Root Cause:**
- Default `SimpleAsyncTaskExecutor` creates a new thread per task (no pooling!)
- `ThreadPoolTaskExecutor` with small pool and slow async tasks

**Fix:**
```java
@Configuration
@EnableAsync
public class AsyncConfig implements AsyncConfigurer {
    @Override
    public Executor getAsyncExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(10);
        executor.setMaxPoolSize(50);
        executor.setQueueCapacity(100);
        executor.setThreadNamePrefix("async-");
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.initialize();
        return executor;
    }
}
```

```yaml
spring.task.execution.pool.core-size: 10
spring.task.execution.pool.max-size: 50
spring.task.execution.pool.queue-capacity: 100
```
