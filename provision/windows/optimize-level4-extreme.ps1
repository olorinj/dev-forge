[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# =============================================================================
# dev-forge : Optimization Level 4 (Extreme)
# Scope: Level 3 + Disable CPU Speculative Mitigations (Spectre/Meltdown),
#        Disable Defender Real-Time Protection Completely
# WARNING: Only for strictly isolated, offline, trusted build nodes!
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
$LogFile = "$LogDir\optimize-level4-$Today.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $TimeStamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $Entry = "[$TimeStamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $Entry -Encoding UTF8
    switch ($Level) {
        \"SUCCESS\" { Write-Host $Entry -ForegroundColor Green }
        \"WARN\"    { Write-Host $Entry -ForegroundColor Yellow }
        \"ERROR\"   { Write-Host $Entry -ForegroundColor Red }
        default   { Write-Host $Entry -ForegroundColor Cyan }
    }
}

# Ejecutar Nivel 3 primero
$Level3Path = "$PSScriptRoot\optimize-level3-aggressive.ps1"
if (-not (Test-Path $Level3Path)) {
    $Level3Path = "C:\forge\provision\windows\optimize-level3-aggressive.ps1"
}
if (Test-Path $Level3Path) {
    & $Level3Path -Rollback:$Rollback
}

Write-Log "=== INICIANDO OPTIMIZACION NIVEL 4 (EXTREMO) [Rollback=$Rollback] ==="

$MemMgmt = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
$DefenderBase = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender"
$DefenderRT = "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"

if ($Rollback) {
    Write-Log "Iniciando Rollback de Nivel 4..." "WARN"
    Remove-ItemProperty -Path $MemMgmt -Name "FeatureSettingsOverride" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $MemMgmt -Name "FeatureSettingsOverrideMask" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $DefenderBase -Name "DisableAntiSpyware" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $DefenderRT -Name "DisableRealtimeMonitoring" -ErrorAction SilentlyContinue
    Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction SilentlyContinue
    Write-Log "=== ROLLBACK NIVEL 4 COMPLETADO ===" "SUCCESS"
    return
}

# 1. Desactivar mitigaciones de microarquitectura (Spectre/Meltdown KPTI)
Write-Log "ADVERTENCIA: Desactivando mitigaciones de CPU para maximizar IPC y throughput de syscalls..." "WARN"
Set-ItemProperty -Path $MemMgmt -Name "FeatureSettingsOverride" -Value 3 -Type DWord -Force
Set-ItemProperty -Path $MemMgmt -Name "FeatureSettingsOverrideMask" -Value 3 -Type DWord -Force

# 2. Desactivar Proteccion en Tiempo Real de Windows Defender completamente
Write-Log "Desactivando proteccion en tiempo real de Windows Defender por completo..." "WARN"
if (-not (Test-Path $DefenderBase)) { New-Item -Path $DefenderBase -Force | Out-Null }
if (-not (Test-Path $DefenderRT)) { New-Item -Path $DefenderRT -Force | Out-Null }

Set-ItemProperty -Path $DefenderBase -Name "DisableAntiSpyware" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $DefenderRT -Name "DisableRealtimeMonitoring" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $DefenderRT -Name "DisableBehaviorMonitoring" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $DefenderRT -Name "DisableOnAccessProtection" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $DefenderRT -Name "DisableScanOnRealtimeEnable" -Value 1 -Type DWord -Force

Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue

Write-Log "=== OPTIMIZACION NIVEL 4 (EXTREMO) COMPLETADA CON EXITO ===" "SUCCESS"
