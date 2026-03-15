# on-startup.ps1 — Capture baseline thread dump after Spring Boot startup
# PowerShell variant for Windows

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutputDir = ".thread-necromancer\dumps\baselines"
$FlagFile = ".thread-necromancer\startup-baseline.enabled"

# Check opt-in flag
if (-not (Test-Path $FlagFile)) {
    exit 0
}

# Find Spring Boot processes
function Find-SpringBootJVMs {
    $pids = @()

    $jcmdPath = Get-Command jcmd -ErrorAction SilentlyContinue
    if ($jcmdPath) {
        $output = & jcmd 2>$null
        foreach ($line in $output) {
            if ($line -match '^\s*(\d+)\s+(.+)$') {
                $pid = $Matches[1]
                $mainClass = $Matches[2]

                # Skip JDK tools
                if ($mainClass -match 'jcmd|jps|jstack|surefire|failsafe|ForkedBooter') {
                    continue
                }

                # Check for Spring Boot
                try {
                    $cmdline = & jcmd $pid VM.command_line 2>$null
                    if ($cmdline -match 'spring|boot') {
                        $pids += $pid
                    }
                } catch {}
            }
        }
    }

    return $pids
}

# Wait for application to stabilize
Write-Host "[thread-necromancer] Waiting 10s for application to stabilize..." -ForegroundColor Cyan
Start-Sleep -Seconds 10

$pids = Find-SpringBootJVMs

if ($pids.Count -eq 0) {
    Write-Host "[thread-necromancer] No Spring Boot JVM found for baseline dump." -ForegroundColor Yellow
    exit 0
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

foreach ($pid in $pids) {
    Write-Host "[thread-necromancer] Capturing startup baseline for PID $pid..." -ForegroundColor Cyan

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
            }
        }
        Write-Host "[thread-necromancer] Baseline saved: $dumpFile" -ForegroundColor Green
        Write-Host "[thread-necromancer] Use '/thread-analyze $dumpFile' to analyze." -ForegroundColor Cyan
    } catch {
        Write-Host "[thread-necromancer] Failed to capture baseline for PID $pid" -ForegroundColor Red
    }
}
