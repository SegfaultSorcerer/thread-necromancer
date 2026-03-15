package com.example.fixture.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * ISSUE #2: Synchronized Bottleneck
 *
 * Uses synchronized(this) on a singleton Spring bean (default scope).
 * Under concurrent load, all threads serialize through this method,
 * causing massive BLOCKED thread accumulation.
 */
@Service
public class LegacySynchronizedService {

    private static final Logger log = LoggerFactory.getLogger(LegacySynchronizedService.class);

    private int orderCounter = 0;

    /**
     * Processes an order with an intentionally coarse-grained synchronized block.
     * The entire method is synchronized on this singleton bean instance,
     * meaning only one thread can execute at a time.
     */
    public synchronized String processOrder(String orderId) {
        log.debug("Processing order {} (holding lock)...", orderId);
        orderCounter++;

        try {
            // Simulate work inside the synchronized block
            // This is the bottleneck — every thread must wait for this
            Thread.sleep(2_000);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }

        return "processed-" + orderId + "-" + orderCounter;
    }
}
