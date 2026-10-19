[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# =============================================================================
# dev-forge : Optimization Level 2 (Recommended)
# Scope: Level 1 + Scheduled Tasks, Telemetry, Safe Memory/NTFS Registry,
#        Fixed Pagefile, Build Environment Variables
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
$BackupDir = "C:\backup"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }

$Today = (Get-Date).ToString('yyyyMMdd')
$LogFile = "$LogDir\optimize-level2-$Today.log"
$RegBackupFile = "$BackupDir\reg_backup_level2_$Today.reg"

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

# Ejecutar Nivel 1 primero
$Level1Path = "$PSScriptRoot\optimize-level1-conservative.ps1"
if (-not (Test-Path $Level1Path)) {
    $Level1Path = "C:\forge\provision\windows\optimize-level1-conservative.ps1"
}
if (Test-Path $Level1Path) {
    & $Level1Path -Rollback:$Rollback
}

Write-Log "=== INICIANDO OPTIMIZACION NIVEL 2 (RECOMENDADO) [Rollback=$Rollback] ==="

$ScheduledTasks = @(
    "\Microsoft\Windows\Customer Experience Improvement Program\Consolidator",
    "\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip",
    "\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
    "\Microsoft\Windows\Application Experience\ProgramDataUpdater",
    "\Microsoft\Windows\Autochk\Proxy",
    "\Microsoft\Windows\Defrag\ScheduledDefrag",
    "\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner",
    "\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector",
    "\Microsoft\Windows\Feedback\Siuf\DmClient",
    "\Microsoft\Windows\Maps\MapsUpdateTask",
    "\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem",
    "\Microsoft\Windows\Windows Error Reporting\QueueReporting"
)

if ($Rollback) {
    Write-Log "Iniciando Rollback de Nivel 2..." "WARN"

    foreach ($task in $ScheduledTasks) {
        Write-Log "Habilitando tarea programada: $task..."
        $tPath = $task.Substring(0, $task.LastIndexOf('\') + 1)
        $tName = $task.Substring($task.LastIndexOf('\') + 1)
        Enable-ScheduledTask -TaskPath $tPath -TaskName $tName -ErrorAction SilentlyContinue | Out-Null
    }

    # Restaurar registro
    if (Test-Path $RegBackupFile) {
        Write-Log "Restaurando registro desde $RegBackupFile..."
        reg import $RegBackupFile 2>$null
    } else {
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 0 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsDisableLastAccessUpdate" -Value 2 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsDisable8dot3NameCreation" -Value 2 -ErrorAction SilentlyContinue
    }

    # Restaurar Pagefile a gestionado por el sistema
    Write-Log "Restaurando pagefile gestionado por el sistema..."
    $System = Get-CimInstance Win32_ComputerSystem
    $System.AutomaticManagedPagefile = $true
    Set-CimInstance -CimInstance $System -ErrorAction SilentlyContinue

    Write-Log "=== ROLLBACK NIVEL 2 COMPLETADO ===" "SUCCESS"
    return
}

# 1. Backup de Registro
Write-Log "Creando backup del registro en $RegBackupFile..."
reg export "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "$BackupDir\mem_mgmt_$Today.reg" /y 2>$null
reg export "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" "$BackupDir\filesystem_$Today.reg" /y 2>$null

# 2. Deshabilitar Tareas Programadas
Write-Log "Deshabilitando tareas programadas de telemetria y diagnosticos..."
foreach ($task in $ScheduledTasks) {
    $taskPath = $task.Substring(0, $task.LastIndexOf('\') + 1)
    $taskName = $task.Substring($task.LastIndexOf('\') + 1)
    $t = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    if ($t -and $t.State -ne 'Disabled') {
        Write-Log "Deshabilitando tarea: $task..."
        Disable-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null
    }
}

# 3. Politicas y Registro de Telemetria
Write-Log "Aplicando politicas de supresion de telemetria y publicidad..."
$DataCollectionPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
if (-not (Test-Path $DataCollectionPath)) { New-Item -Path $DataCollectionPath -Force | Out-Null }
Set-ItemProperty -Path $DataCollectionPath -Name "AllowTelemetry" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $DataCollectionPath -Name "DoNotShowFeedbackNotifications" -Value 1 -Type DWord -Force

$CloudContentPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
if (-not (Test-Path $CloudContentPath)) { New-Item -Path $CloudContentPath -Force | Out-Null }
Set-ItemProperty -Path $CloudContentPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force

$WindowsUpdateAU = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
if (-not (Test-Path $WindowsUpdateAU)) { New-Item -Path $WindowsUpdateAU -Force | Out-Null }
Set-ItemProperty -Path $WindowsUpdateAU -Name "NoAutoUpdate" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $WindowsUpdateAU -Name "AUOptions" -Value 2 -Type DWord -Force

# 4. Registro Seguro: Memoria NT y Sistema de Archivos NTFS
Write-Log "Optimizando Memory Management y subsistema NTFS..."
$MemMgmt = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
Set-ItemProperty -Path $MemMgmt -Name "DisablePagingExecutive" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $MemMgmt -Name "LargeSystemCache" -Value 0 -Type DWord -Force
Set-ItemProperty -Path $MemMgmt -Name "ClearPageFileAtShutdown" -Value 0 -Type DWord -Force

$FileSystem = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
Set-ItemProperty -Path $FileSystem -Name "NtfsDisableLastAccessUpdate" -Value 1 -Type DWord -Force
Set-ItemProperty -Path $FileSystem -Name "NtfsDisable8dot3NameCreation" -Value 1 -Type DWord -Force

# 5. Archivo de Paginacion Fijo (4096 MB)
Write-Log "Fijando tamano de archivo de paginacion a 4096 MB..."
try {
    $System = Get-CimInstance Win32_ComputerSystem
    $System.AutomaticManagedPagefile = $false
    Set-CimInstance -CimInstance $System -ErrorAction SilentlyContinue

    Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | Remove-CimInstance -ErrorAction SilentlyContinue
    New-CimInstance -ClassName Win32_PageFileSetting -Property @{
        Name = "C:\pagefile.sys"
        InitialSize = 4096
        MaximumSize = 4096
    } -ErrorAction SilentlyContinue | Out-Null
    Write-Log "Pagefile configurado a 4096 MB fijo en C:\pagefile.sys." "SUCCESS"
} catch {
    Write-Log "Aviso al fijar Pagefile: $_" "WARN"
}

# 6. Variables de Entorno de Build y Cache Global
Write-Log "Configurando variables de entorno globales para toolchains de build..."
[Environment]::SetEnvironmentVariable("TEMP", "C:\tmp", "Machine")
[Environment]::SetEnvironmentVariable("TMP", "C:\tmp", "Machine")
[Environment]::SetEnvironmentVariable("CARGO_HOME", "C:\cargo", "Machine")
[Environment]::SetEnvironmentVariable("RUSTUP_HOME", "C:\rustup", "Machine")
[Environment]::SetEnvironmentVariable("CARGO_TARGET_DIR", "C:\target", "Machine")
[Environment]::SetEnvironmentVariable("CARGO_BUILD_JOBS", "2", "Machine")
[Environment]::SetEnvironmentVariable("GOPATH", "C:\go", "Machine")
[Environment]::SetEnvironmentVariable("GOCACHE", "C:\tmp\go-cache", "Machine")
[Environment]::SetEnvironmentVariable("NUGET_PACKAGES", "C:\nuget-cache", "Machine")
[Environment]::SetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", "1", "Machine")
[Environment]::SetEnvironmentVariable("GIT_OPTIONAL_LOCKS", "0", "Machine")
[Environment]::SetEnvironmentVariable("MAVEN_OPTS", "-Xmx3584m -XX:+UseG1GC -Dfile.encoding=UTF-8", "Machine")
[Environment]::SetEnvironmentVariable("GRADLE_OPTS", "-Xmx3584m -Dorg.gradle.jvmargs=""-Xmx3584m -XX:+UseG1GC"" -Dorg.gradle.parallel=true", "Machine")

Write-Log "=== OPTIMIZACION NIVEL 2 (RECOMENDADO) COMPLETADA CON EXITO ===" "SUCCESS"
