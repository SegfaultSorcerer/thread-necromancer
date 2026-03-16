# run-parser.ps1 — Find a suitable JDK (>= 11) and run DumpParser.java
# Part of thread-necromancer: "Raising insights from dead threads."

param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$DumpFile
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Parser = Join-Path $ScriptDir "DumpParser.java"

function Get-JavaMajorVersion {
    param([string]$JavaBin)
    try {
        $output = & $JavaBin -version 2>&1 | Select-Object -First 1
        if ($output -match '"(\d+)[\.\d]*"') {
            $major = [int]$Matches[1]
            # Java 8 reports as 1.8
            if ($major -eq 1 -and $output -match '"1\.(\d+)') {
                $major = [int]$Matches[1]
            }
            return $major
        }
    } catch {}
    return 0
}

function Test-SuitableJava {
    param([string]$JavaBin)
    if (-not (Test-Path $JavaBin)) { return $false }
    $version = Get-JavaMajorVersion $JavaBin
    return $version -ge 11
}

function Find-Java {
    # 1. Check java on PATH
    $pathJava = Get-Command java -ErrorAction SilentlyContinue
    if ($pathJava) {
        if (Test-SuitableJava $pathJava.Source) {
            return $pathJava.Source
        }
        $version = Get-JavaMajorVersion $pathJava.Source
        Write-Host "INFO: java on PATH is version $version (need >= 11), searching for alternatives..." -ForegroundColor Yellow
    }

    # 2. Check JAVA_HOME
    if ($env:JAVA_HOME) {
        $javaHome = Join-Path $env:JAVA_HOME "bin\java.exe"
        if (Test-SuitableJava $javaHome) {
            return $javaHome
        }
    }

    # 3. Common JDK locations on Windows
    $searchDirs = @(
        # JetBrains managed JDKs
        "$env:USERPROFILE\.jdks"
        # SDKMAN (WSL/Git Bash)
        "$env:USERPROFILE\.sdkman\candidates\java"
        # Scoop
        "$env:USERPROFILE\scoop\apps\openjdk"
        "$env:USERPROFILE\scoop\apps\temurin-lts-jdk"
        # Chocolatey
        "C:\Program Files\Eclipse Adoptium"
        "C:\Program Files\Temurin"
        "C:\Program Files\Java"
        "C:\Program Files\AdoptOpenJDK"
        "C:\Program Files\Zulu"
        "C:\Program Files\Microsoft\jdk"
        "C:\Program Files (x86)\Java"
        # Common manual installs
        "C:\Java"
        "C:\jdk"
    )

    foreach ($dir in $searchDirs) {
        if (-not (Test-Path $dir)) { continue }

        # Search for java.exe in subdirectories
        $javaBins = Get-ChildItem -Path $dir -Filter "java.exe" -Recurse -Depth 4 -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\bin\\java\.exe$' } |
            Sort-Object FullName -Descending |
            Select-Object -First 10

        foreach ($bin in $javaBins) {
            if (Test-SuitableJava $bin.FullName) {
                return $bin.FullName
            }
        }
    }

    return $null
}

# --- Main ---

$javaBin = Find-Java

if ($javaBin) {
    $version = Get-JavaMajorVersion $javaBin
    Write-Host "Using Java $version`: $javaBin" -ForegroundColor Green
    & $javaBin $Parser $DumpFile
} else {
    Write-Host "ERROR: No suitable JDK (>= 11) found." -ForegroundColor Red
    Write-Host ""
    Write-Host "DumpParser.java requires JDK 11+ for single-file source execution."
    Write-Host ""
    Write-Host "Searched:"
    Write-Host "  - java on PATH"
    Write-Host "  - JAVA_HOME ($env:JAVA_HOME)"
    Write-Host "  - ~/.jdks, Program Files\Java, Program Files\Eclipse Adoptium"
    Write-Host "  - Scoop, Chocolatey install directories"
    Write-Host ""
    Write-Host "Please either:"
    Write-Host "  1. Install JDK 11+: https://adoptium.net"
    Write-Host "  2. Set JAVA_HOME to point to a JDK 11+ installation"
    Write-Host "  3. Add a JDK 11+ bin directory to your PATH"
    exit 1
}
