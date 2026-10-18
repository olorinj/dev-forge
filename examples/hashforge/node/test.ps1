[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

param([string]$Target = "windows")
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$forgeRoot = (Resolve-Path "$scriptDir\..\..\..").Path
$devForgePs1 = "$forgeRoot\bin\dev-forge.ps1"

Write-Host "[HashForge-Node Test] Compilando y empaquetando para target '$Target'..." -ForegroundColor Cyan
& powershell.exe -ExecutionPolicy Bypass -NoProfile -File $devForgePs1 build -p "$scriptDir" -t "$Target" -k

$distDir = "$scriptDir\dist"
$nodeBin = Join-Path $distDir "hashforge-node.js"
$webHtml = Join-Path $distDir "index.html"

if (-not (Test-Path $nodeBin)) { throw "No se encontro $nodeBin" }
if (-not (Test-Path $webHtml)) { throw "No se encontro $webHtml" }

Write-Host "[HashForge-Node Test] Verificando ejecucion de Node.js en Windows..." -ForegroundColor Cyan
$expectedSha = "3424cecd9bc9384046f4b97b5012cc51037a0a58cbf547642dc71dc6a0ac0825"
$expectedMd5 = "253c885072f588436970bcbc0fe47b9e"

$out = & node $nodeBin -s "dev-forge test" -j
Write-Host "  $out"
if ($out -match $expectedSha -and $out -match $expectedMd5) {
    Write-Host "[HashForge-Node Test : PASS] HashForge Node.js / Web verificado con exito" -ForegroundColor Green
} else {
    throw "Hash invalido en salida de Node.js"
}
