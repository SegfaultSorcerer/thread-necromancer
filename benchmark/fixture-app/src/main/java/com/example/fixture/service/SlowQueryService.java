package com.example.fixture.service;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * ISSUE #1: Connection Pool Exhaustion
 *
 * Holds database connections for extended periods with slow queries.
 * Combined with HikariCP pool size of 5, this causes other threads
 * to block waiting at HikariPool.getConnection().
 */
@Service
public class SlowQueryService {

    private static final Logger log = LoggerFactory.getLogger(SlowQueryService.class);

    @PersistenceContext
    private EntityManager entityManager;

    @Transactional(readOnly = true)
    public String runSlowQuery() {
        log.debug("Starting slow query (holding connection for 10s)...");
        try {
            // Simulate a long-running query by sleeping while holding the connection
            // In production this would be an actual slow query or full table scan
            Thread.sleep(10_000);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        return "query-result";
    }
}
