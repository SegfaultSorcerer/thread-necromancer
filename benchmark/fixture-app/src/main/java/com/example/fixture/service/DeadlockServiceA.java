package com.example.fixture.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * ISSUE #3: Deadlock (Part A)
 *
 * Acquires lockA then lockB. DeadlockServiceB acquires lockB then lockA.
 * When called concurrently, this creates a classic deadlock.
 */
@Service
public class DeadlockServiceA {

    private static final Logger log = LoggerFactory.getLogger(DeadlockServiceA.class);

    // Shared locks — static so both services see the same objects
    static final Object LOCK_A = new Object();
    static final Object LOCK_B = new Object();

    /**
     * Acquires LOCK_A first, then LOCK_B.
     * Deadlocks with DeadlockServiceB.transferBackward() which acquires in reverse order.
     */
    public String transferForward(String data) {
        log.debug("ServiceA: acquiring LOCK_A...");
        synchronized (LOCK_A) {
            log.debug("ServiceA: acquired LOCK_A, sleeping before acquiring LOCK_B...");
            try {
                // Small delay to increase deadlock probability
                Thread.sleep(100);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }

            log.debug("ServiceA: acquiring LOCK_B...");
            synchronized (LOCK_B) {
                log.debug("ServiceA: acquired both locks, processing...");
                return "forward-" + data;
            }
        }
    }
}
