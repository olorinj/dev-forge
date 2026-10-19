# =============================================================================
# dev-forge : Windows MSVC C++ Build Tools Provisioner
# =============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 10-msvc: Verificando Visual Studio 2022 C++ Build Tools ===" -ForegroundColor Cyan

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vcInstalled = $false

if (Test-Path $vswhere) {
    $installPath = & $vswhere -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($installPath) {
        $vcInstalled = $true
        Write-Host "C++ Build Tools (MSVC) detectados en: $installPath" -ForegroundColor Green
    }
}

if (-not $vcInstalled) {
    Write-Host "Instalando Visual Studio 2022 C++ Build Tools (MSVC + Windows SDK + link.exe)..." -ForegroundColor Yellow
    choco install -y visualstudio2022buildtools --package-parameters "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive --norestart"
}

Write-Host "=== [dev-forge : Windows] 10-msvc: Entorno C++ MSVC verificado ===" -ForegroundColor Green
