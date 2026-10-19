[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

param(
    [string]$Language = "all",
    [string]$Target = "all"
)

$ErrorActionPreference = "Continue"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "   HashForge: Suite Universal de Pruebas Multi-Lenguaje (PS)" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Lenguaje(s): $Language"
Write-Host "Destino(s):  $Target"
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$languages = if ($Language -eq "all") {
    @("rust", "python", "c", "cpp", "go", "java", "node")
} else {
    @($Language)
}

$passed = 0
$failed = 0

foreach ($lang in $languages) {
    $subDir = Join-Path $scriptDir $lang
    if (-not (Test-Path $subDir)) {
        Write-Host "[ERROR] Lenguaje '$lang' no encontrado en $subDir" -ForegroundColor Red
        $failed++
        continue
    }

    Write-Host "-----------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "▶ Ejecutando pruebas para: $($lang.ToUpper()) (Target: $Target)" -ForegroundColor White
    Write-Host "-----------------------------------------------------------------" -ForegroundColor Cyan

    $testPs1 = Join-Path $subDir "test.ps1"
    if (Test-Path $testPs1) {
        & powershell.exe -ExecutionPolicy Bypass -NoProfile -File $testPs1 -Target $Target
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✔ $($lang.ToUpper()): PRUEBAS SUPERADAS`n" -ForegroundColor Green
            $passed++
        } else {
            Write-Host "✘ $($lang.ToUpper()): PRUEBAS FALLIDAS`n" -ForegroundColor Red
            $failed++
        }
    } else {
        Write-Host "[AVISO] No se encontro test.ps1 en $subDir`n" -ForegroundColor Red
        $failed++
    }
}

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "RESUMEN DE PRUEBAS MULTI-LENGUAJE:" -ForegroundColor White
Write-Host "  Superados: $passed" -ForegroundColor Green
Write-Host "  Fallidos:  $failed" -ForegroundColor Red
Write-Host "=================================================================" -ForegroundColor Cyan

if ($failed -gt 0) {
    exit 1
}
