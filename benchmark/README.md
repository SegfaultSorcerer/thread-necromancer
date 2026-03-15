# thread-necromancer Benchmark

## Fixture Application

A Spring Boot 3.2 application with 8 intentional thread problems:

| # | Issue | Trigger | What to Look For |
|---|---|---|---|
| 1 | Connection Pool Exhaustion | `GET /api/issues/connection-pool` (x6) | WAITING at `HikariPool.getConnection()` |
| 2 | Synchronized Bottleneck | `GET /api/issues/synchronized/{id}` (x10) | BLOCKED at `LegacySynchronizedService.processOrder()` |
| 3 | Deadlock | `POST /api/issues/deadlock` | JVM "Found one Java-level deadlock" |
| 4 | @Scheduled Starvation | Automatic (on startup) | Single `scheduling-1` thread, tasks queued |
| 5 | Thread Leak | `POST /api/issues/thread-leak/{id}` (x10) | Growing `leaked-thread-*` count |
| 6 | External Service Timeout | `GET /api/issues/external-timeout` | RUNNABLE at `SocketInputStream.read()` |
| 7 | @Async Pool Exhaustion | `POST /api/issues/async-exhaust/{id}` (x4) | All `async-task-*` threads busy, rejections |
| 8 | @Transactional + HTTP Call | `GET /api/issues/transactional-api/{id}` | `TransactionInterceptor` + `SocketInputStream.read()` in same stack |

## Running

```bash
cd benchmark/fixture-app
mvn spring-boot:run
```

Then trigger all issues at once:

```bash
curl -X POST http://localhost:8080/api/issues/trigger-all
```

Wait 2-3 seconds, then capture and analyze:

```bash
../../scripts/dump-collector.sh list
../../scripts/dump-collector.sh capture <PID>
# or use: /thread-dump
```

## Benchmark Protocol

Per the blueprint, each skill is tested 3 times with and 3 times without (bare Claude as baseline).

### Assertions

See `benchmark-assertions.md` for the full list of assertions per skill.
