[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 70-packagers: Instalando WiX Toolset e InnoSetup ===" -ForegroundColor Cyan

# Herramientas para generar instaladores .msi y .exe (para Tauri y otras aplicaciones de escritorio)
choco install -y wixtoolset innosetup

$wixPath = "C:\Program Files (x86)\WiX Toolset v3.14\bin"
$innoPath = "C:\Program Files (x86)\Inno Setup 6"
$machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($machinePath -notlike "*WiX Toolset*") {
    [System.Environment]::SetEnvironmentVariable('Path', "$wixPath;$innoPath;$machinePath", 'Machine')
}
$env:PATH = "$wixPath;$innoPath;$env:PATH"

Write-Host "=== [dev-forge : Windows] 70-packagers: Empaquetadores nativos Windows listos ===" -ForegroundColor Green

