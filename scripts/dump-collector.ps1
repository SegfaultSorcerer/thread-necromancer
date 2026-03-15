# dump-collector.ps1 — Discover JVM processes and capture thread dumps
# Part of thread-necromancer: "Raising insights from dead threads"

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$Command,

    [Parameter(Position=1)]
    [string]$Pid_Or_Arg1,

    [Parameter(Position=2)]
    [string]$Arg2,

    [Parameter(Position=3)]
    [string]$Arg3,

    [Parameter(Position=4)]
    [string]$Arg4
)

$ErrorActionPreference = "Stop"
$DefaultOutputDir = ".thread-necromancer\dumps"

function Show-Usage {
    Write-Host @"
Usage: dump-collector.ps1 <command> [options]

Commands:
  list                              List running JVM processes
  capture <PID> [output-dir]        Capture a single thread dump
  watch <PID> [count] [interval] [output-dir]
                                    Capture multiple dumps over time
  deadlock <PID>                    Check for deadlocks only
"@
}

function Format-Uptime {
    param([int]$Seconds)
    $hours = [math]::Floor($Seconds / 3600)
    $mins = [math]::Floor(($Seconds % 3600) / 60)
    return "{0}h {1:D2}m" -f $hours, $mins
}

function Get-JVMProcesses {
    Write-Host "PID       MAIN_CLASS                                    UPTIME      ARGS"
    Write-Host "--------- --------------------------------------------- ----------- ----"

    $jcmdPath = Get-Command jcmd -ErrorAction SilentlyContinue
    if ($jcmdPath) {
        $output = & jcmd 2>$null
        foreach ($line in $output) {
            if ($line -match '^\s*(\d+)\s+(.+)$') {
                $pid = $Matches[1]
                $mainClass = $Matches[2]

                if ($mainClass -match 'jcmd|JCmd') { continue }

                $uptime = "N/A"
                try {
                    $uptimeOutput = & jcmd $pid VM.uptime 2>$null
                    if ($uptimeOutput -match '([\d.]+)\s*s') {
                        $secs = [int][math]::Floor([double]$Matches[1])
                        $uptime = Format-Uptime $secs
                    }
                } catch {}

                if ($mainClass.Length -gt 45) {
                    $mainClass = $mainClass.Substring(0, 42) + "..."
                }

                Write-Host ("{0,-9} {1,-45} {2,-11}" -f $pid, $mainClass, $uptime)
            }
        }
    } else {
        $jpsPath = Get-Command jps -ErrorAction SilentlyContinue
        if ($jpsPath) {
            $output = & jps -l 2>$null
            foreach ($line in $output) {
                if ($line -match '^\s*(\d+)\s+(.+)$') {
                    $pid = $Matches[1]
                    $mainClass = $Matches[2]
                    if ($mainClass -match 'jps|Jps') { continue }
                    if ($mainClass.Length -gt 45) {
                        $mainClass = $mainClass.Substring(0, 42) + "..."
                    }
                    Write-Host ("{0,-9} {1,-45} {2,-11}" -f $pid, $mainClass, "N/A")
                }
            }
        } else {
            Write-Host "Error: Neither jcmd nor jps found." -ForegroundColor Red
            exit 1
        }
    }
}

function Invoke-Capture {
    param(
        [string]$TargetPid,
        [string]$OutputDir = $DefaultOutputDir,
        [string]$Suffix = ""
    )

    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        Write-Host "Created output directory: $OutputDir" -ForegroundColor Green
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $filename = "thread-dump-$TargetPid-$timestamp$Suffix.txt"
    $filepath = Join-Path $OutputDir $filename

    # Write header
    $header = @"
=== THREAD DUMP ===
captured_at: $(Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
pid: $TargetPid
"@

    $jcmdPath = Get-Command jcmd -ErrorAction SilentlyContinue
    if ($jcmdPath) {
        try {
            $version = & jcmd $TargetPid VM.version 2>$null
            if ($version) {
                $header += "`njvm_version: $($version | Select-Object -First 1)"
            }
        } catch {}
    }

    $header += "`n===`n"
    Set-Content -Path $filepath -Value $header

    # Capture dump
    $captured = $false
    if ($jcmdPath) {
        try {
            $dump = & jcmd $TargetPid Thread.print -l 2>$null
            Add-Content -Path $filepath -Value ($dump -join "`n")
            $captured = $true
        } catch {}
    }

    if (-not $captured) {
        $jstackPath = Get-Command jstack -ErrorAction SilentlyContinue
        if ($jstackPath) {
            try {
                $dump = & jstack -l $TargetPid 2>$null
                Add-Content -Path $filepath -Value ($dump -join "`n")
                $captured = $true
            } catch {}
        }
    }

    if (-not $captured) {
        Remove-Item -Path $filepath -ErrorAction SilentlyContinue
        Write-Host "Error: Failed to capture thread dump for PID $TargetPid" -ForegroundColor Red
        exit 1
    }

    Write-Host "Captured thread dump: $filepath" -ForegroundColor Green
    return $filepath
}

function Invoke-Watch {
    param(
        [string]$TargetPid,
        [int]$Count = 3,
        [int]$Interval = 5,
        [string]$OutputDir = $DefaultOutputDir
    )

    Write-Host "Capturing $Count thread dumps at ${Interval}s intervals for PID $TargetPid..." -ForegroundColor Cyan

    $files = @()
    for ($i = 1; $i -le $Count; $i++) {
        Write-Host "`n--- Dump $i/$Count ---" -ForegroundColor Cyan
        $file = Invoke-Capture -TargetPid $TargetPid -OutputDir $OutputDir -Suffix "-$i"
        $files += $file

        if ($i -lt $Count) {
            Write-Host "Waiting ${Interval}s..." -ForegroundColor Gray
            Start-Sleep -Seconds $Interval
        }
    }

    Write-Host "`nDone. Captured $Count dumps:" -ForegroundColor Green
    $files | ForEach-Object { Write-Output $_ }
}

function Test-Deadlock {
    param([string]$TargetPid)

    Write-Host "Checking for deadlocks in PID $TargetPid..." -ForegroundColor Cyan

    $output = ""
    $jcmdPath = Get-Command jcmd -ErrorAction SilentlyContinue
    if ($jcmdPath) {
        $output = & jcmd $TargetPid Thread.print -l 2>$null | Out-String
    } else {
        $jstackPath = Get-Command jstack -ErrorAction SilentlyContinue
        if ($jstackPath) {
            $output = & jstack -l $TargetPid 2>$null | Out-String
        }
    }

    if ($output -match "Found.*deadlock") {
        Write-Host "DEADLOCK DETECTED" -ForegroundColor Red
        $output -split "`n" | Where-Object { $_ -match "deadlock|waiting to lock|which is held" } | ForEach-Object {
            Write-Host $_ -ForegroundColor Red
        }
    } else {
        Write-Host "No deadlocks detected." -ForegroundColor Green
    }
}

# Main
switch ($Command.ToLower()) {
    "list" { Get-JVMProcesses }
    "capture" {
        if (-not $Pid_Or_Arg1) { Write-Host "Error: capture requires a PID." -ForegroundColor Red; exit 1 }
        $outDir = if ($Arg2) { $Arg2 } else { $DefaultOutputDir }
        Invoke-Capture -TargetPid $Pid_Or_Arg1 -OutputDir $outDir
    }
    "watch" {
        if (-not $Pid_Or_Arg1) { Write-Host "Error: watch requires a PID." -ForegroundColor Red; exit 1 }
        $count = if ($Arg2) { [int]$Arg2 } else { 3 }
        $interval = if ($Arg3) { [int]$Arg3 } else { 5 }
        $outDir = if ($Arg4) { $Arg4 } else { $DefaultOutputDir }
        Invoke-Watch -TargetPid $Pid_Or_Arg1 -Count $count -Interval $interval -OutputDir $outDir
    }
    "deadlock" {
        if (-not $Pid_Or_Arg1) { Write-Host "Error: deadlock requires a PID." -ForegroundColor Red; exit 1 }
        Test-Deadlock -TargetPid $Pid_Or_Arg1
    }
    default {
        Write-Host "Error: Unknown command '$Command'" -ForegroundColor Red
        Show-Usage
        exit 1
    }
}
