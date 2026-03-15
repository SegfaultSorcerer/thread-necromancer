package com.example.fixture.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * ISSUE #3: Deadlock (Part B)
 *
 * Acquires lockB then lockA — the REVERSE order of DeadlockServiceA.
 * When called concurrently with DeadlockServiceA, this creates a classic deadlock.
 */
@Service
public class DeadlockServiceB {

    private static final Logger log = LoggerFactory.getLogger(DeadlockServiceB.class);

    /**
     * Acquires LOCK_B first, then LOCK_A.
     * Deadlocks with DeadlockServiceA.transferForward() which acquires in reverse order.
     */
    public String transferBackward(String data) {
        log.debug("ServiceB: acquiring LOCK_B...");
        synchronized (DeadlockServiceA.LOCK_B) {
            log.debug("ServiceB: acquired LOCK_B, sleeping before acquiring LOCK_A...");
            try {
                // Small delay to increase deadlock probability
                Thread.sleep(100);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }

            log.debug("ServiceB: acquiring LOCK_A...");
            synchronized (DeadlockServiceA.LOCK_A) {
                log.debug("ServiceB: acquired both locks, processing...");
                return "backward-" + data;
            }
        }
    }
}
