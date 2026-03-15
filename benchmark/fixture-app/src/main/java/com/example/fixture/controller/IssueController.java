package com.example.fixture.controller;

import com.example.fixture.service.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Controller that exposes endpoints to trigger each intentional thread issue.
 * Use these endpoints to create specific thread dump patterns for benchmarking.
 */
@RestController
@RequestMapping("/api/issues")
public class IssueController {

    private static final Logger log = LoggerFactory.getLogger(IssueController.class);

    @Autowired private SlowQueryService slowQueryService;
    @Autowired private LegacySynchronizedService legacySynchronizedService;
    @Autowired private DeadlockServiceA deadlockServiceA;
    @Autowired private DeadlockServiceB deadlockServiceB;
    @Autowired private ThreadLeakService threadLeakService;
    @Autowired private ExternalApiService externalApiService;
    @Autowired private SlowAsyncService slowAsyncService;
    @Autowired private TransactionalApiService transactionalApiService;

    /**
     * ISSUE #1: Connection Pool Exhaustion
     * Hit this endpoint concurrently (>5 times) to exhaust the HikariCP pool.
     */
    @GetMapping("/connection-pool")
    public String connectionPoolExhaustion() {
        return slowQueryService.runSlowQuery();
    }

    /**
     * ISSUE #2: Synchronized Bottleneck
     * Hit this endpoint concurrently to see threads pile up BLOCKED.
     */
    @GetMapping("/synchronized/{orderId}")
    public String synchronizedBottleneck(@PathVariable String orderId) {
        return legacySynchronizedService.processOrder(orderId);
    }

    /**
     * ISSUE #3: Deadlock
     * Triggers two concurrent operations that acquire locks in opposite order.
     * Once deadlocked, threads will never complete.
     */
    @PostMapping("/deadlock")
    public ResponseEntity<Map<String, String>> triggerDeadlock() {
        log.warn("Triggering deadlock scenario...");

        ExecutorService executor = Executors.newFixedThreadPool(2);

        CompletableFuture<String> futureA = CompletableFuture.supplyAsync(
                () -> deadlockServiceA.transferForward("data-1"), executor);

        CompletableFuture<String> futureB = CompletableFuture.supplyAsync(
                () -> deadlockServiceB.transferBackward("data-2"), executor);

        // Don't wait for results — they'll never come if deadlocked
        executor.shutdown();

        return ResponseEntity.accepted().body(Map.of(
                "status", "deadlock scenario triggered",
                "note", "Threads will deadlock. Use /thread-dump to observe."));
    }

    /**
     * ISSUE #5: Thread Leak
     * Each call spawns a new raw thread. Call repeatedly to see thread count grow.
     */
    @PostMapping("/thread-leak/{taskId}")
    public String threadLeak(@PathVariable String taskId) {
        return threadLeakService.processAsync(taskId);
    }

    /**
     * ISSUE #6: External Service Timeout
     * Calls a black-hole server with no timeout. Thread blocks at SocketInputStream.read().
     */
    @GetMapping("/external-timeout")
    public String externalTimeout() {
        return externalApiService.callExternalService();
    }

    /**
     * ISSUE #7: @Async Pool Exhaustion
     * With pool size 2, the third concurrent call will be rejected.
     */
    @PostMapping("/async-exhaust/{taskId}")
    public ResponseEntity<Map<String, String>> asyncExhaustion(@PathVariable String taskId) {
        try {
            slowAsyncService.processSlowly(taskId);
            return ResponseEntity.accepted().body(Map.of(
                    "status", "async task submitted",
                    "taskId", taskId));
        } catch (Exception e) {
            return ResponseEntity.status(503).body(Map.of(
                    "status", "rejected",
                    "reason", e.getClass().getSimpleName() + ": " + e.getMessage()));
        }
    }

    /**
     * ISSUE #8: @Transactional holding connection during external call
     * Holds a DB connection while making an HTTP call to the black hole server.
     */
    @GetMapping("/transactional-api/{orderId}")
    public String transactionalWithApi(@PathVariable String orderId) {
        return transactionalApiService.processWithExternalCall(orderId);
    }

    /**
     * Triggers ALL issues simultaneously for a comprehensive thread dump.
     */
    @PostMapping("/trigger-all")
    public ResponseEntity<Map<String, String>> triggerAll() {
        log.warn("Triggering ALL thread issues...");

        ExecutorService trigger = Executors.newFixedThreadPool(20);

        // Issue #1: Exhaust connection pool (6 concurrent slow queries > pool size 5)
        for (int i = 0; i < 6; i++) {
            trigger.submit(() -> slowQueryService.runSlowQuery());
        }

        // Issue #2: Synchronized bottleneck (10 concurrent requests)
        for (int i = 0; i < 10; i++) {
            final int idx = i;
            trigger.submit(() -> legacySynchronizedService.processOrder("order-" + idx));
        }

        // Issue #3: Deadlock
        trigger.submit(() -> deadlockServiceA.transferForward("deadlock-data"));
        trigger.submit(() -> deadlockServiceB.transferBackward("deadlock-data"));

        // Issue #5: Thread leak (spawn 10 raw threads)
        for (int i = 0; i < 10; i++) {
            threadLeakService.processAsync("leak-" + i);
        }

        // Issue #6: External timeout (3 threads stuck on socket read)
        for (int i = 0; i < 3; i++) {
            trigger.submit(() -> externalApiService.callExternalService());
        }

        // Issue #7: Async pool exhaustion (4 tasks > pool size 2)
        for (int i = 0; i < 4; i++) {
            try {
                slowAsyncService.processSlowly("async-" + i);
            } catch (Exception e) {
                log.debug("Async rejection (expected): {}", e.getMessage());
            }
        }

        // Issue #8: Transactional + API call (3 concurrent)
        for (int i = 0; i < 3; i++) {
            final int idx = i;
            trigger.submit(() -> transactionalApiService.processWithExternalCall("tx-order-" + idx));
        }

        // Issue #4 is automatic — @Scheduled tasks are already running

        trigger.shutdown();

        return ResponseEntity.accepted().body(Map.of(
                "status", "all issues triggered",
                "note", "Wait 2-3 seconds then capture a thread dump with /thread-dump"));
    }
}
