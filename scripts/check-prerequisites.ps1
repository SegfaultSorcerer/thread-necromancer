# check-prerequisites.ps1 — Verify JVM diagnostic tools are available
# Part of thread-necromancer: "Raising insights from dead threads"

$ErrorActionPreference = "Continue"

$pass = 0
$warn = 0
$fail = 0

function Check-Command {
    param(
        [string]$Name,
        [string]$Required,
        [string]$Description
    )

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Host "[OK]    $($Name.PadRight(12)) $Description ($($cmd.Source))" -ForegroundColor Green
        $script:pass++
    } elseif ($Required -eq "required") {
        Write-Host "[FAIL]  $($Name.PadRight(12)) $Description - REQUIRED but not found" -ForegroundColor Red
        $script:fail++
    } else {
        Write-Host "[WARN]  $($Name.PadRight(12)) $Description - optional, not found" -ForegroundColor Yellow
        $script:warn++
    }
}

function Check-JavaVersion {
    $javaCmd = Get-Command java -ErrorAction SilentlyContinue
    if ($javaCmd) {
        $versionOutput = & java -version 2>&1 | Select-Object -First 1
        if ($versionOutput -match '"(\d+)[\.\d]*"') {
            $major = [int]$Matches[1]
            $version = $Matches[0].Trim('"')
            if ($major -ge 11) {
                Write-Host "[OK]    Java version: $version (>= 11 required)" -ForegroundColor Green
            } else {
                Write-Host "[FAIL]  Java version: $version (>= 11 required)" -ForegroundColor Red
                $script:fail++
            }
        }
    }
}

function Check-JavaHome {
    if ($env:JAVA_HOME) {
        Write-Host "[OK]    JAVA_HOME:    $env:JAVA_HOME" -ForegroundColor Green
        $jcmdPath = Join-Path $env:JAVA_HOME "bin\jcmd.exe"
        if ((Test-Path $jcmdPath) -and -not (Get-Command jcmd -ErrorAction SilentlyContinue)) {
            Write-Host "[HINT]  jcmd found at $jcmdPath but not on PATH" -ForegroundColor Yellow
            Write-Host "        Add to PATH: `$env:Path += `";$env:JAVA_HOME\bin`"" -ForegroundColor Gray
        }
    } else {
        Write-Host "[WARN]  JAVA_HOME not set. JDK tools may not be on PATH." -ForegroundColor Yellow
        $script:warn++
    }
}

Write-Host "thread-necromancer - prerequisite check"
Write-Host "========================================"
Write-Host ""

Write-Host "--- Required ---"
Check-Command "java" "required" "Java runtime"
Check-JavaVersion

Write-Host ""
Write-Host "--- JDK Diagnostic Tools ---"
Check-Command "jcmd" "optional" "JVM diagnostic command (preferred)"
Check-Command "jstack" "optional" "JVM stack trace tool (fallback)"
Check-Command "jps" "optional" "JVM process listing"

Write-Host ""
Write-Host "--- Environment ---"
Check-JavaHome

Write-Host ""
Write-Host "========================================"
Write-Host "Results: $pass passed, $warn warnings, $fail failed"

if ($fail -gt 0) {
    Write-Host ""
    Write-Host "Some required prerequisites are missing." -ForegroundColor Red
    exit 1
}

$hasJcmd = Get-Command jcmd -ErrorAction SilentlyContinue
$hasJstack = Get-Command jstack -ErrorAction SilentlyContinue
if (-not $hasJcmd -and -not $hasJstack) {
    Write-Host ""
    Write-Host "WARNING: Neither jcmd nor jstack found." -ForegroundColor Yellow
    Write-Host "Install a full JDK (not just JRE) to get them."
    exit 1
}

Write-Host ""
Write-Host "All prerequisites met. thread-necromancer is ready." -ForegroundColor Green
exit 0
