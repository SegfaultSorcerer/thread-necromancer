package com.example.fixture.service;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * ISSUE #8: @Transactional Holding Connection During REST Call
 *
 * Method is @Transactional, so it holds a database connection for the
 * entire duration. But inside the transaction, it makes an external
 * HTTP call that takes a long time. The DB connection is wasted
 * waiting for the external response.
 */
@Service
public class TransactionalApiService {

    private static final Logger log = LoggerFactory.getLogger(TransactionalApiService.class);

    @PersistenceContext
    private EntityManager entityManager;

    @Autowired
    private ExternalApiService externalApiService;

    /**
     * Holds a @Transactional boundary (= DB connection) while making an
     * external HTTP call. The connection is wasted during the external call.
     */
    @Transactional
    public String processWithExternalCall(String orderId) {
        log.debug("Starting transactional processing for order {}", orderId);

        // Do some DB work
        entityManager.createNativeQuery("SELECT 1").getSingleResult();

        // Now make an external call WHILE STILL HOLDING THE TRANSACTION/CONNECTION
        // This is the anti-pattern: the connection is held during the entire HTTP call
        log.debug("Making external call while holding DB connection...");
        String externalResult = externalApiService.callExternalService();

        // More DB work after the external call
        entityManager.createNativeQuery("SELECT 1").getSingleResult();

        return "processed-" + orderId + "-" + externalResult;
    }
}
