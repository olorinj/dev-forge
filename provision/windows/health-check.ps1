# =============================================================================
# dev-forge : Health-Check & Validation Suite for Windows Server 2022 Core
# =============================================================================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$pass = 0
$fail = 0

function Assert-Tool($name, $cmdBlock) {
    try {
        $out = & $cmdBlock 2>&1
        if ($LASTEXITCODE -eq 0 -or $out) {
            Write-Host "  ✔ PASS : $name -> $($out | Select-Object -First 1)" -ForegroundColor Green
            $script:pass++
        } else {
            Write-Host "  ✘ FAIL : $name" -ForegroundColor Red
            $script:fail++
        }
    } catch {
        Write-Host "  ✘ FAIL : $name ($($_.Exception.Message))" -ForegroundColor Red
        $script:fail++
    }
}

Write-Host "=== [dev-forge] Windows Build Node Health-Check ===" -ForegroundColor Cyan

Write-Host "`n1. Verificando Toolchains de Compilacion..." -ForegroundColor Yellow
Assert-Tool "Rust Compiler (rustc)" { rustc --version }
Assert-Tool "Cargo Package Manager" { cargo --version }
Assert-Tool "Python Runtime" { python --version }
Assert-Tool "Go Compiler" { go version }
Assert-Tool "Node.js Runtime" { node --version }
Assert-Tool "Java SDK (javac)" { javac -version }
Assert-Tool "CMake Build System" { cmake --version }
Assert-Tool "Ninja Build Tool" { ninja --version }

Write-Host "`n2. Verificando Optimizaciones del Sistema..." -ForegroundColor Yellow
$exclusions = Get-MpPreference | Select-Object -ExpandProperty ExclusionPath -ErrorAction SilentlyContinue
if ($exclusions) {
    Write-Host "  ✔ PASS : Defender Exclusiones activas ($($exclusions.Count) rutas)" -ForegroundColor Green
    $pass++
} else {
    Write-Host "  ⚠ WARN : Sin exclusiones explicitas de Defender" -ForegroundColor Yellow
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " RESUMEN: Superados: $pass | Fallidos: $fail" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Cyan

if ($fail -gt 0) {
    exit 1
}

