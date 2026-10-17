[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

param([string]$Target = "windows")
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$forgeRoot = (Resolve-Path "$scriptDir\..\..\..").Path
$devForgePs1 = "$forgeRoot\bin\dev-forge.ps1"

Write-Host "[HashForge-Go Test] Compilando para target '$Target'..." -ForegroundColor Cyan
& powershell.exe -ExecutionPolicy Bypass -NoProfile -File $devForgePs1 build -p "$scriptDir" -t "$Target" -k

$distDir = "$scriptDir\dist"
if ($Target -in @("windows", "all")) {
    $winBin = "$distDir\hashforge-go.exe"
    if (-not (Test-Path $winBin)) { $winBin = "$distDir\go.exe" }
    if (-not (Test-Path $winBin)) { throw "No se encontro el binario Windows en $distDir" }
    $sz = (Get-Item $winBin).Length
    Write-Host "[HashForge-Go Test : PASS] Binario Windows verificado ($sz bytes)" -ForegroundColor Green
}
