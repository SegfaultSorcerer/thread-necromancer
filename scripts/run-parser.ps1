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
        # java -version writes to stderr — use Process API for reliable capture
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $JavaBin
        $pinfo.Arguments = "-version"
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($pinfo)
        $stderr = $proc.StandardError.ReadToEnd()
        $stdout = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit()
        $output = "$stderr $stdout"

        # Match version string like "17.0.2" or "1.8.0_202"
        if ($output -match '"(\d+)(\.(\d+))?') {
            $first = [int]$Matches[1]
            # Java 8 and earlier report as 1.x (e.g., "1.8.0_202")
            if ($first -eq 1 -and $Matches[3]) {
                return [int]$Matches[3]
            }
            return $first
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
        $jhJava = Join-Path $env:JAVA_HOME "bin\java.exe"
        if ((Test-Path $jhJava) -and (Test-SuitableJava $jhJava)) {
            return $jhJava
        }
    }

    # 3. Common JDK locations on Windows
    $searchRoots = @(
        # JetBrains managed JDKs
        (Join-Path $env:USERPROFILE ".jdks")
        # SDKMAN (WSL/Git Bash)
        (Join-Path $env:USERPROFILE ".sdkman\candidates\java")
        # Scoop
        (Join-Path $env:USERPROFILE "scoop\apps\openjdk")
        (Join-Path $env:USERPROFILE "scoop\apps\temurin-lts-jdk")
        (Join-Path $env:USERPROFILE "scoop\apps\temurin17-jdk")
        (Join-Path $env:USERPROFILE "scoop\apps\temurin21-jdk")
        # Chocolatey / Adoptium / standard
        "C:\Program Files\Eclipse Adoptium"
        "C:\Program Files\Temurin"
        "C:\Program Files\Java"
        "C:\Program Files\AdoptOpenJDK"
        "C:\Program Files\BellSoft"
        "C:\Program Files\Zulu"
        "C:\Program Files\Amazon Corretto"
        "C:\Program Files\Microsoft\jdk"
        "C:\Program Files\SapMachine"
        "C:\Program Files (x86)\Java"
        # Common manual installs
        "C:\Java"
        "C:\jdk"
    )

    foreach ($root in $searchRoots) {
        if (-not (Test-Path $root)) { continue }

        # Search for java.exe in bin subdirectories
        try {
            $javaBins = Get-ChildItem -Path $root -Filter "java.exe" -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -like '*\bin\java.exe' } |
                Sort-Object { $_.FullName } -Descending

            foreach ($bin in $javaBins) {
                if (Test-SuitableJava $bin.FullName) {
                    return $bin.FullName
                }
            }
        } catch {}
    }

    return $null
}

# --- Main ---

$javaBin = Find-Java

if ($javaBin) {
    $version = Get-JavaMajorVersion $javaBin
    Write-Host "Using Java ${version}: $javaBin" -ForegroundColor Green
    & $javaBin $Parser $DumpFile
    exit $LASTEXITCODE
} else {
    Write-Host "ERROR: No suitable JDK (>= 11) found." -ForegroundColor Red
    Write-Host ""
    Write-Host "DumpParser.java requires JDK 11+ for single-file source execution."
    Write-Host ""
    Write-Host "Searched:"
    Write-Host "  - java on PATH"
    if ($env:JAVA_HOME) {
        Write-Host "  - JAVA_HOME ($env:JAVA_HOME)"
    }
    Write-Host "  - $env:USERPROFILE\.jdks"
    Write-Host "  - Program Files\Java, Eclipse Adoptium, Temurin, Zulu, Corretto"
    Write-Host "  - Scoop, Chocolatey install directories"
    Write-Host ""
    Write-Host "Please either:"
    Write-Host "  1. Install JDK 11+: https://adoptium.net"
    Write-Host "  2. Set JAVA_HOME to point to a JDK 11+ installation"
    Write-Host "  3. Add a JDK 11+ bin directory to your PATH"
    exit 1
}
