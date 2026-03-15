# thread-necromancer — Implementation Blueprint

> JVM Thread Dump Analysis for Claude Code.
> Part of the SegfaultSorcerer Java Tooling Ecosystem.
> "Raising insights from dead threads."

---

## 1. Project Identity

| Field            | Value                                                      |
|------------------|------------------------------------------------------------|
| Name             | thread-necromancer                                         |
| Tagline          | "Raising insights from dead threads"                       |
| Type             | Claude Code Plugin (skills + hooks + scripts)              |
| Repository       | `SegfaultSorcerer/thread-necromancer`                      |
| License          | Dual: MIT + Apache 2.0 (same as spring-grimoire)           |
| Naming theme     | Occult/supernatural — consistent with SegfaultSorcerer brand |
| Branding         | Dark purple/violet tones, skull or ghost thread imagery     |

---

## 2. Problem Statement

Thread dumps are one of the most powerful JVM diagnostic tools, but also one of the most underused because:

- Raw dumps are walls of text (easily 5000+ lines for a production app)
- Most developers can spot an obvious deadlock but miss subtle contention patterns
- Temporal analysis (comparing dumps over time) is almost never done manually
- Spring proxy classes, CGLIB enhancers, and AOP wrappers obscure the real call site
- Existing tools are either SaaS (fastThread.io), GUI-only (VisualVM), or abandoned Perl scripts
- No tool integrates with AI-assisted development workflows

thread-necromancer fills this gap: a CLI-native, Claude Code-integrated tool that turns thread dumps into structured, actionable insights.

---

## 3. Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│  thread-necromancer (Claude Code Plugin)                  │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │   Scripts     │  │    Skills    │  │     Hooks     │  │
│  │  (Shell/PS)   │  │  (SKILL.md)  │  │ (hooks.json)  │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬────────┘  │
│         │                 │                  │           │
│         ▼                 ▼                  ▼           │
│  ┌──────────────────────────────────────────────────┐   │
│  │  dump-collector.sh / dump-collector.ps1           │   │
│  │  - Discovers JVM processes via jcmd/jps           │   │
│  │  - Captures thread dumps (single or series)       │   │
│  │  - Captures deadlock-only dumps                   │   │
│  │  - Outputs structured text for Claude to analyze   │   │
│  └──────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
```

### Directory Structure

```
thread-necromancer/
├── .claude-plugin/
│   └── plugin.json              # Plugin metadata for Claude Code marketplace
├── skills/
│   ├── thread-dump/
│   │   ├── SKILL.md             # /thread-dump — live capture + analysis
│   │   └── references/
│   │       ├── thread-states.md
│   │       ├── common-patterns.md
│   │       └── spring-thread-patterns.md
│   ├── thread-analyze/
│   │   ├── SKILL.md             # /thread-analyze <file> — analyze existing dump
│   │   └── references/
│   │       └── analysis-checklist.md
│   ├── thread-watch/
│   │   ├── SKILL.md             # /thread-watch — multi-dump temporal analysis
│   │   └── references/
│   │       └── temporal-patterns.md
│   └── thread-compare/
│       ├── SKILL.md             # /thread-compare <f1> <f2> — diff two dumps
│       └── references/
│           └── diff-strategies.md
├── hooks/
│   ├── hooks.json               # Hook configuration
│   └── hooks.windows.json       # PowerShell variants
├── scripts/
│   ├── dump-collector.sh        # Bash: capture thread dumps
│   ├── dump-collector.ps1       # PowerShell: capture thread dumps
│   ├── dump-parser.sh           # Bash: pre-parse dump into structured sections
│   ├── dump-parser.ps1          # PowerShell variant
│   └── check-prerequisites.sh   # Verify jcmd, jps, jstack availability
├── CONTRIBUTING.md
├── LICENSE-MIT
├── LICENSE-APACHE
├── README.md
└── thread-necromancer.png       # Branding image
```

---

## 4. Scripts (Shell Layer)

The scripts handle JVM interaction and raw dump collection. Claude doesn't call jcmd directly — the scripts abstract platform differences and provide structured output.

### 4.1 `dump-collector.sh` / `dump-collector.ps1`

**Purpose:** Discover JVM processes and capture thread dumps.

**Commands:**

```bash
# List running JVM processes
./scripts/dump-collector.sh list

# Expected output format:
# PID    MAIN_CLASS                          UPTIME     ARGS
# 12345  com.example.Application             2h 34m     --spring.profiles.active=prod
# 12346  org.apache.maven.surefire.booter    0h 02m     ...

# Capture single thread dump
./scripts/dump-collector.sh capture <PID> [output-dir]
# Writes: <output-dir>/thread-dump-<PID>-<timestamp>.txt

# Capture series (for temporal analysis)
./scripts/dump-collector.sh watch <PID> [count=3] [interval=5] [output-dir]
# Writes: <output-dir>/thread-dump-<PID>-<timestamp>-1.txt
#         <output-dir>/thread-dump-<PID>-<timestamp>-2.txt
#         <output-dir>/thread-dump-<PID>-<timestamp>-3.txt

# Capture deadlock info only (fast)
./scripts/dump-collector.sh deadlock <PID>
```

**Implementation details:**

- Use `jcmd <PID> Thread.print -l` as primary method (includes lock info)
- Fall back to `jstack -l <PID>` if jcmd not available
- Fall back to `kill -3 <PID>` as last resort (output goes to app's stdout)
- On Windows, use `jcmd.exe` via PowerShell
- Always include `-l` flag for lock information
- Capture JVM version info alongside the dump (`jcmd <PID> VM.version`)
- Create output directory `.thread-necromancer/dumps/` in project root if no output-dir specified
- Add `.thread-necromancer/` to generated `.gitignore` suggestion

**Error handling:**

- PID not found → clear error message + suggest running `list` first
- Permission denied → suggest running with appropriate permissions
- jcmd not on PATH → check JAVA_HOME/bin, suggest adding to PATH
- Process is not a JVM → detect and report

### 4.2 `dump-parser.sh` / `dump-parser.ps1`

**Purpose:** Pre-parse a raw thread dump into structured sections that are easier for Claude to analyze. This reduces token usage by letting Claude focus on analysis rather than parsing.

**Output format (structured text):**

```
=== DUMP METADATA ===
timestamp: 2025-03-14T20:45:12.000Z
jvm_version: OpenJDK 21.0.2
pid: 12345
total_threads: 247

=== THREAD STATE SUMMARY ===
RUNNABLE: 23
WAITING: 147
TIMED_WAITING: 45
BLOCKED: 32

=== THREAD POOLS ===
pool: http-nio-8080-exec (Tomcat)
  total: 200, RUNNABLE: 12, WAITING: 147, BLOCKED: 38, TIMED_WAITING: 3
  pattern: org.apache.tomcat.util.threads.TaskThread

pool: scheduling-1 (Spring @Scheduled)
  total: 5, RUNNABLE: 1, WAITING: 4
  pattern: org.springframework.scheduling

pool: HikariPool-1 (HikariCP)
  total: 10, RUNNABLE: 3, TIMED_WAITING: 7
  pattern: com.zaxxer.hikari.pool.HikariPool

pool: ForkJoinPool.commonPool
  total: 8, RUNNABLE: 2, WAITING: 6

pool: Other/Unnamed
  total: 24

=== DEADLOCKS ===
NONE DETECTED
# or:
# DEADLOCK #1:
#   Thread "exec-42" holds lock 0x000000076ab30 (ReentrantLock)
#     waiting for lock 0x000000076cd40 (OrderService)
#   Thread "exec-17" holds lock 0x000000076cd40 (OrderService)
#     waiting for lock 0x000000076ab30 (ReentrantLock)

=== BLOCKED THREAD CLUSTERS ===
cluster_1: 147 threads blocked at same point
  state: WAITING (parking)
  common_frame: com.zaxxer.hikari.pool.HikariPool.getConnection(HikariPool.java:181)
  lock: java.util.concurrent.SynchronousQueue
  top_frames:
    sun.misc.Unsafe.park(Native Method)
    java.util.concurrent.locks.LockSupport.park(LockSupport.java:175)
    com.zaxxer.hikari.pool.HikariPool.getConnection(HikariPool.java:181)
  representative_thread: "http-nio-8080-exec-42"

cluster_2: 23 threads blocked at same point
  state: BLOCKED (on object monitor)
  common_frame: com.example.service.LegacyService.processOrder(LegacyService.java:89)
  lock: com.example.service.LegacyService@76ab3012
  holder: "http-nio-8080-exec-17"

=== LOCK OWNERS ===
Thread "http-nio-8080-exec-42":
  holds: 0x000000076ab30 (ReentrantLock)
  waiting_for: 0x000000076cd40 (HikariCP connection)
  state: WAITING

=== RAW THREADS (condensed) ===
# Only non-idle threads, with common JDK frames collapsed
[full stacktraces of interesting threads here]
```

**Key parsing rules:**

- Identify thread pools by name patterns: `http-nio-*`, `scheduling-*`, `HikariPool-*`, `ForkJoinPool*`, `pool-*-thread-*`, `AsyncExecutor-*`
- Group threads with identical top-5 stack frames into clusters
- Extract lock/monitor information from `- locked <0x...>` and `- waiting to lock <0x...>` lines
- Detect Spring proxy frames and annotate: `$$EnhancerBySpringCGLIB$$` → note "Spring proxy"
- Collapse common JDK internal frames (NIO selector, socket read, park) into single-line summaries for non-blocked threads
- Count and report daemon vs non-daemon threads

---

## 5. Skills (Claude Analysis Layer)

Each skill follows the spring-grimoire pattern: YAML frontmatter + structured prompt + reference material.

### 5.1 `/thread-dump` — Live Capture + Analysis

```yaml
---
name: thread-dump
description: Capture a live thread dump from a running JVM process and analyze it
usage: /thread-dump [PID]
arguments:
  - name: PID
    description: "JVM process ID. If omitted, list available processes and ask."
    required: false
---
```

**Skill behavior:**

1. If no PID given: run `dump-collector.sh list`, present table, ask user to pick
2. Run `dump-collector.sh capture <PID>`
3. Run `dump-parser.sh <dump-file>` to get structured sections
4. Analyze with the following checklist (see reference files):
   - Thread state distribution — is it healthy?
   - Deadlock detection (explicit from JVM + implicit from lock chains)
   - Blocked thread clusters — what are threads waiting on?
   - Thread pool sizing — are pools appropriately sized?
   - Lock contention hotspots — which locks have the most waiters?
   - Spring-specific patterns — proxy overhead, @Transactional locks, @Async pool exhaustion
5. Output structured report (see Section 7: Output Format)

### 5.2 `/thread-analyze` — Analyze Existing Dump File

```yaml
---
name: thread-analyze
description: Analyze an existing thread dump file
usage: /thread-analyze <file-path>
arguments:
  - name: file-path
    description: "Path to thread dump file (.txt, .tdump, .log)"
    required: true
---
```

**Skill behavior:**

1. Validate file exists and looks like a thread dump (check for `"thread-name" #N` pattern)
2. Run `dump-parser.sh <file-path>`
3. Same analysis as `/thread-dump` step 4+5
4. If file contains multiple dumps (some tools concatenate), detect boundaries and analyze each

### 5.3 `/thread-watch` — Temporal Analysis

```yaml
---
name: thread-watch
description: Capture multiple thread dumps over time and analyze thread progression
usage: /thread-watch [PID] [--count 3] [--interval 5]
arguments:
  - name: PID
    description: "JVM process ID"
    required: false
  - name: count
    description: "Number of dumps to capture (default: 3)"
    required: false
  - name: interval
    description: "Seconds between dumps (default: 5)"
    required: false
---
```

**Skill behavior:**

1. Capture N dumps at M-second intervals via `dump-collector.sh watch`
2. Parse each dump
3. Perform temporal diff analysis:
   - **Stuck threads**: threads in same state + same top frame across all dumps → truly blocked
   - **Progressing threads**: threads that moved between dumps → healthy, just slow
   - **Oscillating threads**: threads alternating between RUNNABLE and WAITING → possible contention
   - **Growing pools**: thread count increasing across dumps → possible leak or runaway pool
   - **Lock holder duration**: if the same thread holds a lock across all dumps → long-running critical section
4. Output temporal report with per-dump summaries + diff highlights

### 5.4 `/thread-compare` — Diff Two Dumps

```yaml
---
name: thread-compare
description: Compare two thread dumps to identify changes
usage: /thread-compare <file1> <file2>
arguments:
  - name: file1
    description: "Path to first (earlier) thread dump"
    required: true
  - name: file2
    description: "Path to second (later) thread dump"
    required: true
---
```

**Skill behavior:**

1. Parse both dumps
2. Match threads by name (thread names are stable across dumps)
3. Report:
   - Threads that changed state (e.g., RUNNABLE → BLOCKED)
   - Threads that appeared or disappeared (pool scaling, thread creation)
   - Lock holders that changed
   - Cluster size changes (contention getting better or worse)
4. Output comparison table

---

## 6. Reference Material

These files go in `skills/<skill>/references/` and are loaded by Claude during analysis.

### 6.1 `references/thread-states.md`

Content for this file:

- JVM thread state definitions (NEW, RUNNABLE, BLOCKED, WAITING, TIMED_WAITING, TERMINATED)
- Healthy state distribution percentages for a typical Spring Boot app under moderate load:
  - RUNNABLE: 5-20%, TIMED_WAITING: 30-50%, WAITING: 20-40%, BLOCKED: < 5%
- Red flags:
  - BLOCKED > 10% → serious lock contention
  - All threads in one pool WAITING → idle pool (possibly undersized upstream)
  - Many RUNNABLE doing the same thing → hot loop or CPU-bound operation
  - Thread count growing over time → thread leak

### 6.2 `references/common-patterns.md`

Patterns to document with signature, root cause, fix, and relevant Spring config:

1. **Connection Pool Exhaustion** — many threads WAITING at `HikariPool.getConnection()` or `C3P0PooledConnectionPoolManager`
2. **Synchronized Bottleneck** — many BLOCKED threads at same synchronized method/block
3. **External Service Timeout** — threads RUNNABLE at `SocketInputStream.read()` with no timeout
4. **GC-Induced Thread Suspension** — all threads suddenly parked (dump taken during STW pause)
5. **Thread Pool Exhaustion** — all threads in a pool busy, no idle threads left
6. **Deadlock** — JVM reports "Found one Java-level deadlock"
7. **@Async Pool Starvation** — `SimpleAsyncTaskExecutor` creating unlimited threads, or `ThreadPoolTaskExecutor` fully blocked

Each pattern should include:
- Signature (what does it look like in the dump?)
- Root cause
- Fix with concrete code/config examples
- Relevant `spring.*` configuration properties

### 6.3 `references/spring-thread-patterns.md`

Content:

**Thread Name → Component Mapping table:**

| Thread Name Pattern            | Component                    | Default Pool Size |
|-------------------------------|------------------------------|-------------------|
| `http-nio-*-exec-*`          | Tomcat NIO connector         | 200               |
| `http-nio-*-Poller`          | Tomcat NIO selector          | 1-2               |
| `http-nio-*-Acceptor`        | Tomcat connection acceptor   | 1                 |
| `scheduling-*`               | @Scheduled (Spring default)  | 1 (!)             |
| `task-*`                     | @Async (Spring default pool) | 8                 |
| `taskScheduler-*`            | Spring TaskScheduler         | configurable      |
| `HikariPool-*-housekeeper`   | HikariCP maintenance         | 1                 |
| `HikariPool-*-connection-*`  | HikariCP connections         | pool size         |
| `lettuce-nioEventLoop-*`     | Redis Lettuce client         | CPU cores         |
| `reactor-http-nio-*`         | WebFlux/Netty event loop     | CPU cores         |
| `parallel-*`                 | Project Reactor parallel      | CPU cores         |
| `boundedElastic-*`           | Project Reactor blocking ops | 10 × CPU cores    |
| `Eureka-*`                   | Eureka service discovery     | varies            |
| `ForkJoinPool.commonPool-*`  | JDK common pool              | CPU cores - 1     |
| `C3P0PooledConnectionPool*`  | C3P0 connection pool         | pool size         |
| `oracle.jdbc.*`              | Oracle JDBC driver threads   | varies            |

**Spring Proxy Detection rules:**
- `$$EnhancerBySpringCGLIB$$` / `$$SpringCGLIB$$` → CGLIB proxy, extract real class name
- `CglibAopProxy` in stack → AOP advice being applied
- `TransactionInterceptor` → @Transactional proxy
- `org.springframework.security.access.intercept` → @PreAuthorize/@Secured proxy

**Common Spring Pitfalls in Thread Dumps:**
1. @Scheduled with default pool (size=1) — all tasks queue behind one
2. @Transactional holding connection during non-DB I/O
3. Lazy loading outside transaction (open-in-view default=true)

### 6.4 `references/temporal-patterns.md`

Content:

- **Stuck Thread Detection**: same state + same top 3 frames + same lock across 3+ dumps → truly blocked
- **Progression Detection**: changed state or moved in call stack → healthy
- **Thread Count Drift**: growing = possible leak, shrinking = scaling down or dying, stable = healthy
- **Contention Trend**: growing clusters = getting worse, shrinking = resolving, stable large = steady bottleneck
- **Lock Holder Stability**: same holder across all dumps → duration estimate = (dumps - 1) × interval

---

## 7. Output Format

All skills produce output following this structure. Matches the spring-grimoire convention.

```markdown
## Thread Dump Analysis Report

### Metadata
| Field       | Value                           |
|-------------|---------------------------------|
| Timestamp   | 2025-03-14 20:45:12 UTC         |
| JVM         | OpenJDK 21.0.2                  |
| PID         | 12345                           |
| Threads     | 247 total (23 daemon)           |
| Application | com.example.Application (Spring Boot) |

### Thread State Distribution
| State         | Count | Percentage | Assessment           |
|---------------|-------|------------|----------------------|
| RUNNABLE      | 23    | 9.3%       | ✅ Healthy           |
| WAITING       | 147   | 59.5%      | ⚠️ High — check below |
| TIMED_WAITING | 45    | 18.2%      | ✅ Normal            |
| BLOCKED       | 32    | 13.0%      | 🔴 Contention!       |

### Thread Pool Health
| Pool                 | Size | Busy | Idle | Blocked | Assessment              |
|----------------------|------|------|------|---------|-------------------------|
| http-nio-8080-exec   | 200  | 12   | 3    | 38      | 🔴 147 waiting for DB   |
| scheduling-1         | 1    | 1    | 0    | 0       | ⚠️ Single thread pool   |
| HikariPool-1         | 10   | 3    | 0    | 0       | 🔴 Fully utilized       |
| ForkJoinPool.common  | 8    | 2    | 6    | 0       | ✅ Healthy              |

### Deadlocks
NONE DETECTED (or detailed deadlock chain with lock addresses and involved threads)

### Contention Hotspots
| Severity | Lock / Monitor                        | Waiting | Holder       | Duration |
|----------|---------------------------------------|---------|--------------|----------|
| CRITICAL | HikariPool.getConnection              | 147     | exec-42      | > 5s     |
| CRITICAL | LegacyService.synchronized            | 23      | exec-17      | > 2s     |
| WARNING  | ConcurrentHashMap.computeIfAbsent     | 8       | exec-102     | < 1s     |

### Blocked Thread Clusters
Per cluster: count, description, severity, representative stacktrace with Spring proxy annotations.

### Spring-Specific Findings
| Severity | Finding                                        | Detail                                       |
|----------|------------------------------------------------|----------------------------------------------|
| WARNING  | @Scheduled pool size = 1 (default)             | Only 1 scheduling thread — tasks will queue  |
| WARNING  | @Transactional holding connection during I/O   | Method does HTTP call inside TX               |
| INFO     | open-in-view likely enabled                    | Lazy init frames in controller stacks         |

### Top 3 Actions
Numbered, with severity, concrete config YAML, and code fix suggestions.
```

---

## 8. Hooks

### 8.1 Thread Dump on Test Hang (opt-in)

| Field     | Value                                                               |
|-----------|---------------------------------------------------------------------|
| Event     | `PostToolUse` (after test execution)                                |
| Trigger   | `mvn test` or `gradle test` fails with timeout or hang              |
| Action    | Automatically capture a thread dump of the test JVM if still running|
| Opt-in    | Flag file `.thread-necromancer/dump-on-test-hang.enabled`           |

### 8.2 Startup Thread Baseline (opt-in)

| Field     | Value                                                               |
|-----------|---------------------------------------------------------------------|
| Event     | `PostToolUse` (after Spring Boot application starts)                |
| Trigger   | `mvn spring-boot:run` or application startup detected               |
| Action    | Capture baseline thread dump 10s after startup                      |
| Opt-in    | Flag file `.thread-necromancer/startup-baseline.enabled`            |

---

## 9. Plugin Configuration

### `plugin.json`

```json
{
  "name": "thread-necromancer",
  "version": "1.0.0",
  "description": "JVM Thread Dump Analysis — raising insights from dead threads",
  "author": "SegfaultSorcerer",
  "homepage": "https://github.com/SegfaultSorcerer/thread-necromancer",
  "license": "MIT OR Apache-2.0",
  "skills": [
    "skills/thread-dump",
    "skills/thread-analyze",
    "skills/thread-watch",
    "skills/thread-compare"
  ],
  "hooks": "hooks/hooks.json",
  "prerequisites": {
    "required": ["java"],
    "optional": ["jcmd", "jstack"]
  },
  "tags": ["java", "jvm", "debugging", "performance", "spring"],
  "keywords": ["thread dump", "deadlock", "contention", "jvm diagnostics"]
}
```

---

## 10. Prerequisites & Compatibility

| Requirement   | Minimum | Recommended | Notes                                    |
|---------------|---------|-------------|------------------------------------------|
| JDK           | 11+     | 17+         | jcmd available since JDK 7               |
| Claude Code   | latest  | latest      | Plugin marketplace support required       |
| OS            | any     | any         | Bash scripts + PowerShell alternatives    |
| Build tool    | —       | Maven/Gradle| For test-failure hook integration          |

**Platform notes:**

- **macOS/Linux:** Scripts use bash. `jcmd` should be on PATH (usually via `$JAVA_HOME/bin`).
- **Windows:** PowerShell scripts provided. If Git Bash is installed, bash scripts also work (same pattern as spring-grimoire).
- **Docker/containers:** `jcmd` works if the JDK (not just JRE) is in the container. For containers with JRE only, include a note about using `jstack` from the host.

---

## 11. Benchmark Plan

Follow spring-grimoire's methodology: test each skill against a fixture project with intentional issues, 3 runs with skill vs. 3 runs without (bare Claude as baseline).

### Fixture Project

A Spring Boot 3.2 application with intentionally induced thread problems:

1. **Connection pool exhaustion** — HikariCP pool size 5, long-running queries
2. **Synchronized bottleneck** — `synchronized(this)` on a hot-path service
3. **Deadlock** — Two services acquiring locks in opposite order
4. **@Scheduled single-thread starvation** — Default pool, one task sleeping 60s
5. **Thread leak** — `new Thread().start()` without pool management
6. **External service timeout** — HTTP call with no timeout configured
7. **@Async pool exhaustion** — Pool size 2, tasks taking 30s each
8. **@Transactional holding connection during REST call** — DB connection held during external API call

### Assertions per Skill

**`/thread-dump` (~25 assertions):**
- Detects connection pool exhaustion (cluster size, pool name)
- Detects synchronized bottleneck (lock object, holder thread, waiter count)
- Detects deadlock if present
- Reports correct thread pool sizes and names
- Identifies Spring @Scheduled pool size = 1
- Identifies @Transactional holding connection during I/O
- Produces severity table with CRITICAL/WARNING/INFO
- Produces Top 3 Actions with concrete config suggestions
- Output follows specified table format

**`/thread-watch` (~20 assertions):**
- Identifies stuck threads (same state across all dumps)
- Identifies progressing threads
- Reports contention trend (growing/stable/shrinking)
- Detects thread count drift
- Identifies long-running lock holders with duration estimate
- Reports per-dump summary + diff

**`/thread-compare` (~15 assertions):**
- Matches threads by name across dumps
- Reports state changes correctly
- Reports new/disappeared threads
- Reports cluster size changes

### Benchmark Targets

| Skill            | Target (with skill) | Expected baseline | Expected delta |
|------------------|--------------------|--------------------|----------------|
| /thread-dump     | > 95%              | ~75-80%            | +15-20%        |
| /thread-watch    | > 95%              | ~70-75%            | +20-25%        |
| /thread-compare  | > 90%              | ~65-70%            | +20-25%        |
| /thread-analyze  | Same as /thread-dump | Same              | Same           |

---

## 12. README Structure

Follow spring-grimoire's proven README structure:

1. Banner image (`thread-necromancer.png`) + tagline
2. Badges: license (MIT + Apache 2.0), Java 17+, Claude Code Plugin
3. Stats line: "4 slash commands. 2 automation hooks. Zero config to get started."
4. **Why?** section (2-3 paragraphs: the problem + why this tool)
5. **Skills** table (quick overview)
6. Per-skill detail sections with benchmark results (expandable)
7. **Hooks** table
8. **Installation** (plugin marketplace command + manual git clone)
9. **Prerequisites** (with `check-prerequisites.sh`)
10. **Configuration** (opt-in hooks via flag files, `.thread-necromancer/` directory)
11. **Benchmark** summary table
12. **Synergies** (links to spring-grimoire, heap-seance)
13. **Contributing**
14. **License**

---

## 13. Synergies with Existing Tooling

### spring-grimoire
- `/spring-jpa-audit` finds N+1 queries → `/thread-dump` shows actual connection pool impact at runtime
- `/spring-security-check` finds misconfigurations → `/thread-dump` shows threads blocked by security filters
- `/spring-config-audit` (planned) warns about default pool sizes → `/thread-dump` proves the impact
- Shared Spring thread naming conventions and proxy pattern knowledge

### heap-seance
- Memory analysis shows what's allocated → thread analysis shows who's allocating
- Combined: memory leak found by heap-seance → thread-necromancer shows which threads create the leaked objects

### gc-exorcist (planned)
- GC pauses cause thread freezes → temporal analysis detects "all threads paused" pattern
- Combined view: GC log timeline + thread dump timeline = complete JVM health picture

---

## 14. Implementation Order

Suggested sequence for building this project:

### Phase 1: Foundation
1. Create repository with directory structure, licenses, README skeleton
2. Implement `check-prerequisites.sh`
3. Implement `dump-collector.sh` (list + capture commands)
4. Implement `dump-parser.sh` (basic: state summary + pool detection + cluster grouping)
5. Test manually with a real Spring Boot app

### Phase 2: Core Skills
6. Write `/thread-dump` SKILL.md with all reference files
7. Write `/thread-analyze` SKILL.md
8. Write `plugin.json`
9. Test both skills against a Spring Boot app with known issues

### Phase 3: Temporal Analysis
10. Add `watch` command to dump-collector
11. Write `/thread-watch` SKILL.md with temporal-patterns reference
12. Write `/thread-compare` SKILL.md
13. Test temporal skills

### Phase 4: Hooks + Polish
14. Implement hooks (dump-on-test-hang, startup-baseline)
15. Write PowerShell variants of all scripts
16. Write `hooks.windows.json`

### Phase 5: Benchmark
17. Create fixture Spring Boot project with 8 intentional issues
18. Run benchmarks (3x with, 3x without per skill)
19. Update README with benchmark results
20. Create branding image

### Phase 6: Release
21. Final README polish
22. Tag v1.0.0
23. Publish to Claude Code plugin marketplace

---

## 15. Future Ideas (v2.0+)

- **JMX integration**: Capture thread info via JMX for remote JVMs
- **Continuous monitoring mode**: Periodic dumps with alerts on contention spike
- **Visual thread timeline**: Generate HTML visualization of thread states over time
- **Integration with JFR**: Parse Java Flight Recorder thread data for richer analysis
- **Kubernetes support**: Capture dumps from pods via `kubectl exec`
- **Comparative baselines**: Store "healthy" dump and auto-compare new dumps against it
- **Virtual Thread support**: Java 21+ virtual thread analysis (carrier thread pinning, etc.)
