[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 50-node: Instalando Node.js LTS ===" -ForegroundColor Cyan

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    choco install -y nodejs-lts
    $env:PATH = "$env:ProgramFiles\nodejs;$env:PATH"
}

Write-Host "=== [dev-forge : Windows] 50-node: Node $(node -v) y npm $(npm -v) configurados ===" -ForegroundColor Green
