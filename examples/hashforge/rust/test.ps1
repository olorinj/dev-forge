[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

param([string]$Target = "windows")
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$forgeRoot = (Resolve-Path "$scriptDir\..\..\..").Path
$devForgePs1 = "$forgeRoot\bin\dev-forge.ps1"

Write-Host "[HashForge-Rust Test] Compilando para target '$Target'..." -ForegroundColor Cyan
& powershell.exe -ExecutionPolicy Bypass -NoProfile -File $devForgePs1 build -p "$scriptDir" -t "$Target" -k

$distDir = "$scriptDir\dist"
$expectedSha = "3424cecd9bc9384046f4b97b5012cc51037a0a58cbf547642dc71dc6a0ac0825"
$expectedMd5 = "253c885072f588436970bcbc0fe47b9e"

if ($Target -in @("windows", "all")) {
    $winBin = "$distDir\hashforge.exe"
    if (-not (Test-Path $winBin)) { throw "No se encontro $winBin" }
    $sz = (Get-Item $winBin).Length
    Write-Host "[HashForge-Rust Test : PASS] Binario Windows verificado ($sz bytes)" -ForegroundColor Green

    $winSetup = "$distDir\hashforge-setup.exe"
    if (-not (Test-Path $winSetup)) { throw "No se encontro $winSetup" }
    $szSetup = (Get-Item $winSetup).Length
    Write-Host "[HashForge-Rust Test : PASS] Instalador InnoSetup verificado ($szSetup bytes)" -ForegroundColor Green

    $winMsi = "$distDir\hashforge.msi"
    if (-not (Test-Path $winMsi)) { throw "No se encontro $winMsi" }
    $szMsi = (Get-Item $winMsi).Length
    Write-Host "[HashForge-Rust Test : PASS] Paquete WiX MSI verificado ($szMsi bytes)" -ForegroundColor Green
}
