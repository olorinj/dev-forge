[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 10-msvc: Verificando Visual Studio 2022 C++ Build Tools ===" -ForegroundColor Cyan

# La imagen de box 'visual-studio-2022-community-windows-11' suele traer VS preinstalado.
# Verificamos si vswhere o cl.exe existen; si no, aseguramos la instalación del workload C++.
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        Write-Host "Instalando Visual Studio Build Tools 2022 con C++..." -ForegroundColor Yellow
        choco install -y visualstudio2022buildtools visualstudio2022-workload-vctools
    } else {
        Write-Host "Visual Studio Installer detectado en el sistema." -ForegroundColor Green
    }
} else {
    Write-Host "Compilador cl.exe (MSVC) disponible en PATH." -ForegroundColor Green
}

Write-Host "=== [dev-forge : Windows] 10-msvc: Entorno C++ MSVC verificado ===" -ForegroundColor Green

