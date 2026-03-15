# on-test-hang.ps1 — Capture thread dump when test JVM appears hung
# PowerShell variant for Windows

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CollectorScript = Join-Path $ScriptDir "..\dump-collector.ps1"
$OutputDir = ".thread-necromancer\dumps\test-hangs"
$FlagFile = ".thread-necromancer\dump-on-test-hang.enabled"

# Check opt-in flag
if (-not (Test-Path $FlagFile)) {
    exit 0
}

# Find test JVM processes
function Find-TestJVMs {
    $pids = @()

    $jcmdPath = Get-Command jcmd -ErrorAction SilentlyContinue
    if ($jcmdPath) {
        $output = & jcmd 2>$null
        foreach ($line in $output) {
            if ($line -match '^\s*(\d+)\s+(.+)$') {
                $pid = $Matches[1]
                $mainClass = $Matches[2]

                if ($mainClass -match 'surefire|failsafe|ForkedBooter|GradleWorkerMain|gradle.*worker') {
                    $pids += $pid
                }
            }
        }
    }

    return $pids
}

$pids = Find-TestJVMs

if ($pids.Count -eq 0) {
    Write-Host "[thread-necromancer] No test JVM processes found to dump." -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

foreach ($pid in $pids) {
    Write-Host "[thread-necromancer] Capturing thread dump for hung test JVM (PID: $pid)..." -ForegroundColor Cyan

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $dumpFile = Join-Path $OutputDir "thread-dump-$pid-$timestamp.txt"

    try {
        $jcmdPath = Get-Command jcmd -ErrorAction SilentlyContinue
        if ($jcmdPath) {
            & jcmd $pid Thread.print -l > $dumpFile 2>$null
        } else {
            $jstackPath = Get-Command jstack -ErrorAction SilentlyContinue
            if ($jstackPath) {
                & jstack -l $pid > $dumpFile 2>$null
            } else {
                Write-Host "[thread-necromancer] Neither jcmd nor jstack available." -ForegroundColor Red
                continue
            }
        }
        Write-Host "[thread-necromancer] Thread dump saved: $dumpFile" -ForegroundColor Green
    } catch {
        Write-Host "[thread-necromancer] Failed to capture dump for PID $pid" -ForegroundColor Red
    }
}
