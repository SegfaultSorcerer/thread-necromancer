# Common Thread Dump Patterns

> These patterns apply to **any JVM application** — Spring Boot, Quarkus, Micronaut, Dropwizard, Vert.x, or plain Java.
> Framework-specific configuration examples are provided where applicable.

## 1. Connection Pool Exhaustion

**Signature:**
Many threads WAITING at `HikariPool.getConnection()`, `C3P0PooledConnectionPoolManager.checkout()`, or `AgroalConnectionPool.getConnection()`.
```
java.lang.Thread.State: WAITING (parking)
  at com.zaxxer.hikari.pool.HikariPool.getConnection(HikariPool.java:181)
```

**Root Cause:**
All database connections are in use. Incoming requests queue up waiting for a free connection.

**Common Triggers:**
- Pool size too small for request volume
- Long-running queries holding connections
- Transaction boundaries too wide — holding connection during non-DB work (HTTP calls, file I/O)
- N+1 query patterns consuming connections longer than necessary
- Connection leak (connection not returned to pool)

**Fix (General — HikariCP config):**
```properties
# Increase pool size (rule of thumb: connections = (CPU cores * 2) + disk spindles)
maximumPoolSize=20
# Add connection timeout to fail fast instead of waiting forever
connectionTimeout=5000
# Detect leaks
leakDetectionThreshold=30000
```

**Fix (Spring Boot):**
```yaml
spring.datasource.hikari.maximum-pool-size: 20
spring.datasource.hikari.connection-timeout: 5000
spring.datasource.hikari.leak-detection-threshold: 30000
```

**Fix (Quarkus — Agroal):**
```properties
quarkus.datasource.jdbc.max-size=20
quarkus.datasource.jdbc.acquisition-timeout=5S
```

**Fix (Micronaut):**
```yaml
datasources.default.maximumPoolSize: 20
datasources.default.connectionTimeout: 5000
```

**Code Fix:**
- Move non-DB operations outside transaction boundaries
- Fix N+1 queries with JOIN FETCH, `@EntityGraph`, or batch fetching
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
- If using DI: use request-scoped beans if the synchronized state is per-request
- Consider lock striping for map-like structures
- Consider `StampedLock` for read-heavy workloads

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

**Fix (Java HttpClient — JDK 11+):**
```java
HttpClient client = HttpClient.newBuilder()
    .connectTimeout(Duration.ofSeconds(3))
    .build();
HttpRequest request = HttpRequest.newBuilder(uri)
    .timeout(Duration.ofSeconds(5))
    .build();
```

**Fix (OkHttp):**
```java
OkHttpClient client = new OkHttpClient.Builder()
    .connectTimeout(3, TimeUnit.SECONDS)
    .readTimeout(5, TimeUnit.SECONDS)
    .writeTimeout(5, TimeUnit.SECONDS)
    .build();
```

**Fix (Apache HttpClient):**
```java
RequestConfig config = RequestConfig.custom()
    .setConnectTimeout(Timeout.ofSeconds(3))
    .setResponseTimeout(Timeout.ofSeconds(5))
    .build();
```

**Fix (Spring RestTemplate):**
```yaml
spring.rest-template.connect-timeout: 3000
spring.rest-template.read-timeout: 5000
```

**Fix (Quarkus REST Client):**
```properties
quarkus.rest-client."com.example.MyClient".connect-timeout=3000
quarkus.rest-client."com.example.MyClient".read-timeout=5000
```

**Also consider:** Circuit breaker (Resilience4j, MicroProfile Fault Tolerance, or Vert.x circuit breaker) to fail fast when external service is down.

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

**Fix — increase pool size (but also fix the root cause):**

| Server | Configuration |
|---|---|
| Tomcat (Spring Boot) | `server.tomcat.threads.max: 400` |
| Tomcat (standalone) | `maxThreads="400"` in `server.xml` Connector |
| Undertow (WildFly/Quarkus) | `quarkus.http.io-threads` / `io.undertow.worker-threads` |
| Jetty | `maxThreads` in `QueuedThreadPool` |
| Netty (Vert.x/Micronaut) | Event loop — scale via worker pool instead |

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

## 7. Async / Executor Pool Starvation

**Signature:**
Unbounded thread creation (thread count grows without limit), or all threads in a fixed pool are busy with tasks queued.

Common thread name patterns:
- `pool-N-thread-N` — generic `ExecutorService`
- `task-N` / `SimpleAsyncTaskExecutor-N` — Spring `@Async`
- `executor-thread-N` — Quarkus/MicroProfile managed executor
- `vert.x-worker-thread-N` — Vert.x worker pool

**Root Cause:**
- `Executors.newCachedThreadPool()` creates threads without bound under sustained load
- Spring's default `SimpleAsyncTaskExecutor` creates a new thread per task (no pooling!)
- Fixed pool too small for the workload, tasks back up in queue or get rejected

**Fix (Plain Java):**
```java
ExecutorService executor = new ThreadPoolExecutor(
    10, 50, 60L, TimeUnit.SECONDS,
    new LinkedBlockingQueue<>(100),
    new ThreadPoolExecutor.CallerRunsPolicy());
```

**Fix (Spring Boot):**
```yaml
spring.task.execution.pool.core-size: 10
spring.task.execution.pool.max-size: 50
spring.task.execution.pool.queue-capacity: 100
```

**Fix (Quarkus):**
```properties
quarkus.thread-pool.max-threads=50
quarkus.thread-pool.queue-size=100
```

**Fix (Vert.x):**
```java
DeploymentOptions options = new DeploymentOptions().setWorkerPoolSize(20);
```
