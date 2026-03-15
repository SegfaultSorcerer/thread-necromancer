package com.example.fixture.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.concurrent.atomic.AtomicInteger;

/**
 * ISSUE #5: Thread Leak
 *
 * Creates new threads directly without using a pool.
 * Each call spawns a new thread that runs for a while and eventually dies,
 * but under sustained load the thread count grows unbounded.
 */
@Service
public class ThreadLeakService {

    private static final Logger log = LoggerFactory.getLogger(ThreadLeakService.class);

    private final AtomicInteger threadCounter = new AtomicInteger(0);

    /**
     * Spawns a raw thread for each request — no pooling, no bounds.
     * Under load, this leaks threads.
     */
    public String processAsync(String taskId) {
        int num = threadCounter.incrementAndGet();
        Thread thread = new Thread(() -> {
            log.debug("Leaked thread {} processing task {}", num, taskId);
            try {
                // Simulate long-running background work
                Thread.sleep(30_000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            log.debug("Leaked thread {} finished task {}", num, taskId);
        }, "leaked-thread-" + num);

        thread.setDaemon(true);
        thread.start();

        return "spawned-thread-" + num;
    }
}
