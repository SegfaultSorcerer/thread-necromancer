package com.example.fixture;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Fixture application with 8 intentional thread problems for benchmarking thread-necromancer.
 *
 * Issues:
 * 1. Connection pool exhaustion (HikariCP pool size 5, long queries)
 * 2. Synchronized bottleneck (synchronized on hot-path service)
 * 3. Deadlock (two services acquiring locks in opposite order)
 * 4. @Scheduled single-thread starvation (default pool size 1, blocking task)
 * 5. Thread leak (new Thread().start() without pool management)
 * 6. External service timeout (HTTP call with no timeout)
 * 7. @Async pool exhaustion (pool size 2, slow tasks)
 * 8. @Transactional holding connection during REST call
 */
@SpringBootApplication
@EnableScheduling
@EnableAsync
public class FixtureApplication {

    public static void main(String[] args) {
        SpringApplication.run(FixtureApplication.class, args);
    }
}
