# Spring Thread Patterns Reference

## Thread Name → Component Mapping

| Thread Name Pattern | Component | Default Pool Size |
|---|---|---|
| `http-nio-*-exec-*` | Tomcat NIO connector | 200 |
| `http-nio-*-Poller` | Tomcat NIO selector | 1–2 |
| `http-nio-*-Acceptor` | Tomcat connection acceptor | 1 |
| `scheduling-*` | @Scheduled (Spring default) | **1 (!)** |
| `task-*` | @Async (Spring default pool) | 8 |
| `taskScheduler-*` | Spring TaskScheduler | configurable |
| `HikariPool-*-housekeeper` | HikariCP maintenance | 1 |
| `HikariPool-*-connection-*` | HikariCP connections | pool size |
| `lettuce-nioEventLoop-*` | Redis Lettuce client | CPU cores |
| `reactor-http-nio-*` | WebFlux/Netty event loop | CPU cores |
| `parallel-*` | Project Reactor parallel | CPU cores |
| `boundedElastic-*` | Project Reactor blocking ops | 10 x CPU cores |
| `Eureka-*` | Eureka service discovery | varies |
| `ForkJoinPool.commonPool-*` | JDK common pool | CPU cores - 1 |
| `ForkJoinPool-*-worker-*` | Custom ForkJoinPool | configurable |
| `C3P0PooledConnectionPool*` | C3P0 connection pool | pool size |
| `oracle.jdbc.*` | Oracle JDBC driver threads | varies |
| `pool-*-thread-*` | Generic ExecutorService | varies |
| `AsyncExecutor-*` | Custom async executor | varies |

## Spring Proxy Detection

When analyzing stack traces, these frames indicate Spring proxies wrapping the actual business logic:

| Frame Pattern | Proxy Type | Implications |
|---|---|---|
| `$$EnhancerBySpringCGLIB$$` | CGLIB proxy | Extract real class name before `$$` |
| `$$SpringCGLIB$$` | CGLIB proxy (Spring 6+) | Same as above, newer naming |
| `CglibAopProxy` | AOP advice | An aspect/interceptor is being applied |
| `TransactionInterceptor` | @Transactional | Transaction boundary — connection likely held |
| `MethodBeforeAdviceInterceptor` | @Before advice | Pre-method aspect |
| `AfterReturningAdviceInterceptor` | @AfterReturning | Post-method aspect |
| `ExposeInvocationInterceptor` | AOP infrastructure | Can be ignored — AOP plumbing |
| `org.springframework.security.access.intercept` | @PreAuthorize/@Secured | Security check proxy |
| `JdkDynamicAopProxy` | JDK dynamic proxy | Interface-based proxy |

**When reporting:** Strip proxy class names and report the underlying business class. E.g., `OrderService$$EnhancerBySpringCGLIB$$a1b2c3.placeOrder()` → report as `OrderService.placeOrder()` (CGLIB proxy).

## Common Spring Pitfalls in Thread Dumps

### 1. @Scheduled Default Pool (Size = 1)

**What it looks like:**
Only one `scheduling-*` thread exists. If a scheduled task takes longer than its interval, other tasks queue behind it.

**Detection:**
- Thread pool section shows `scheduling-1` with only 1 thread
- That thread is doing actual work (not parked)

**Fix:**
```yaml
spring.task.scheduling.pool.size: 5
```
```java
@Configuration
public class SchedulingConfig implements SchedulingConfigurer {
    @Override
    public void configureTasks(ScheduledTaskRegistrar registrar) {
        registrar.setScheduler(Executors.newScheduledThreadPool(5));
    }
}
```

### 2. @Transactional Holding Connection During Non-DB I/O

**What it looks like:**
Thread is RUNNABLE at `SocketInputStream.read()` or similar I/O, but the stack shows `TransactionInterceptor` earlier in the call chain. The thread holds a database connection while waiting for an external HTTP call.

**Detection:**
- Stack trace contains both `TransactionInterceptor` and `SocketInputStream.read`
- Or: `TransactionInterceptor` + any non-DB blocking call

**Fix:**
- Move the external call outside the `@Transactional` boundary
- Split the method: DB work in one @Transactional method, external call separate
- Use `@Transactional` only on the methods that actually need it

### 3. Open-in-View (Lazy Loading in Controller Layer)

**What it looks like:**
Stack traces show Hibernate lazy initialization frames (`LazyInitializationException` handler or `AbstractLazyInitializer.initialize()`) in controller/serialization code, not in service layer.

**Detection:**
- `org.hibernate.proxy.AbstractLazyInitializer` frames above controller/serializer frames
- Multiple short DB queries triggered during JSON serialization

**Impact:**
- Database connections held longer than necessary (through entire request lifecycle)
- N+1 queries during serialization
- Connection pool pressure

**Fix:**
```yaml
spring.jpa.open-in-view: false
```
Then fix `LazyInitializationException` by using:
- `JOIN FETCH` in queries
- `@EntityGraph` annotations
- DTOs instead of returning entities directly

### 4. WebFlux Blocking on Event Loop

**What it looks like:**
`reactor-http-nio-*` threads doing blocking operations (JDBC, file I/O, `Thread.sleep`).

**Detection:**
- `reactor-http-nio-*` thread state is RUNNABLE at blocking I/O
- Or: Reactor's `BlockHound` violation messages in logs

**Fix:**
- Offload blocking operations to `boundedElastic` scheduler: `.subscribeOn(Schedulers.boundedElastic())`
- Use reactive drivers (R2DBC, reactive Redis, reactive MongoDB)
