# dump-parser.ps1 — Parse raw thread dumps into structured sections
# Part of thread-necromancer: "Raising insights from dead threads"

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$DumpFile
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $DumpFile)) {
    Write-Error "File not found: $DumpFile"
    exit 1
}

$content = Get-Content $DumpFile -Raw
$lines = Get-Content $DumpFile

# --- Metadata ---

function Write-Metadata {
    Write-Output "=== DUMP METADATA ==="

    $capturedAt = ($lines | Select-String '^captured_at:\s*(.+)' | Select-Object -First 1)
    $pid = ($lines | Select-String '^pid:\s*(.+)' | Select-Object -First 1)
    $jvmVersion = ($lines | Select-String '^jvm_version:\s*(.+)' | Select-Object -First 1)

    $capturedAtVal = if ($capturedAt) { $capturedAt.Matches[0].Groups[1].Value } else { "unknown" }
    $pidVal = if ($pid) { $pid.Matches[0].Groups[1].Value } else { "unknown" }
    $jvmVersionVal = if ($jvmVersion) { $jvmVersion.Matches[0].Groups[1].Value } else { "unknown" }

    $totalThreads = ($lines | Where-Object { $_ -match '^"' }).Count
    $daemonThreads = ($lines | Where-Object { $_ -match 'daemon' }).Count

    Write-Output "timestamp: $capturedAtVal"
    Write-Output "jvm_version: $jvmVersionVal"
    Write-Output "pid: $pidVal"
    Write-Output "total_threads: $totalThreads"
    Write-Output "daemon_threads: $daemonThreads"
    Write-Output ""
}

# --- State Summary ---

function Write-StateSummary {
    Write-Output "=== THREAD STATE SUMMARY ==="

    $runnable = ($lines | Where-Object { $_ -match 'java\.lang\.Thread\.State: RUNNABLE' }).Count
    $timedWaiting = ($lines | Where-Object { $_ -match 'java\.lang\.Thread\.State: TIMED_WAITING' }).Count
    $blocked = ($lines | Where-Object { $_ -match 'java\.lang\.Thread\.State: BLOCKED' }).Count
    $newState = ($lines | Where-Object { $_ -match 'java\.lang\.Thread\.State: NEW' }).Count
    $terminated = ($lines | Where-Object { $_ -match 'java\.lang\.Thread\.State: TERMINATED' }).Count
    $allWaiting = ($lines | Where-Object { $_ -match 'java\.lang\.Thread\.State: WAITING' }).Count
    $waiting = $allWaiting - $timedWaiting

    Write-Output "RUNNABLE: $runnable"
    Write-Output "WAITING: $waiting"
    Write-Output "TIMED_WAITING: $timedWaiting"
    Write-Output "BLOCKED: $blocked"
    Write-Output "NEW: $newState"
    Write-Output "TERMINATED: $terminated"
    Write-Output ""
}

# --- Thread Pools ---

function Write-ThreadPools {
    Write-Output "=== THREAD POOLS ==="

    # Build thread name/state pairs
    $threadPairs = @()
    $currentName = ""

    foreach ($line in $lines) {
        if ($line -match '^"([^"]+)"') {
            $currentName = $Matches[1]
        }
        if ($line -match 'java\.lang\.Thread\.State:\s+(\S+)' -and $currentName) {
            $threadPairs += [PSCustomObject]@{ Name = $currentName; State = $Matches[1] }
            $currentName = ""
        }
    }

    $poolDefs = @(
        @{ Pattern = 'http-nio-.*-exec-'; Label = 'Tomcat NIO Executor' },
        @{ Pattern = 'http-nio-.*-Poller'; Label = 'Tomcat NIO Poller' },
        @{ Pattern = 'http-nio-.*-Acceptor'; Label = 'Tomcat Acceptor' },
        @{ Pattern = 'scheduling-'; Label = 'Spring @Scheduled' },
        @{ Pattern = '^task-'; Label = 'Spring @Async' },
        @{ Pattern = 'taskScheduler-'; Label = 'Spring TaskScheduler' },
        @{ Pattern = 'HikariPool-.*housekeeper'; Label = 'HikariCP Housekeeper' },
        @{ Pattern = 'HikariPool-.*connection'; Label = 'HikariCP Connection' },
        @{ Pattern = 'lettuce-nioEventLoop-'; Label = 'Redis Lettuce' },
        @{ Pattern = 'reactor-http-nio-'; Label = 'WebFlux/Netty' },
        @{ Pattern = 'ForkJoinPool\.commonPool'; Label = 'ForkJoinPool Common' },
        @{ Pattern = 'ForkJoinPool-'; Label = 'ForkJoinPool Custom' },
        @{ Pattern = 'pool-.*-thread-'; Label = 'Generic Thread Pool' }
    )

    $matched = @()

    foreach ($def in $poolDefs) {
        $poolThreads = $threadPairs | Where-Object { $_.Name -match $def.Pattern }
        if ($poolThreads.Count -gt 0) {
            $r = ($poolThreads | Where-Object { $_.State -eq 'RUNNABLE' }).Count
            $tw = ($poolThreads | Where-Object { $_.State -eq 'TIMED_WAITING' }).Count
            $b = ($poolThreads | Where-Object { $_.State -eq 'BLOCKED' }).Count
            $aw = ($poolThreads | Where-Object { $_.State -eq 'WAITING' }).Count
            $w = $aw - $tw

            Write-Output "pool: $($def.Label)"
            Write-Output "  total: $($poolThreads.Count), RUNNABLE: $r, WAITING: $w, TIMED_WAITING: $tw, BLOCKED: $b"

            $matched += $poolThreads
        }
    }

    $otherCount = $threadPairs.Count - $matched.Count
    if ($otherCount -gt 0) {
        Write-Output "pool: Other/System"
        Write-Output "  total: $otherCount"
    }

    Write-Output ""
}

# --- Deadlocks ---

function Write-Deadlocks {
    Write-Output "=== DEADLOCKS ==="

    if ($content -match 'Found.*[Dd]eadlock') {
        $inDeadlock = $false
        foreach ($line in $lines) {
            if ($line -match 'Found.*[Dd]eadlock') { $inDeadlock = $true }
            if ($inDeadlock) {
                Write-Output $line
                if ($inDeadlock -and $line -eq '' -and $prevLine -ne '') { break }
            }
            $prevLine = $line
        }
    } else {
        Write-Output "NONE DETECTED"
    }

    Write-Output ""
}

# --- Main ---

Write-Metadata
Write-StateSummary
Write-ThreadPools
Write-Deadlocks
