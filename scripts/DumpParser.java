import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.regex.*;
import java.util.stream.*;

/**
 * DumpParser.java — Parse raw JVM thread dumps into structured sections.
 * Part of thread-necromancer: "Raising insights from dead threads."
 *
 * Usage: java scripts/DumpParser.java <thread-dump-file>
 *
 * Runs as a single-file source program (JDK 11+). No compilation needed.
 * Cross-platform: works identically on Linux, macOS, and Windows.
 */
public class DumpParser {

    // --- Data structures ---

    static class ThreadInfo {
        String name = "";
        String state = "";
        String rawState = "";
        boolean daemon = false;
        List<String> frames = new ArrayList<>();
        List<String> locksHeld = new ArrayList<>();
        List<String> locksWaiting = new ArrayList<>();
        String fullHeader = "";
    }

    static class PoolStats {
        String label;
        String pattern;
        int total, runnable, waiting, timedWaiting, blocked;

        PoolStats(String label, String pattern) {
            this.label = label;
            this.pattern = pattern;
        }

        void add(String state) {
            total++;
            switch (state) {
                case "RUNNABLE": runnable++; break;
                case "BLOCKED": blocked++; break;
                case "TIMED_WAITING": timedWaiting++; break;
                case "WAITING": waiting++; break;
            }
        }
    }

    static class Cluster {
        int count;
        String state = "";
        List<String> topFrames = new ArrayList<>();
        List<String> lockInfo = new ArrayList<>();
        String representative = "";
    }

    // --- Pool pattern definitions ---

    static final String[][] POOL_DEFS = {
        // Tomcat
        {"http-nio-.*-exec-", "Tomcat NIO Executor"},
        {"http-nio-.*-Poller", "Tomcat NIO Poller"},
        {"http-nio-.*-Acceptor", "Tomcat Acceptor"},
        {"Catalina-utility-", "Tomcat Utility"},
        // Jetty
        {"qtp.*-", "Jetty QueuedThreadPool"},
        // Undertow
        {"XNIO-.*-task-", "Undertow Worker"},
        {"XNIO-.*-I/O-", "Undertow I/O"},
        // Spring
        {"scheduling-", "Spring @Scheduled"},
        {"task-", "Spring @Async"},
        {"taskScheduler-", "Spring TaskScheduler"},
        {"AsyncExecutor-", "Async Executor"},
        // Quarkus / Vert.x
        {"executor-thread-", "Quarkus Worker Pool"},
        {"vert\\.x-eventloop-thread-", "Vert.x Event Loop"},
        {"vert\\.x-worker-thread-", "Vert.x Worker Pool"},
        {"vert\\.x-internal-blocking-", "Vert.x Internal Blocking"},
        {"quarkus-scheduler-", "Quarkus Scheduler"},
        // Micronaut
        {"default-nioEventLoopGroup-", "Micronaut Event Loop"},
        {"io-executor-thread-", "Micronaut I/O Pool"},
        {"scheduled-executor-thread-", "Micronaut Scheduler"},
        // Reactive
        {"reactor-http-nio-", "WebFlux/Netty"},
        {"parallel-", "Reactor Parallel"},
        {"boundedElastic-", "Reactor BoundedElastic"},
        // Database pools
        {"HikariPool-.*housekeeper", "HikariCP Housekeeper"},
        {"HikariPool-.*connection", "HikariCP Connection"},
        {"C3P0PooledConnectionPool", "C3P0 Connection Pool"},
        // Clients / Messaging
        {"lettuce-nioEventLoop-", "Redis Lettuce"},
        {"redisson-netty-", "Redisson Redis"},
        {"kafka-producer-network-", "Kafka Producer"},
        {"kafka-coordinator-", "Kafka Coordinator"},
        {"org\\.springframework\\.kafka-", "Spring Kafka Consumer"},
        {"Eureka-", "Eureka Discovery"},
        {"Hystrix-", "Hystrix Circuit Breaker"},
        // JDK
        {"ForkJoinPool\\.commonPool", "ForkJoinPool Common"},
        {"ForkJoinPool-", "ForkJoinPool Custom"},
        {"pool-.*-thread-", "Generic Thread Pool"},
    };

    // --- Parsing ---

    static List<ThreadInfo> parseThreads(List<String> lines) {
        List<ThreadInfo> threads = new ArrayList<>();
        ThreadInfo current = null;

        for (String line : lines) {
            if (line.startsWith("\"")) {
                if (current != null) threads.add(current);
                current = new ThreadInfo();
                current.fullHeader = line;

                // Extract thread name
                int endQuote = line.indexOf('"', 1);
                if (endQuote > 0) {
                    current.name = line.substring(1, endQuote);
                }
                current.daemon = line.contains(" daemon ");
            } else if (current != null) {
                String trimmed = line.trim();

                if (trimmed.startsWith("java.lang.Thread.State:")) {
                    current.rawState = trimmed;
                    String s = trimmed.substring("java.lang.Thread.State: ".length());
                    // Extract base state (without parenthetical)
                    int paren = s.indexOf(' ');
                    current.state = paren > 0 ? s.substring(0, paren) : s;
                } else if (trimmed.startsWith("at ")) {
                    current.frames.add(line);
                } else if (trimmed.startsWith("- locked <")) {
                    current.locksHeld.add(line);
                } else if (trimmed.startsWith("- waiting to lock <") || trimmed.startsWith("- parking to wait for")) {
                    current.locksWaiting.add(line);
                } else if (line.isEmpty() && current.name.isEmpty()) {
                    current = null;
                }
            }
        }
        if (current != null && !current.name.isEmpty()) threads.add(current);

        return threads;
    }

    // --- Metadata ---

    static void printMetadata(List<String> lines, List<ThreadInfo> threads) {
        System.out.println("=== DUMP METADATA ===");

        String timestamp = findLine(lines, "captured_at:", "unknown");
        String pid = findLine(lines, "pid:", "unknown");
        String jvmVersion = findLine(lines, "jvm_version:", "unknown");

        if (timestamp.equals("unknown")) {
            timestamp = lines.stream()
                .map(l -> {
                    Matcher m = Pattern.compile("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}").matcher(l);
                    return m.find() ? m.group() : null;
                })
                .filter(Objects::nonNull)
                .findFirst().orElse("unknown");
        }

        long daemonCount = threads.stream().filter(t -> t.daemon).count();

        System.out.println("timestamp: " + timestamp);
        System.out.println("jvm_version: " + jvmVersion);
        System.out.println("pid: " + pid);
        System.out.println("total_threads: " + threads.size());
        System.out.println("daemon_threads: " + daemonCount);
        System.out.println();
    }

    static String findLine(List<String> lines, String prefix, String fallback) {
        return lines.stream()
            .filter(l -> l.startsWith(prefix))
            .map(l -> l.substring(prefix.length()).trim())
            .findFirst().orElse(fallback);
    }

    // --- State Summary ---

    static void printStateSummary(List<ThreadInfo> threads) {
        System.out.println("=== THREAD STATE SUMMARY ===");

        Map<String, Long> counts = threads.stream()
            .filter(t -> !t.state.isEmpty())
            .collect(Collectors.groupingBy(t -> t.state, Collectors.counting()));

        for (String state : List.of("RUNNABLE", "WAITING", "TIMED_WAITING", "BLOCKED", "NEW", "TERMINATED")) {
            System.out.println(state + ": " + counts.getOrDefault(state, 0L));
        }
        System.out.println();
    }

    // --- Thread Pools ---

    static void printThreadPools(List<ThreadInfo> threads) {
        System.out.println("=== THREAD POOLS ===");

        Set<String> matched = new HashSet<>();
        List<PoolStats> pools = new ArrayList<>();

        for (String[] def : POOL_DEFS) {
            Pattern pattern = Pattern.compile(def[0]);
            PoolStats pool = new PoolStats(def[1], def[0]);

            for (ThreadInfo t : threads) {
                if (pattern.matcher(t.name).find() && !matched.contains(t.name)) {
                    pool.add(t.state);
                    matched.add(t.name);
                }
            }

            if (pool.total > 0) {
                pools.add(pool);
            }
        }

        for (PoolStats p : pools) {
            System.out.println("pool: " + p.label);
            System.out.printf("  total: %d, RUNNABLE: %d, WAITING: %d, TIMED_WAITING: %d, BLOCKED: %d%n",
                p.total, p.runnable, p.waiting, p.timedWaiting, p.blocked);
        }

        long otherCount = threads.stream().filter(t -> !matched.contains(t.name)).count();
        if (otherCount > 0) {
            System.out.println("pool: Other/System");
            System.out.println("  total: " + otherCount);
        }
        System.out.println();
    }

    // --- Deadlocks ---

    static void printDeadlocks(List<String> lines) {
        System.out.println("=== DEADLOCKS ===");

        boolean inDeadlock = false;
        boolean found = false;

        for (String line : lines) {
            if (line.contains("Found") && line.toLowerCase().contains("deadlock")) {
                inDeadlock = true;
                found = true;
            }
            if (inDeadlock) {
                System.out.println(line);
                // Stop after "Found N deadlock." summary line at the end
                if (found && line.matches("Found \\d+ deadlock.*")) {
                    // Check if this is the closing line (not the opening one)
                    if (!line.contains("========")) {
                        break;
                    }
                }
            }
        }

        if (!found) {
            System.out.println("NONE DETECTED");
        }
        System.out.println();
    }

    // --- Blocked Thread Clusters ---

    static void printBlockedClusters(List<ThreadInfo> threads) {
        System.out.println("=== BLOCKED THREAD CLUSTERS ===");

        // Group threads by top 3 frames
        Map<String, Cluster> clusters = new LinkedHashMap<>();

        for (ThreadInfo t : threads) {
            boolean isBlocked = "BLOCKED".equals(t.state);
            boolean isWaitingWithLock = "WAITING".equals(t.state) && !t.locksWaiting.isEmpty();

            if (!isBlocked && !isWaitingWithLock) continue;

            // Build key from top 3 frames
            int frameLimit = Math.min(3, t.frames.size());
            String key = t.frames.subList(0, frameLimit).stream().collect(Collectors.joining("|"));
            if (key.isEmpty()) continue;

            Cluster cluster = clusters.computeIfAbsent(key, k -> {
                Cluster c = new Cluster();
                c.state = t.rawState.replace("java.lang.Thread.State: ", "").trim();
                c.topFrames = t.frames.subList(0, Math.min(5, t.frames.size()));
                c.lockInfo = new ArrayList<>(t.locksWaiting);
                if (c.lockInfo.isEmpty()) c.lockInfo = new ArrayList<>(t.locksHeld);
                c.representative = t.name;
                return c;
            });
            cluster.count++;
        }

        if (clusters.isEmpty()) {
            System.out.println("NONE");
        } else {
            int n = 0;
            for (Cluster c : clusters.values()) {
                n++;
                System.out.printf("cluster_%d: %d threads%n", n, c.count);
                System.out.println("  state: " + c.state);
                System.out.println("  top_frames:");
                c.topFrames.forEach(f -> System.out.println("  " + f));
                if (!c.lockInfo.isEmpty()) {
                    System.out.println("  lock_info:");
                    c.lockInfo.forEach(l -> System.out.println("  " + l));
                }
                System.out.printf("  representative: \"%s\"%n%n", c.representative);
            }
        }
        System.out.println();
    }

    // --- Lock Owners (only threads that HOLD locks) ---

    static void printLockOwners(List<ThreadInfo> threads) {
        System.out.println("=== LOCK OWNERS ===");

        boolean found = false;
        for (ThreadInfo t : threads) {
            if (!t.locksHeld.isEmpty()) {
                found = true;
                System.out.printf("Thread \"%s\":%n", t.name);
                System.out.println("  state: " + t.state);
                t.locksHeld.forEach(l -> System.out.println("  holds: " + l));
                t.locksWaiting.forEach(l -> System.out.println("  waiting_for: " + l));
                System.out.println();
            }
        }

        if (!found) {
            System.out.println("NONE");
            System.out.println();
        }
    }

    // --- Notable Threads (RUNNABLE non-idle, max 20) ---

    static void printNotableThreads(List<ThreadInfo> threads) {
        System.out.println("=== NOTABLE THREADS (RUNNABLE + non-idle, max 20) ===");

        int count = 0;
        for (ThreadInfo t : threads) {
            if (count >= 20) break;
            if (!"RUNNABLE".equals(t.state)) continue;

            // Skip idle patterns
            boolean idle = t.frames.stream().anyMatch(f ->
                f.contains("Unsafe.park") ||
                f.contains("EPoll.wait") ||
                f.contains("KQueue.poll") ||
                f.contains("SelectorImpl.select") ||
                f.contains("poll0") ||
                f.contains("accept0") ||
                f.contains("SocketDispatcher.read") ||
                f.contains("ForkJoinPool.awaitWork") ||
                f.contains("ThreadPoolExecutor.getTask"));

            if (idle) continue;

            System.out.println(t.fullHeader);
            if (!t.rawState.isEmpty()) System.out.println("   " + t.rawState);
            t.frames.forEach(System.out::println);
            t.locksHeld.forEach(System.out::println);
            t.locksWaiting.forEach(System.out::println);
            System.out.println();
            count++;
        }

        System.out.printf("(showing max 20 RUNNABLE threads; BLOCKED threads are in clusters above)%n");
    }

    // --- Main ---

    public static void main(String[] args) {
        if (args.length < 1 || "-h".equals(args[0]) || "--help".equals(args[0])) {
            System.err.println("Usage: java DumpParser.java <thread-dump-file>");
            System.err.println();
            System.err.println("Parses a raw JVM thread dump into structured sections for analysis.");
            System.err.println("Compresses thousands of lines into ~200 lines of actionable data.");
            System.exit(1);
        }

        Path file = Paths.get(args[0]);
        if (!Files.exists(file)) {
            System.err.println("Error: File not found: " + file);
            System.exit(1);
        }

        try {
            List<String> lines = Files.readAllLines(file);
            List<ThreadInfo> threads = parseThreads(lines);

            printMetadata(lines, threads);
            printStateSummary(threads);
            printThreadPools(threads);
            printDeadlocks(lines);
            printBlockedClusters(threads);
            printLockOwners(threads);
            printNotableThreads(threads);

        } catch (IOException e) {
            System.err.println("Error reading file: " + e.getMessage());
            System.exit(1);
        }
    }
}
