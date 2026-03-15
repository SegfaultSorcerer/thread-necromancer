package com.example.fixture.scheduled;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * ISSUE #4: @Scheduled Single-Thread Starvation
 *
 * Spring's default scheduling pool has size=1. This component has two
 * scheduled tasks. The first sleeps for 60 seconds, blocking the single
 * scheduling thread. The second task cannot run until the first finishes,
 * even if its scheduled time has passed.
 */
@Component
public class BlockingScheduledTasks {

    private static final Logger log = LoggerFactory.getLogger(BlockingScheduledTasks.class);

    /**
     * Long-running scheduled task that blocks the single scheduling thread.
     * Runs every 30 seconds but takes 60 seconds to complete.
     */
    @Scheduled(fixedRate = 30_000)
    public void longRunningTask() {
        log.debug("Long-running scheduled task started (will take 60s)...");
        try {
            Thread.sleep(60_000);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        log.debug("Long-running scheduled task finished");
    }

    /**
     * Quick task that should run every 5 seconds.
     * But it can't, because the scheduling thread is blocked by longRunningTask().
     */
    @Scheduled(fixedRate = 5_000)
    public void quickHealthCheck() {
        log.info("Quick health check executed at {}", System.currentTimeMillis());
    }
}
