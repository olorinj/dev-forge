[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 70-packagers: Instalando WiX Toolset e InnoSetup ===" -ForegroundColor Cyan

# Herramientas para generar instaladores .msi y .exe (para Tauri y otras aplicaciones de escritorio)
choco install -y wixtoolset innosetup

Write-Host "=== [dev-forge : Windows] 70-packagers: Empaquetadores nativos Windows listos ===" -ForegroundColor Green
