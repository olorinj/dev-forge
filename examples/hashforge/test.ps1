[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

param(
    [string]$Target = "windows"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$forgeRoot = (Resolve-Path "$scriptDir\..\..").Path
$devForgePs1 = "$forgeRoot\bin\dev-forge.ps1"
$devForgeCmd = "$forgeRoot\bin\dev-forge.cmd"

function Write-Info($msg) { Write-Host "[HashForge Test] $msg" -ForegroundColor Cyan }
function Write-Pass($msg) { Write-Host "[HashForge Test : PASS] $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "[HashForge Test : FAIL] $msg" -ForegroundColor Red; exit 1 }

$expectedSha256 = "7fa5a0fe7bcdd886b62fc0bcddbf1a70c86801bb61dd66c430485981ee8aa6bf"
$expectedMd5    = "00dfa0bf846830cfcae67dca1f543166"

Write-Info "Iniciando suite de pruebas para HashForge (PowerShell)"
Write-Info "Directorio del proyecto: $scriptDir"
Write-Info "Destino de compilacion:   $Target"

# 1. Ejecutar orquestador dev-forge
Write-Info "Ejecutando orquestador dev-forge..."
if (Test-Path $devForgePs1) {
    & powershell.exe -ExecutionPolicy Bypass -NoProfile -File $devForgePs1 build -p "$scriptDir" -t "$Target" -k
} elseif (Test-Path $devForgeCmd) {
    & $devForgeCmd build -p "$scriptDir" -t "$Target" -k
} else {
    Write-Fail "No se encontro bin/dev-forge.ps1 ni bin/dev-forge.cmd en $forgeRoot"
}

# 2. Verificar artefactos generados
$distDir = "$scriptDir\dist"
if (-not (Test-Path $distDir)) {
    Write-Fail "No se genero el directorio dist tras la compilacion."
}

if ($Target -in @("windows", "all")) {
    $winBin = "$distDir\hashforge.exe"
    if (-not (Test-Path $winBin)) {
        Write-Fail "No se encontro el binario Windows en $winBin"
    }

    $binItem = Get-Item $winBin
    Write-Info "Binario Windows encontrado: $($binItem.FullName) ($($binItem.Length) bytes)"

    if ($PSVersionTable.PSEdition -ne "Core" -or $IsWindows) {
        Write-Info "Ejecutando prueba de verificacion con hashforge.exe..."
        $output = & $winBin -s "dev-forge test" -j
        Write-Host $output

        if ($output -match $expectedSha256 -and $output -match $expectedMd5) {
            Write-Pass "Binario Windows verificado correctamente con hash esperado (SHA-256: $expectedSha256)"
        } else {
            Write-Fail "El binario devolvio un resultado inesperado: $output"
        }
    } else {
        Write-Pass "Binario Windows generado y validado estructuralmente ($($binItem.Length) bytes)."
    }
}

if ($Target -in @("linux", "all")) {
    $linuxBin = "$distDir\hashforge"
    if (-not (Test-Path $linuxBin)) {
        Write-Fail "No se encontro el binario Linux en $linuxBin"
    }
    $binItem = Get-Item $linuxBin
    Write-Pass "Binario Linux presente en dist: $($binItem.Name) ($($binItem.Length) bytes)"
}

Write-Host ""
Write-Pass "Todas las pruebas de HashForge finalizaron con exito para target '$Target'."
