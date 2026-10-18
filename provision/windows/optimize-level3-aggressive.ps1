[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# =============================================================================
# dev-forge : Optimization Level 3 (Aggressive)
# Scope: Level 2 + Processor C-States Off, Core Unparking, Scheduler Quantum Tuning
# =============================================================================

param(
    [switch]$Rollback = $false
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "[ERROR] Este script requiere privilegios elevados de Administrador."
    exit 1
}

$LogDir = "C:\logs"
$Today = (Get-Date).ToString('yyyyMMdd')
$LogFile = "$LogDir\optimize-level3-$Today.log"

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

# Ejecutar Nivel 2 primero
$Level2Path = "$PSScriptRoot\optimize-level2-recommended.ps1"
if (Test-Path $Level2Path) {
    & $Level2Path -Rollback:$Rollback
}

Write-Log "=== INICIANDO OPTIMIZACION NIVEL 3 (AGRESIVO) [Rollback=$Rollback] ==="

if ($Rollback) {
    Write-Log "Iniciando Rollback de Nivel 3..." "WARN"
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 2 -ErrorAction SilentlyContinue
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CSTATEMAX 1 2>$null
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 0 2>$null
    powercfg /setactive SCHEME_CURRENT
    Write-Log "=== ROLLBACK NIVEL 3 COMPLETADO ===" "SUCCESS"
    return
}

# 1. Ajustes de latencia de procesador (C-States y Core Parking)
Write-Log "Desactivando C-States profundos y Core Parking para latencia cero de wake..."
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CSTATEMAX 0 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100 2>$null
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100 2>$null
powercfg /setactive SCHEME_CURRENT

# 2. Quantum del Planificador de Hilos NT (Win32PrioritySeparation = 0x26 = 38)
Write-Log "Ajustando Quantum del planificador NT para hilos de compilacion balanceados (0x26)..."
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 38 -Type DWord -Force

Write-Log "=== OPTIMIZACION NIVEL 3 (AGRESIVO) COMPLETADA CON EXITO ===" "SUCCESS"
