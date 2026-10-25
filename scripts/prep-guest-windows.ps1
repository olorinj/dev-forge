# =============================================================================
# dev-forge : Script de Preparacion y Optimizacion del Guest Windows
# =============================================================================
# Aplica hardening, poda de servicios innecesarios, bloqueo total de Windows
# Update, purga profunda de WinSxS con DISM, eliminacion de sombras VSS y
# llenado con ceros usando sdelete para maxima compactacion VDI.
# =============================================================================
[CmdletBinding()]
param()

$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== [dev-forge-prep] Iniciando optimizacion de Windows Server Core para VDI ===" -ForegroundColor Cyan

# 1. Bloqueo Absoluto y Permanente de Windows Update
Write-Host "1/6 Deshabilitando permanentemente el servicio y tareas de Windows Update..." -ForegroundColor Yellow
Stop-Service -Name "wuauserv" -Force
Set-Service -Name "wuauserv" -StartupType Disabled

Stop-Service -Name "UsoSvc" -Force
Set-Service -Name "UsoSvc" -StartupType Disabled

Stop-Service -Name "WaaSMedicSvc" -Force
Set-Service -Name "WaaSMedicSvc" -StartupType Disabled

# Deshabilitar tareas programadas de actualizacion
Get-ScheduledTask -TaskPath "\Microsoft\Windows\WindowsUpdate\*" | Disable-ScheduledTask
Get-ScheduledTask -TaskPath "\Microsoft\Windows\UpdateOrchestrator\*" | Disable-ScheduledTask

# Forzar directiva de grupo local (GPO) en Registro
$RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
if (-not (Test-Path $RegistryPath)) {
    New-Item -Path $RegistryPath -Force | Out-Null
}
Set-ItemProperty -Path $RegistryPath -Name "NoAutoUpdate" -Value 1 -Type DWord
Set-ItemProperty -Path $RegistryPath -Name "AUOptions" -Value 1 -Type DWord

Write-Host "   Windows Update desactivado y bloqueado por directiva." -ForegroundColor Green

# 2. Deshabilitar Servicios Innecesarios para una VM de Compilacion
Write-Host "2/6 Deshabilitando servicios prescindibles (indexacion, telemetria, spooler)..." -ForegroundColor Yellow
$ServicesToDisable = @(
    "WSearch",      # Windows Search (evita indexacion continua que degrada I/O)
    "SysMain",      # Superfetch
    "Spooler",      # Servicio de impresion
    "DiagTrack",    # Telemetria y experiencia del usuario conectado
    "dmwappushservice",
    "WerSvc"        # Windows Error Reporting
)

foreach ($svc in $ServicesToDisable) {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Stop-Service -Name $svc -Force
        Set-Service -Name $svc -StartupType Disabled
    }
}
Write-Host "   Servicios innecesarios deshabilitados." -ForegroundColor Green

# 3. Purga Profunda de WinSxS y Componentes Obsoletos de Windows
Write-Host "3/6 Purgando almacen de componentes WinSxS con DISM..." -ForegroundColor Yellow
Start-Process -FilePath "dism.exe" -ArgumentList "/online /cleanup-image /startcomponentcleanup /resetbase" -Wait -NoNewWindow
Write-Host "   Almacen de componentes WinSxS compactado y restablecido." -ForegroundColor Green

# 4. Eliminacion de Sombras de Volumen (VSS) y Puntos de Restauracion
Write-Host "4/6 Eliminando copias shadow VSS y puntos de restauracion..." -ForegroundColor Yellow
vssadmin delete shadows /all /quiet
Write-Host "   Sombras de volumen eliminadas." -ForegroundColor Green

# 5. Limpieza de Caches de Chocolatey y Archivos Temporales
Write-Host "5/6 Limpiando caches de Chocolatey y archivos temporales..." -ForegroundColor Yellow
if (Get-Command choco -ErrorAction SilentlyContinue) {
    choco cache remove --confirm
}
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Users\vagrant\AppData\Local\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# Vaciar logs de eventos
Get-EventLog -List | ForEach-Object { Clear-EventLog -LogName $_.Log -ErrorAction SilentlyContinue }
Write-Host "   Archivos temporales y caches purgados." -ForegroundColor Green

# 6. Rellenado de Ceros para Compactacion VDI (Sysinternals SDelete)
Write-Host "6/6 Rellenando con ceros los sectores libres de disco con SDelete..." -ForegroundColor Yellow
$sdeletePath = "C:\Windows\System32\sdelete.exe"
if (-not (Test-Path $sdeletePath)) {
    $sdeleteZip = "C:\Windows\Temp\sdelete.zip"
    Invoke-WebRequest -Uri "https://download.sysinternals.com/files/SDelete.zip" -OutFile $sdeleteZip
    Expand-Archive -Path $sdeleteZip -DestinationPath "C:\Windows\Temp\sdelete" -Force
    Move-Item -Path "C:\Windows\Temp\sdelete\sdelete64.exe" -Destination $sdeletePath -Force
    Remove-Item -Path $sdeleteZip -Force -ErrorAction SilentlyContinue
}

if (Test-Path $sdeletePath) {
    & $sdeletePath -accepteula -z C:
} else {
    Write-Warning "No se pudo obtener sdelete.exe; se omite zeroing en Windows."
}

Write-Host "=== [dev-forge-prep] Optimizacion de Windows finalizada con exito! ===" -ForegroundColor Green
