[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 30-python: Instalando Python y herramientas ===" -ForegroundColor Cyan

$isRealPython = $false
try {
    $ver = & python --version 2>&1
    if ($ver -like "*Python 3*") { $isRealPython = $true }
} catch {}

if (-not $isRealPython) {
    choco install -y python312
    Get-ChildItem -Path "$env:LOCALAPPDATA\Microsoft\WindowsApps" -Filter "python*.exe" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $pyPath = "$env:ProgramFiles\Python312;$env:ProgramFiles\Python312\Scripts"
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($machinePath -notlike "*Python312*") {
        [System.Environment]::SetEnvironmentVariable('Path', "$pyPath;$machinePath", 'Machine')
    }
    $env:PATH = "$pyPath;$env:PATH"
}

python -m pip install --upgrade pip pyinstaller wheel setuptools

Write-Host "=== [dev-forge : Windows] 30-python: Python $(python --version) configurado ===" -ForegroundColor Green

