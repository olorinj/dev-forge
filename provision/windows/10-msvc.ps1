[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 10-msvc: Verificando Visual Studio 2022 C++ Build Tools ===" -ForegroundColor Cyan

# La imagen de box 'visual-studio-2022-community-windows-11' suele traer VS preinstalado.
# Verificamos si vswhere o cl.exe existen; si no, aseguramos la instalación del workload C++.
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
    Write-Host "Instalando Workload C++ Native Desktop en Visual Studio 2022 Community..." -ForegroundColor Yellow
    $setupExe = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
    if (Test-Path $setupExe) {
        $vsPath = "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community"
        $process = Start-Process -FilePath $setupExe -ArgumentList "modify --installPath `"$vsPath`" --add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended --passive --norestart" -Wait -PassThru
        if ($process.ExitCode -in 0, 3010) {
            Write-Host "Workload C++ Native Desktop instalado con éxito." -ForegroundColor Green
        } else {
            Write-Host "El instalador de Visual Studio devolvió el código: $($process.ExitCode)" -ForegroundColor Yellow
        }
    } else {
        choco install -y visualstudio2022-workload-nativedesktop
    }
}

Write-Host "=== [dev-forge : Windows] 10-msvc: Entorno C++ MSVC verificado ===" -ForegroundColor Green

