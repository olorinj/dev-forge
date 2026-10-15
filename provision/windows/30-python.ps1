[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 30-python: Instalando Python y herramientas ===" -ForegroundColor Cyan

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    choco install -y python312
    $env:PATH = "$env:ProgramFiles\Python312;$env:ProgramFiles\Python312\Scripts;$env:PATH"
}

python -m pip install --upgrade pip pyinstaller wheel setuptools

Write-Host "=== [dev-forge : Windows] 30-python: Python $(python --version) configurado ===" -ForegroundColor Green

