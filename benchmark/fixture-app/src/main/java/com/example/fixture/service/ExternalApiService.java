package com.example.fixture.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.io.InputStream;
import java.net.ServerSocket;
import java.net.Socket;

/**
 * ISSUE #6: External Service Timeout
 *
 * Makes HTTP/socket calls with no timeout configured.
 * Connects to a local "black hole" server that accepts connections
 * but never responds, simulating a hung external service.
 */
@Service
public class ExternalApiService {

    private static final Logger log = LoggerFactory.getLogger(ExternalApiService.class);

    private volatile int blackHolePort = -1;
    private volatile ServerSocket blackHoleServer;

    /**
     * Start a local server that accepts connections but never sends data.
     * This simulates an external service that hangs.
     */
    public void startBlackHoleServer() {
        if (blackHoleServer != null) return;

        try {
            blackHoleServer = new ServerSocket(0); // random available port
            blackHolePort = blackHoleServer.getLocalPort();
            log.info("Black hole server started on port {}", blackHolePort);

            Thread serverThread = new Thread(() -> {
                while (!blackHoleServer.isClosed()) {
                    try {
                        Socket client = blackHoleServer.accept();
                        // Accept the connection but never respond — black hole
                        log.debug("Black hole accepted connection from {}", client.getRemoteSocketAddress());
                    } catch (IOException e) {
                        if (!blackHoleServer.isClosed()) {
                            log.error("Black hole server error", e);
                        }
                    }
                }
            }, "black-hole-server");
            serverThread.setDaemon(true);
            serverThread.start();
        } catch (IOException e) {
            log.error("Failed to start black hole server", e);
        }
    }

    /**
     * Calls the "external service" (black hole) with NO timeout.
     * The thread will block at SocketInputStream.read() indefinitely.
     */
    public String callExternalService() {
        if (blackHolePort == -1) {
            startBlackHoleServer();
        }

        log.debug("Calling external service (black hole) on port {}...", blackHolePort);
        try {
            // No connect timeout, no read timeout — this is the bug
            Socket socket = new Socket("localhost", blackHolePort);
            InputStream is = socket.getInputStream();
            // This will block forever — the server never sends data
            int data = is.read();
            socket.close();
            return "response-" + data;
        } catch (IOException e) {
            return "error-" + e.getMessage();
        }
    }
}
