[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 40-go: Instalando Go Toolchain ===" -ForegroundColor Cyan

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    choco install -y golang
    $env:PATH = "C:\Program Files\Go\bin;$env:PATH"
}

Write-Host "=== [dev-forge : Windows] 40-go: Go $(go version) configurado ===" -ForegroundColor Green
