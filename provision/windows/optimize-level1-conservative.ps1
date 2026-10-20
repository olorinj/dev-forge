param(
    [switch]$Rollback = $false
)

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# =============================================================================
# dev-forge : Optimization Level 1 (Conservative)
# Scope: Essential Services, Ultimate Performance Power Plan, Defender Exclusions
# =============================================================================

# 1. Administrator Check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "[ERROR] Este script requiere privilegios elevados de Administrador."
    exit 1
}

$LogDir = "C:\logs"
$BackupDir = "C:\backup"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

$Today = (Get-Date).ToString('yyyyMMdd')
$LogFile = "$LogDir\optimize-level1-$Today.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $TimeStamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $Entry = "[$TimeStamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $Entry -Encoding UTF8
    switch ($Level) {
        "SUCCESS" { Write-Host $Entry -ForegroundColor Green }
        "WARN"    { Write-Host $Entry -ForegroundColor Yellow }
        "ERROR"   { Write-Host $Entry -ForegroundColor Red }
        default   { Write-Host $Entry -ForegroundColor Cyan }
    }
}

Write-Log "=== INICIANDO OPTIMIZACION NIVEL 1 (CONSERVADOR) [Rollback=$Rollback] ==="

# Servicios Conservadores
$ConservativeServices = @(
    "SysMain",
    "WSearch",
    "DiagTrack",
    "BITS",
    "Spooler",
    "Audiosrv",
    "AudioEndpointBuilder",
    "Fax",
    "WIA-Rpc",
    "stisvc",
    "MapsBroker",
    "bthserv",
    "lfsvc",
    "SensorService",
    "RetailDemo",
    "SCardSvr",
    "PrintWorkflow",
    "AjRouter",
    "ShellHWDetection",
    "TrkWks"
)

# Exclusiones Defender
$ExclusionPaths = @(
    "C:\forge",
    "C:\workspace",
    "C:\target",
    "C:\tmp",
    "C:\cargo",
    "C:\rustup",
    "C:\go",
    "C:\nuget-cache",
    "C:\pnpm-store",
    "$env:USERPROFILE\.cargo",
    "$env:USERPROFILE\.rustup",
    "$env:USERPROFILE\.m2",
    "$env:USERPROFILE\.gradle",
    "$env:USERPROFILE\.nuget",
    "$env:USERPROFILE\go"
)

$ExclusionProcesses = @(
    "cl.exe", "link.exe", "lib.exe", "clang.exe", "clang++.exe", "lld-link.exe",
    "ninja.exe", "cmake.exe", "msbuild.exe", "devenv.exe", "rustc.exe", "cargo.exe",
    "rust-analyzer.exe", "sccache.exe", "go.exe", "dotnet.exe", "csc.exe", "vbc.exe",
    "java.exe", "javac.exe", "mvn.exe", "gradle.exe", "node.exe", "git.exe"
)

$ExclusionExtensions = @(
    ".obj", ".lib", ".pdb", ".ilk", ".exp",
    ".rlib", ".rmeta",
    ".ninja", ".ninja_log",
    ".class", ".jar",
    ".tlog", ".lastbuildstate"
)

if ($Rollback) {
    Write-Log "Iniciando Rollback de Nivel 1..." "WARN"

    foreach ($svcName in $ConservativeServices) {
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if ($svc) {
            Write-Log "Restaurando servicio $svcName a Manual..."
            Set-Service -Name $svcName -StartupType Manual -ErrorAction SilentlyContinue
        }
    }

    Write-Log "Restaurando Plan de Energia equilibrado (Balanced)..."
    powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e 2>$null

    Write-Log "Eliminando exclusiones de Windows Defender..."
    foreach ($p in $ExclusionPaths) { Remove-MpPreference -ExclusionPath $p -ErrorAction SilentlyContinue }
    foreach ($pr in $ExclusionProcesses) { Remove-MpPreference -ExclusionProcess $pr -ErrorAction SilentlyContinue }
    foreach ($ext in $ExclusionExtensions) { Remove-MpPreference -ExclusionExtension $ext -ErrorAction SilentlyContinue }

    Write-Log "=== ROLLBACK NIVEL 1 COMPLETADO ===" "SUCCESS"
    return
}

# 2. Servicios
Write-Log "Configurando servicios conservadores..."
foreach ($svcName in $ConservativeServices) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -eq 'Running') {
            Write-Log "Deteniendo servicio $svcName..."
            Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
        }
        if ($svc.StartType -ne 'Disabled') {
            Write-Log "Deshabilitando servicio $svcName..."
            Set-Service -Name $svcName -StartupType Disabled -ErrorAction SilentlyContinue
        }
    }
}

# 3. Plan de Energia Ultimate Performance / High Performance
Write-Log "Configurando esquema de energia de Maximo Rendimiento..."
$UltimateGUID = "e9a42b02-d5df-448d-aa00-03f14749eb61"
$HighPerfGUID = "8c5e7fda-e8f1-4a01-9f58-3097d2d61f16"

$activeScheme = powercfg -duplicatescheme $UltimateGUID 2>$null
if ($LASTEXITCODE -ne 0) {
    powercfg -duplicatescheme $HighPerfGUID 2>$null
    powercfg /setactive $HighPerfGUID
    Write-Log "Activado esquema de Alto Rendimiento (High Performance)." "SUCCESS"
} else {
    powercfg /setactive $UltimateGUID
    Write-Log "Activado esquema Ultimate Performance." "SUCCESS"
}

# 4. Exclusiones y Desactivación de Monitoreo en Tiempo Real de Microsoft Defender
Write-Log "Desactivando monitoreo en tiempo real de Microsoft Defender (evita bloqueos de compilacion)..."
Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true -DisableIOAVProtection $true -DisableScriptScanning $true -ErrorAction SilentlyContinue

Write-Log "Aplicando exclusiones de carpetas, procesos y extensiones en Microsoft Defender..."
foreach ($path in $ExclusionPaths) {
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    Add-MpPreference -ExclusionPath $path -ErrorAction SilentlyContinue
}
foreach ($proc in $ExclusionProcesses) {
    Add-MpPreference -ExclusionProcess $proc -ErrorAction SilentlyContinue
}
foreach ($ext in $ExclusionExtensions) {
    Add-MpPreference -ExclusionExtension $ext -ErrorAction SilentlyContinue
}

Write-Log "=== OPTIMIZACION NIVEL 1 (CONSERVADOR) COMPLETADA CON EXITO ===" "SUCCESS"
