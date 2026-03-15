# Framework Thread Patterns Reference

## Thread Name → Component Mapping

### Generic JVM / Common Libraries

| Thread Name Pattern | Component | Default Pool Size |
|---|---|---|
| `ForkJoinPool.commonPool-*` | JDK common pool | CPU cores - 1 |
| `ForkJoinPool-*-worker-*` | Custom ForkJoinPool | configurable |
| `pool-*-thread-*` | Generic `ExecutorService` | varies |
| `HikariPool-*-housekeeper` | HikariCP maintenance | 1 |
| `HikariPool-*-connection-*` | HikariCP connections | pool size |
| `C3P0PooledConnectionPool*` | C3P0 connection pool | pool size |
| `oracle.jdbc.*` | Oracle JDBC driver threads | varies |
| `mysql-cj-abandoned-connection-cleanup` | MySQL Connector/J | 1 |
| `Abandoned connection cleanup thread` | MySQL Connector/J (older) | 1 |
| `lettuce-nioEventLoop-*` | Redis Lettuce client | CPU cores |
| `redisson-netty-*` | Redisson Redis client | varies |
| `kafka-producer-network-*` | Kafka producer | 1 per producer |
| `kafka-coordinator-*` | Kafka consumer coordinator | 1 per consumer |
| `elasticsearch-*` | Elasticsearch client | varies |
| `RMI *` | Java RMI / JMX | varies |
| `GC Daemon` / `G1 *` / `ZGC *` | Garbage collector | JVM managed |
| `Signal Dispatcher` | JVM signal handling | 1 |
| `Finalizer` | Object finalization | 1 |
| `Reference Handler` | Reference processing | 1 |

### Tomcat (Spring Boot, standalone)

| Thread Name Pattern | Component | Default Pool Size |
|---|---|---|
| `http-nio-*-exec-*` | Tomcat NIO connector | 200 |
| `http-nio-*-Poller` | Tomcat NIO selector | 1–2 |
| `http-nio-*-Acceptor` | Tomcat connection acceptor | 1 |
| `Catalina-utility-*` | Tomcat utility threads | 2 |

### Spring-Specific

| Thread Name Pattern | Component | Default Pool Size |
|---|---|---|
| `scheduling-*` | @Scheduled (Spring default) | **1 (!)** |
| `task-*` | @Async (Spring default pool) | 8 |
| `taskScheduler-*` | Spring TaskScheduler | configurable |
| `AsyncExecutor-*` | Custom async executor | varies |

### Spring WebFlux / Project Reactor

| Thread Name Pattern | Component | Default Pool Size |
|---|---|---|
| `reactor-http-nio-*` | WebFlux/Netty event loop | CPU cores |
| `parallel-*` | Project Reactor parallel | CPU cores |
| `boundedElastic-*` | Project Reactor blocking ops | 10 x CPU cores |

### Quarkus

| Thread Name Pattern | Component | Default Pool Size |
|---|---|---|
| `executor-thread-*` | Quarkus worker pool | 200 |
| `vert.x-eventloop-thread-*` | Vert.x event loop | 2 x CPU cores |
| `vert.x-worker-thread-*` | Vert.x worker pool | 20 |
| `quarkus-scheduler-*` | Quarkus @Scheduled | configurable |
| `arjuna-*` | Narayana transaction manager | varies |

### Micronaut

| Thread Name Pattern | Component | Default Pool Size |
|---|---|---|
| `default-nioEventLoopGroup-*` | Netty event loop | CPU cores |
| `io-executor-thread-*` | Micronaut I/O pool | configurable |
| `scheduled-executor-thread-*` | Micronaut @Scheduled | configurable |

### Vert.x (standalone)

| Thread Name Pattern | Component | Default Pool Size |
|---|---|---|
| `vert.x-eventloop-thread-*` | Event loop | 2 x CPU cores |
| `vert.x-worker-thread-*` | Worker pool | 20 |
| `vert.x-internal-blocking-*` | Internal blocking ops | 20 |

### Jetty

| Thread Name Pattern | Component | Default Pool Size |
|---|---|---|
| `qtp*` | Jetty QueuedThreadPool | 200 |
| `Jetty-*` | Jetty internal | varies |

### Undertow (WildFly)

| Thread Name Pattern | Component | Default Pool Size |
|---|---|---|
| `XNIO-*-task-*` | Undertow worker threads | CPU cores x 8 |
| `XNIO-*-I/O-*` | Undertow I/O threads | CPU cores |
| `XNIO-*-Accept` | Connection acceptor | 1 |

### Netflix / Spring Cloud

| Thread Name Pattern | Component | Default Pool Size |
|---|---|---|
| `Eureka-*` | Eureka service discovery | varies |
| `Hystrix-*` | Hystrix circuit breaker pool | 10 |
| `RxIoScheduler-*` | RxJava I/O scheduler | varies |
| `RxComputationScheduler-*` | RxJava computation scheduler | CPU cores |

---

## Proxy / Wrapper Detection

When analyzing stack traces, these frames indicate proxy layers wrapping the actual business logic. Strip them when reporting to show the real class.

### Spring

| Frame Pattern | Proxy Type |
|---|---|
| `$$EnhancerBySpringCGLIB$$` / `$$SpringCGLIB$$` | CGLIB proxy — extract real class name before `$$` |
| `CglibAopProxy` | AOP advice being applied |
| `TransactionInterceptor` | @Transactional boundary — connection likely held |
| `JdkDynamicAopProxy` | Interface-based proxy |
| `ExposeInvocationInterceptor` | AOP plumbing — can be ignored |

### CDI (Quarkus, WildFly)

| Frame Pattern | Proxy Type |
|---|---|
| `_Subclass` / `_ClientProxy` | Quarkus CDI subclass proxy |
| `Weld$Proxy$` | Weld CDI proxy (WildFly, generic CDI) |
| `$$_WeldSubclass` | Weld enhanced subclass |

### General

| Frame Pattern | Proxy Type |
|---|---|
| `$Proxy` / `com.sun.proxy.$Proxy` | JDK dynamic proxy |
| `$$FastClassByGuice$$` | Guice AOP proxy |
| `ByteBuddy` / `$auxiliary` | ByteBuddy generated class |
| `javassist` | Javassist proxy (Hibernate, older frameworks) |

**When reporting:** Always strip proxy class names and report the underlying business class.

---

## Framework-Specific Pitfalls

### Spring: @Scheduled Default Pool (Size = 1)

Only one `scheduling-*` thread. All tasks queue behind each other.

**Fix:** `spring.task.scheduling.pool.size: 5`

### Spring: @Transactional Holding Connection During I/O

Stack shows `TransactionInterceptor` + `SocketInputStream.read` — DB connection held during HTTP call.

**Fix:** Move external calls outside `@Transactional` boundaries.

### Spring: Open-in-View Lazy Loading

`spring.jpa.open-in-view: true` (default) holds DB connection through entire request for lazy loading.

**Fix:** Set `spring.jpa.open-in-view: false`, use `JOIN FETCH` or DTOs.

### Spring WebFlux / Vert.x: Blocking on Event Loop

`reactor-http-nio-*` or `vert.x-eventloop-thread-*` doing blocking I/O (JDBC, file I/O, `Thread.sleep`).

**Fix (WebFlux):** `.subscribeOn(Schedulers.boundedElastic())`
**Fix (Vert.x):** Use `executeBlocking()` or worker verticles.

### Quarkus: Blocking on I/O Thread

`executor-thread-*` blocked on reactive endpoint — Quarkus reactive routes must not block.

**Fix:** Use `@Blocking` annotation or offload to worker pool with `Uni.emitOn()`.
