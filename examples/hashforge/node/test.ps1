[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
 = [System.Text.Encoding]::UTF8

param([string] = "windows")
 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = (Resolve-Path "\..\..\..").Path
 = "in\dev-forge.ps1"

Write-Host "[HashForge-Node Test] Compilando y empaquetando para target ''..." -ForegroundColor Cyan
& powershell.exe -ExecutionPolicy Bypass -NoProfile -File  build -p "" -t "" -k

 = "\dist"
 = Join-Path  "hashforge-node.js"
 = Join-Path  "index.html"

if (-not (Test-Path )) { throw "No se encontro " }
if (-not (Test-Path )) { throw "No se encontro " }

Write-Host "[HashForge-Node Test] Verificando ejecucion de Node.js en Windows..." -ForegroundColor Cyan
 = "3424cecd9bc9384046f4b97b5012cc51037a0a58cbf547642dc71dc6a0ac0825"
 = "253c885072f588436970bcbc0fe47b9e"

 = & node  -s "dev-forge test" -j
Write-Host "  "
if ($out -match $expectedSha -and $out -match $expectedMd5) {
    Write-Host "[HashForge-Node Test : PASS] HashForge Node.js / Web verificado con exito" -ForegroundColor Green
} else {
    throw "Hash invalido en salida de Node.js"
}
