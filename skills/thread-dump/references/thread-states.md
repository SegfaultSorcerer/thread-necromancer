# JVM Thread States Reference

## State Definitions

| State | Description | What It Means |
|---|---|---|
| `NEW` | Thread created but not yet started | Rare in dumps — usually a bug if seen |
| `RUNNABLE` | Executing or ready to execute | Includes threads doing I/O (socket read, file I/O) |
| `BLOCKED` | Waiting to acquire a monitor lock | Contention — another thread holds the lock |
| `WAITING` | Waiting indefinitely for another thread | `Object.wait()`, `LockSupport.park()`, `Thread.join()` |
| `TIMED_WAITING` | Waiting with a timeout | `Thread.sleep()`, `Object.wait(timeout)`, `LockSupport.parkNanos()` |
| `TERMINATED` | Thread has completed execution | Rare in dumps — thread about to be cleaned up |

## Healthy State Distribution (Spring Boot under moderate load)

| State | Healthy Range | Red Flag Threshold |
|---|---|---|
| RUNNABLE | 5–20% | > 50% with same stack = hot loop |
| WAITING | 20–40% | > 80% = all threads idle or stuck |
| TIMED_WAITING | 30–50% | Rarely a problem on its own |
| BLOCKED | < 5% | > 10% = serious lock contention |

## Red Flags

### BLOCKED > 10%
Serious lock contention. Find the lock holder and analyze why it's holding the lock so long.
Common causes: synchronized methods on hot paths, database operations inside synchronized blocks.

### All threads in one pool WAITING
Pool is idle — either no work is arriving, or an upstream component is the bottleneck.
Check: Is the load balancer sending traffic? Is a gateway/proxy blocking?

### Many RUNNABLE doing the same thing
Hot loop or CPU-bound operation. Check if threads are in:
- `java.util.regex` — catastrophic backtracking
- `java.util.HashMap.get` — concurrent modification (no ConcurrentHashMap)
- `java.security.SecureRandom` — entropy starvation
- Custom loops without yields

### Thread count growing over time
Thread leak. Common causes:
- `new Thread().start()` without pooling
- `Executors.newCachedThreadPool()` under sustained load
- Unbounded `@Async` with `SimpleAsyncTaskExecutor`
- Connections not being returned to pool

### RUNNABLE at SocketInputStream.read
Thread is blocked on I/O but JVM reports it as RUNNABLE (JVM doesn't distinguish CPU-runnable from I/O-blocked).
If many threads are here, an external service is slow or has no timeout configured.

## Key Frames to Recognize

| Frame | Meaning |
|---|---|
| `Unsafe.park` / `LockSupport.park` | Thread parked — look at what it's waiting for |
| `Object.wait` | Classic monitor wait — look for notify/notifyAll |
| `SocketInputStream.socketRead0` | Blocking socket read — check timeouts |
| `FileInputStream.readBytes` | Blocking file I/O |
| `SelectorImpl.select` | NIO selector — normal for event loops |
| `EPoll.wait` / `KQueue.poll` | Native I/O multiplexing — normal for Netty/NIO |
| `Thread.sleep` | Explicit sleep — check if this is in a polling loop |
| `ForkJoinPool.awaitWork` | Idle ForkJoinPool worker — normal |
| `ThreadPoolExecutor.getTask` | Idle pool worker waiting for work — normal |
