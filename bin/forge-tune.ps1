[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# =============================================================================
# dev-forge : Host Resource Auto-Detection & VM Dimensioning (PowerShell)
# Directives: 50% Physical Cores (min 2), 33% Host RAM (min 4GB, 16GB->5GB),
#             Fastest Storage Directory, Dynamic Keyboard Synchronization.
# =============================================================================

$ForgeDir = (Get-Item $PSScriptRoot).Parent.FullName
$ConfigDir = Join-Path $ForgeDir "config"
$ProfilePath = Join-Path $ConfigDir "forge-host.env"

if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

function Write-Info { param([string]$msg) Write-Host "[forge-tune] $msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$msg) Write-Host "[forge-tune : OK] $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "[forge-tune : AVISO] $msg" -ForegroundColor Yellow }

Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host "         dev-forge : Dimensionador Automatico de Recursos" -ForegroundColor Cyan
Write-Host "  ================================================================`n" -ForegroundColor Cyan

Write-Info "Detectando recursos de hardware del host Windows..."

# 1. Detección de CPU
$proc = Get-CimInstance Win32_Processor | Select-Object -First 1
$cpuModel = $proc.Name.Trim()
$physCores = $proc.NumberOfCores
$logicalProcessors = $proc.NumberOfLogicalProcessors
$smtActive = if ($logicalProcessors -gt $physCores) { "ON" } else { "OFF" }

if (-not $physCores -or $physCores -lt 1) { $physCores = 2 }

# 2. Detección de RAM
$comp = Get-CimInstance Win32_ComputerSystem
$totalBytes = $comp.TotalPhysicalMemory
$totalRamGb = [math]::Round($totalBytes / 1GB)

# 3. Cálculo de vCPUs (Directiva: 50% núcleos físicos, mínimo 2)
if ($physCores -ge 4) {
    $calcVcpus = [math]::Floor($physCores / 2)
} else {
    $calcVcpus = 2
}

# 4. Cálculo de RAM (Directiva: 33% memoria host, min 4GB; caso 16GB -> 5120MB)
if ($totalRamGb -ge 14 -and $totalRamGb -le 20) {
    $calcRamMb = 5120
} else {
    $calcGb = [math]::Round($totalRamGb * 0.33)
    if ($calcGb -lt 4) { $calcGb = 4 }
    $calcRamMb = $calcGb * 1024
}

# 5. Detección de Almacenamiento Óptimo
$bestDrive = Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.SizeRemaining -gt 40GB } |
    Sort-Object SizeRemaining -Descending | Select-Object -First 1

if ($bestDrive) {
    $vboxFolder = "$($bestDrive.DriveLetter):\VirtualBox VMs"
} else {
    $vboxFolder = "C:\VirtualBox VMs"
}
if (-not (Test-Path $vboxFolder)) {
    New-Item -ItemType Directory -Path $vboxFolder -Force -ErrorAction SilentlyContinue | Out-Null
}

if (Get-Command VBoxManage -ErrorAction SilentlyContinue) {
    VBoxManage setproperty machinefolder "$vboxFolder" 2>$null
}

# 6. Detección de Idioma y Teclado
$langList = Get-WinUserLanguageList
$detectedKb = if ($langList) { $langList[0].LanguageTag } else { "es-ES" }

# 7. Escritura del Perfil config/forge-host.env
$dateStr = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$profileContent = @"
# =============================================================================
# dev-forge : Perfil de Recursos Dimensionados del Host
# Generado automaticamente por: dev-forge tune
# Fecha: $dateStr
# =============================================================================
FORGE_HOST_PROFILE_VERSION="1.0"
FORGE_HOST_OS="Windows"
FORGE_HOST_CPU_MODEL="$cpuModel"
FORGE_HOST_PHYSICAL_CORES=$physCores
FORGE_HOST_TOTAL_RAM_GB=$totalRamGb
FORGE_HOST_KEYBOARD="$detectedKb"

# Asignacion de Recursos para Maquinas Virtuales (Directivas de Arquitectura)
# - CPU: 50% de los nucleos fisicos del host (min 2)
# - RAM: ~33% de la memoria fisica del host (min 4096 MB)
FORGE_LINUX_CPUS=$calcVcpus
FORGE_LINUX_MEM=$calcRamMb
FORGE_WIN_CPUS=$calcVcpus
FORGE_WIN_MEM=$calcRamMb

# Almacenamiento de Discos Virtuales en el Host
FORGE_VBOX_FOLDER="$vboxFolder"
"@

[System.IO.File]::WriteAllText($ProfilePath, $profileContent, (New-Object System.Text.UTF8Encoding $false))

# 8. Resumen
Write-Host "RECURSOS DEL HOST DETECTADOS:" -ForegroundColor White
Write-Host "  - Procesador:        $cpuModel" -ForegroundColor Cyan
Write-Host "  - Nucleos Fisicos:   $physCores (SMT / HyperThreading: $smtActive)" -ForegroundColor Cyan
Write-Host "  - Memoria RAM Total: $totalRamGb GB" -ForegroundColor Cyan
Write-Host "  - Teclado Detectado: $detectedKb" -ForegroundColor Cyan
Write-Host "  - Carpeta Almacen:   $vboxFolder" -ForegroundColor Cyan
Write-Host ""
Write-Host "DIMENSIONAMIENTO APLICADO (Directivas dev-forge):" -ForegroundColor White
Write-Host "  - vCPUs por VM:      $calcVcpus vCPUs (50% de cores fisicos)" -ForegroundColor Green
Write-Host "  - RAM por VM:        $calcRamMb MB (~$([math]::Round($calcRamMb/1024)) GB) (33% RAM host)" -ForegroundColor Green
Write-Host "  - forge-linux:       $calcVcpus vCPUs / $calcRamMb MB" -ForegroundColor Green
Write-Host "  - forge-windows:     $calcVcpus vCPUs / $calcRamMb MB" -ForegroundColor Green
Write-Host ""
Write-Ok "Perfil guardado con exito en: $ProfilePath"
Write-Ok "El entorno dev-forge esta listo para compilar con rendimiento optimo."
