package com.example.fixture.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

import java.util.concurrent.CompletableFuture;

/**
 * ISSUE #7: @Async Pool Exhaustion
 *
 * With pool core-size=2 and max-size=2 and queue-capacity=0,
 * only 2 async tasks can run at a time. Additional calls will be
 * rejected with RejectedExecutionException (or block the caller
 * if CallerRunsPolicy is configured).
 */
@Service
public class SlowAsyncService {

    private static final Logger log = LoggerFactory.getLogger(SlowAsyncService.class);

    /**
     * Slow async task — takes 30 seconds.
     * With only 2 pool threads, the pool is quickly exhausted.
     */
    @Async
    public CompletableFuture<String> processSlowly(String taskId) {
        log.debug("Async task {} started on {}", taskId, Thread.currentThread().getName());
        try {
            // Simulate long-running async work
            Thread.sleep(30_000);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        log.debug("Async task {} completed", taskId);
        return CompletableFuture.completedFuture("async-result-" + taskId);
    }
}
