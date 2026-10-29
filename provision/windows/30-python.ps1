[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 30-python: Instalando Python 3.14, uv, Poetry y suite multipython ===" -ForegroundColor Cyan

$isRealPython = $false
try {
    $ver = & python --version 2>&1
    if ($ver -like "*Python 3.14*") { $isRealPython = $true }
} catch {}

if (-not $isRealPython) {
    $installer = "$env:TEMP\python-3.14.0-amd64.exe"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "  -> Descargando Python 3.14 oficial..." -ForegroundColor Yellow
    & curl.exe -sSfL "https://www.python.org/ftp/python/3.14.0/python-3.14.0-amd64.exe" -o $installer
    Write-Host "  -> Instalando Python 3.14 desatendido..." -ForegroundColor Yellow
    $proc = Start-Process -FilePath $installer -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1 Include_test=0" -Wait -PassThru
    Remove-Item -Force $installer -ErrorAction SilentlyContinue
    if ($proc.ExitCode -notin @(0, 3010)) {
        Write-Warning "Aviso: código de retorno del instalador de Python: $($proc.ExitCode)"
    }

    Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WindowsApps" -Filter "python*.exe" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $pyPath = "C:\Program Files\Python314;C:\Program Files\Python314\Scripts"
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($machinePath -notlike "*Python314*") {
        [System.Environment]::SetEnvironmentVariable('Path', "$pyPath;$machinePath", 'Machine')
    }
    $env:PATH = "$pyPath;$env:PATH"
}

# Instalación de Astral uv
if (-not (Get-Command uv.exe -ErrorAction SilentlyContinue)) {
    Write-Host "  -> Instalando Astral uv..." -ForegroundColor Yellow
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    $uvDir = "$env:USERPROFILE\.local\bin"
    if (Test-Path "$uvDir\uv.exe") {
        $currPath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
        if ($currPath -notlike "*$uvDir*") {
            [System.Environment]::SetEnvironmentVariable('Path', "$uvDir;$currPath", 'Machine')
        }
        $env:PATH = "$uvDir;$env:PATH"
    }
}

# Pre-instalación de la suite multipython
Write-Host "  -> Pre-aprovisionando versiones multipython (3.10..3.13) con uv..." -ForegroundColor Yellow
& uv python install 3.10 3.11 3.12 3.13 2>&1 | Write-Host

# Herramientas de desarrollo y empaquetado (Poetry, Nuitka, PyInstaller, Build, Tox)
Write-Host "  -> Instalando Poetry, Nuitka, PyInstaller, Wheel, Setuptools, Build y Tox..." -ForegroundColor Yellow
python -m pip install --no-cache-dir --upgrade pip poetry nuitka pyinstaller wheel setuptools build tox

Write-Host "=== [dev-forge : Windows] 30-python: Python $(python --version) y herramientas configuradas con éxito ===" -ForegroundColor Green

