#!/usr/bin/env bash
# generate-large-dump.sh — Generate a realistic production-scale thread dump (~1000 threads)
# This simulates a Spring Boot app under heavy load with multiple issues

set -euo pipefail

OUTPUT="${1:-benchmark/test-dumps/production-scale-dump.txt}"

cat > "$OUTPUT" << 'HEADER'
=== THREAD DUMP ===
captured_at: 2026-03-15T14:23:47Z
pid: 98765
jvm_version: OpenJDK 64-Bit Server VM (17.0.12+7)
===

Full thread dump OpenJDK 64-Bit Server VM (17.0.12+7 mixed mode, sharing):

Threads class SMR info:
_java_thread_list=0x00007f8a0c002340, length=1047, elements={
}

HEADER

THREAD_NUM=1
NID=0x1000

emit_thread() {
    local name="$1" daemon="$2" state="$3" state_detail="$4"
    shift 4
    local tid=$((RANDOM * RANDOM))
    printf '"%s" #%d %sprio=5 os_prio=0 cpu=%.2fms elapsed=3456.78s tid=0x%016x nid=0x%x %s [0x%016x]\n' \
        "$name" "$THREAD_NUM" "${daemon:+daemon }" "$(echo "$RANDOM / 100" | bc -l)" "$tid" "$NID" "$state_detail" "$((RANDOM * RANDOM))" >> "$OUTPUT"
    echo "   java.lang.Thread.State: $state" >> "$OUTPUT"
    while [ $# -gt 0 ]; do
        echo "$1" >> "$OUTPUT"
        shift
    done
    echo "" >> "$OUTPUT"
    THREAD_NUM=$((THREAD_NUM + 1))
    NID=$((NID + 1))
}

# === TOMCAT THREADS (200 total) ===
# 150 idle (WAITING)
for i in $(seq 1 150); do
    emit_thread "http-nio-8080-exec-$i" "daemon" "WAITING (parking)" "waiting on condition" \
        "	at jdk.internal.misc.Unsafe.park(java.base@17.0.12/Native Method)" \
        "	- parking to wait for  <0x00000006c0a0b210> (a java.util.concurrent.locks.AbstractQueuedSynchronizer\$ConditionObject)" \
        "	at java.util.concurrent.locks.LockSupport.park(java.base@17.0.12/LockSupport.java:341)" \
        "	at java.util.concurrent.locks.AbstractQueuedSynchronizer\$ConditionNode.block(java.base@17.0.12/AbstractQueuedSynchronizer.java:506)" \
        "	at java.util.concurrent.ForkJoinPool.unmanagedBlock(java.base@17.0.12/ForkJoinPool.java:3466)" \
        "	at java.util.concurrent.ForkJoinPool.managedBlock(java.base@17.0.12/ForkJoinPool.java:3437)" \
        "	at java.util.concurrent.locks.AbstractQueuedSynchronizer\$ConditionObject.await(java.base@17.0.12/AbstractQueuedSynchronizer.java:1623)" \
        "	at java.util.concurrent.LinkedBlockingQueue.take(java.base@17.0.12/LinkedBlockingQueue.java:435)" \
        "	at org.apache.tomcat.util.threads.TaskQueue.take(TaskQueue.java:117)" \
        "	at java.util.concurrent.ThreadPoolExecutor.getTask(java.base@17.0.12/ThreadPoolExecutor.java:1071)" \
        "	at java.util.concurrent.ThreadPoolExecutor.runWorker(java.base@17.0.12/ThreadPoolExecutor.java:1132)" \
        "	at java.util.concurrent.ThreadPoolExecutor\$Worker.run(java.base@17.0.12/ThreadPoolExecutor.java:635)" \
        "	at org.apache.tomcat.util.threads.TaskThread\$WrappingRunnable.run(TaskThread.java:61)" \
        "	at java.lang.Thread.run(java.base@17.0.12/Thread.java:840)"
done

# 30 BLOCKED on synchronized OrderService
for i in $(seq 151 180); do
    emit_thread "http-nio-8080-exec-$i" "daemon" "BLOCKED (on object monitor)" "waiting for monitor entry" \
        "	at com.megacorp.orderservice.service.OrderProcessingService.processOrder(OrderProcessingService.java:89)" \
        "	- waiting to lock <0x00000006c2d40120> (a com.megacorp.orderservice.service.OrderProcessingService)" \
        "	at com.megacorp.orderservice.service.OrderProcessingService\$\$SpringCGLIB\$\$0.processOrder(<generated>)" \
        "	at com.megacorp.orderservice.controller.OrderController.submitOrder(OrderController.java:45)" \
        "	at java.lang.reflect.Method.invoke(java.base@17.0.12/Method.java:568)" \
        "	at org.springframework.web.method.support.InvocableHandlerMethod.doInvoke(InvocableHandlerMethod.java:255)" \
        "	at org.springframework.web.servlet.FrameworkServlet.service(FrameworkServlet.java:885)" \
        "	at jakarta.servlet.http.HttpServlet.service(HttpServlet.java:614)" \
        "	at org.apache.catalina.core.ApplicationFilterChain.internalDoFilter(ApplicationFilterChain.java:174)"
done

# 15 WAITING on HikariPool.getConnection
for i in $(seq 181 195); do
    emit_thread "http-nio-8080-exec-$i" "daemon" "WAITING (parking)" "waiting on condition" \
        "	at jdk.internal.misc.Unsafe.park(java.base@17.0.12/Native Method)" \
        "	- parking to wait for  <0x00000006c5ab3020> (a java.util.concurrent.SynchronousQueue\$TransferStack)" \
        "	at java.util.concurrent.locks.LockSupport.park(java.base@17.0.12/LockSupport.java:341)" \
        "	at com.zaxxer.hikari.pool.HikariPool.getConnection(HikariPool.java:181)" \
        "	at com.zaxxer.hikari.pool.HikariPool.getConnection(HikariPool.java:146)" \
        "	at com.zaxxer.hikari.HikariDataSource.getConnection(HikariDataSource.java:128)" \
        "	at org.springframework.jdbc.datasource.DataSourceUtils.fetchConnection(DataSourceUtils.java:159)" \
        "	at org.springframework.orm.jpa.vendor.HibernateJpaDialect.beginTransaction(HibernateJpaDialect.java:164)" \
        "	at org.springframework.transaction.interceptor.TransactionInterceptor.invoke(TransactionInterceptor.java:119)" \
        "	at com.megacorp.orderservice.service.InventoryService\$\$SpringCGLIB\$\$0.checkStock(<generated>)" \
        "	at com.megacorp.orderservice.controller.InventoryController.getStock(InventoryController.java:32)"
done

# 5 RUNNABLE doing socket reads (external API without timeout)
for i in $(seq 196 200); do
    emit_thread "http-nio-8080-exec-$i" "daemon" "RUNNABLE" "runnable" \
        "	at java.net.SocketInputStream.socketRead0(java.base@17.0.12/Native Method)" \
        "	at java.net.SocketInputStream.read(java.base@17.0.12/SocketInputStream.java:150)" \
        "	at java.io.BufferedInputStream.fill(java.base@17.0.12/BufferedInputStream.java:244)" \
        "	at org.apache.http.impl.io.SessionInputBufferImpl.streamRead(SessionInputBufferImpl.java:137)" \
        "	at org.apache.http.impl.io.ContentLengthInputStream.read(ContentLengthInputStream.java:174)" \
        "	at com.megacorp.orderservice.client.PaymentGatewayClient.processPayment(PaymentGatewayClient.java:67)" \
        "	at com.megacorp.orderservice.service.PaymentService.charge(PaymentService.java:43)" \
        "	at org.springframework.transaction.interceptor.TransactionInterceptor.invoke(TransactionInterceptor.java:119)" \
        "	at com.megacorp.orderservice.service.PaymentService\$\$SpringCGLIB\$\$0.charge(<generated>)" \
        "	at com.megacorp.orderservice.controller.OrderController.submitOrder(OrderController.java:48)"
done

# === HIKARICP (20 connections) ===
for i in $(seq 1 20); do
    emit_thread "HikariPool-1-connection-$i" "daemon" "TIMED_WAITING (parking)" "waiting on condition" \
        "	at jdk.internal.misc.Unsafe.park(java.base@17.0.12/Native Method)" \
        "	at java.util.concurrent.locks.LockSupport.parkNanos(java.base@17.0.12/LockSupport.java:252)" \
        "	at com.zaxxer.hikari.pool.PoolEntry.createProxyConnection(PoolEntry.java:100)"
done

emit_thread "HikariPool-1-housekeeper" "daemon" "TIMED_WAITING (parking)" "waiting on condition" \
    "	at jdk.internal.misc.Unsafe.park(java.base@17.0.12/Native Method)" \
    "	at java.util.concurrent.locks.LockSupport.parkNanos(java.base@17.0.12/LockSupport.java:252)" \
    "	at java.util.concurrent.ScheduledThreadPoolExecutor\$DelayedWorkQueue.take(java.base@17.0.12/ScheduledThreadPoolExecutor.java:1176)"

# === SPRING SCHEDULING (1 thread — the problem) ===
emit_thread "scheduling-1" "daemon" "TIMED_WAITING (sleeping)" "waiting on condition" \
    "	at java.lang.Thread.sleep(java.base@17.0.12/Native Method)" \
    "	at com.megacorp.orderservice.scheduled.DataSyncJob.syncExternalCatalog(DataSyncJob.java:45)" \
    "	at java.lang.reflect.Method.invoke(java.base@17.0.12/Method.java:568)" \
    "	at org.springframework.scheduling.support.ScheduledMethodRunnable.runInternal(ScheduledMethodRunnable.java:130)"

# === SPRING ASYNC (8 threads, all busy) ===
for i in $(seq 1 8); do
    emit_thread "task-$i" "daemon" "TIMED_WAITING (sleeping)" "waiting on condition" \
        "	at java.lang.Thread.sleep(java.base@17.0.12/Native Method)" \
        "	at com.megacorp.orderservice.service.EmailNotificationService.sendOrderConfirmation(EmailNotificationService.java:72)" \
        "	at com.megacorp.orderservice.service.EmailNotificationService\$\$SpringCGLIB\$\$0.sendOrderConfirmation(<generated>)"
done

# === LETTUCE REDIS (4 threads) ===
for i in $(seq 1 4); do
    emit_thread "lettuce-nioEventLoop-$i" "daemon" "RUNNABLE" "runnable" \
        "	at sun.nio.ch.EPoll.wait(java.base@17.0.12/Native Method)" \
        "	at io.netty.channel.epoll.EpollEventLoop.epollWait(EpollEventLoop.java:306)" \
        "	at io.netty.channel.epoll.EpollEventLoop.run(EpollEventLoop.java:363)"
done

# === KAFKA CONSUMER (3 threads) ===
for i in $(seq 1 3); do
    emit_thread "org.springframework.kafka-$i-C-1" "daemon" "RUNNABLE" "runnable" \
        "	at sun.nio.ch.EPoll.wait(java.base@17.0.12/Native Method)" \
        "	at org.apache.kafka.clients.consumer.internals.ConsumerNetworkClient.poll(ConsumerNetworkClient.java:265)" \
        "	at org.apache.kafka.clients.consumer.KafkaConsumer.poll(KafkaConsumer.java:1206)"
done

# === LEAKED THREADS (250 — thread leak from background job) ===
for i in $(seq 1 250); do
    emit_thread "background-worker-$i" "daemon" "TIMED_WAITING (sleeping)" "waiting on condition" \
        "	at java.lang.Thread.sleep(java.base@17.0.12/Native Method)" \
        "	at com.megacorp.orderservice.legacy.LegacyReportGenerator.generateReport(LegacyReportGenerator.java:112)" \
        "	at com.megacorp.orderservice.legacy.LegacyReportGenerator.lambda\$startAsync\$0(LegacyReportGenerator.java:98)"
done

# === ForkJoinPool (16 threads) ===
for i in $(seq 1 16); do
    emit_thread "ForkJoinPool.commonPool-worker-$i" "daemon" "WAITING (parking)" "waiting on condition" \
        "	at jdk.internal.misc.Unsafe.park(java.base@17.0.12/Native Method)" \
        "	at java.util.concurrent.ForkJoinPool.awaitWork(java.base@17.0.12/ForkJoinPool.java:1623)" \
        "	at java.util.concurrent.ForkJoinPool.runWorker(java.base@17.0.12/ForkJoinPool.java:1740)" \
        "	at java.util.concurrent.ForkJoinPool\$WorkQueue.topLevelExec(java.base@17.0.12/ForkJoinPool.java:1112)" \
        "	at java.util.concurrent.ForkJoinWorkerThread.run(java.base@17.0.12/ForkJoinWorkerThread.java:188)"
done

# === CUSTOM POOL: report-executor (100 threads, 80 BLOCKED on DB) ===
for i in $(seq 1 80); do
    emit_thread "report-executor-$i" "" "BLOCKED (on object monitor)" "waiting for monitor entry" \
        "	at com.megacorp.orderservice.reporting.ReportDAO.getReportData(ReportDAO.java:156)" \
        "	- waiting to lock <0x00000006c8f12340> (a com.megacorp.orderservice.reporting.ReportDAO)" \
        "	at com.megacorp.orderservice.reporting.ReportService.generateMonthlyReport(ReportService.java:78)" \
        "	at com.megacorp.orderservice.reporting.ReportService\$\$SpringCGLIB\$\$0.generateMonthlyReport(<generated>)"
done

for i in $(seq 81 100); do
    emit_thread "report-executor-$i" "" "RUNNABLE" "runnable" \
        "	at com.megacorp.orderservice.reporting.ReportService.formatData(ReportService.java:112)" \
        "	at com.megacorp.orderservice.reporting.ReportService\$\$SpringCGLIB\$\$0.formatData(<generated>)"
done

# === EUREKA (2 threads) ===
emit_thread "Eureka-DiscoveryClient-HeartbeatExecutor" "daemon" "TIMED_WAITING (sleeping)" "waiting on condition" \
    "	at java.lang.Thread.sleep(java.base@17.0.12/Native Method)" \
    "	at com.netflix.discovery.TimedSupervisorTask.run(TimedSupervisorTask.java:79)"

emit_thread "Eureka-DiscoveryClient-CacheRefreshExecutor" "daemon" "TIMED_WAITING (sleeping)" "waiting on condition" \
    "	at java.lang.Thread.sleep(java.base@17.0.12/Native Method)" \
    "	at com.netflix.discovery.TimedSupervisorTask.run(TimedSupervisorTask.java:79)"

# === GC AND JVM INTERNAL THREADS (200+) ===
for i in $(seq 1 8); do
    emit_thread "GC Thread#$i" "" "RUNNABLE" "runnable" \
        "	at java.lang.Thread.run(java.base@17.0.12/Thread.java:840)"
done

for i in $(seq 1 4); do
    emit_thread "G1 Refine#$i" "" "WAITING (parking)" "waiting on condition" \
        "	at jdk.internal.misc.Unsafe.park(java.base@17.0.12/Native Method)"
done

emit_thread "G1 Young RemSet Sampling" "" "TIMED_WAITING (parking)" "waiting on condition" \
    "	at jdk.internal.misc.Unsafe.park(java.base@17.0.12/Native Method)"

emit_thread "VM Thread" "" "RUNNABLE" "runnable" ""
emit_thread "Signal Dispatcher" "daemon" "RUNNABLE" "waiting on condition" ""
emit_thread "Finalizer" "daemon" "WAITING (on object monitor)" "in Object.wait()" \
    "	at java.lang.Object.wait(java.base@17.0.12/Native Method)" \
    "	- waiting on <0x00000006c0205710> (a java.lang.ref.ReferenceQueue\$Lock)" \
    "	at java.lang.ref.ReferenceQueue.remove(java.base@17.0.12/ReferenceQueue.java:155)" \
    "	at java.lang.ref.ReferenceQueue.remove(java.base@17.0.12/ReferenceQueue.java:176)" \
    "	at java.lang.ref.Finalizer\$FinalizerThread.run(java.base@17.0.12/Finalizer.java:172)"
emit_thread "Reference Handler" "daemon" "WAITING (on object monitor)" "in Object.wait()" \
    "	at java.lang.Object.wait(java.base@17.0.12/Native Method)" \
    "	- waiting on <0x00000006c0205a10> (a java.lang.ref.Reference\$ReferenceHandler)" \
    "	at java.lang.ref.Reference\$ReferenceHandler.run(java.base@17.0.12/Reference.java:265)"

# === MISC DAEMON THREADS (fill to ~1000+) ===
for i in $(seq 1 50); do
    emit_thread "pool-3-thread-$i" "daemon" "WAITING (parking)" "waiting on condition" \
        "	at jdk.internal.misc.Unsafe.park(java.base@17.0.12/Native Method)" \
        "	at java.util.concurrent.locks.LockSupport.park(java.base@17.0.12/LockSupport.java:341)" \
        "	at java.util.concurrent.ThreadPoolExecutor.getTask(java.base@17.0.12/ThreadPoolExecutor.java:1071)" \
        "	at java.util.concurrent.ThreadPoolExecutor.runWorker(java.base@17.0.12/ThreadPoolExecutor.java:1132)"
done

for i in $(seq 1 50); do
    emit_thread "pool-4-thread-$i" "daemon" "TIMED_WAITING (parking)" "waiting on condition" \
        "	at jdk.internal.misc.Unsafe.park(java.base@17.0.12/Native Method)" \
        "	at java.util.concurrent.locks.LockSupport.parkNanos(java.base@17.0.12/LockSupport.java:252)" \
        "	at java.util.concurrent.ScheduledThreadPoolExecutor\$DelayedWorkQueue.take(java.base@17.0.12/ScheduledThreadPoolExecutor.java:1176)"
done

# === DEADLOCK SECTION ===
cat >> "$OUTPUT" << 'DEADLOCK'

Found one Java-level deadlock:
=============================
"http-nio-8080-exec-196":
  waiting to lock monitor 0x00007f8a0c004e18 (object 0x00000006c2d40120, a com.megacorp.orderservice.service.OrderProcessingService),
  which is held by "http-nio-8080-exec-151"

"http-nio-8080-exec-151":
  waiting to lock monitor 0x00007f8a0c004f28 (object 0x00000006c8f12340, a com.megacorp.orderservice.reporting.ReportDAO),
  which is held by "report-executor-1"

"report-executor-1":
  waiting to lock monitor 0x00007f8a0c005038 (object 0x00000006c5ab3020, a java.util.concurrent.SynchronousQueue$TransferStack),
  which is held by "http-nio-8080-exec-196"

Java stack information for the threads listed above:
===================================================
Found 1 deadlock.

DEADLOCK

TOTAL=$(grep -c '^"' "$OUTPUT")
echo "Generated production-scale dump: $OUTPUT"
echo "Total threads: $TOTAL"
echo "Lines: $(wc -l < "$OUTPUT")"
