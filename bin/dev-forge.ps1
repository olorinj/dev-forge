[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# =============================================================================
# dev-forge : Smart Bootstrap Wrapper (Delegates to Native Rust Orchestrator)
# =============================================================================

$ForgeDir = (Get-Item $PSScriptRoot).Parent.FullName
$BinPath = Join-Path $ForgeDir "target\release\dev-forge.exe"

# 1. Si existe el binario release compilado, ejecutarlo inmediatamente
if (Test-Path $BinPath) {
    & $BinPath @args
    exit $LASTEXITCODE
}

# 2. Si dev-forge esta instalado globalmente en PATH, delegar en el
if (Get-Command dev-forge -ErrorAction SilentlyContinue) {
    & dev-forge @args
    exit $LASTEXITCODE
}

# 3. Si cargo esta disponible en el host, compilar automaticamente la primera vez
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    Write-Host "[dev-forge] Compilando el binario nativo en Rust por primera vez..." -ForegroundColor Cyan
    Push-Location $ForgeDir
    cargo build --release --bin dev-forge
    Pop-Location
    if (Test-Path $BinPath) {
        & $BinPath @args
        exit $LASTEXITCODE
    }
}

Write-Host "[dev-forge : ERROR] No se encontro el binario compilado 'dev-forge.exe'." -ForegroundColor Red
Write-Host "Instala Rust (cargo) o ejecuta: cargo build --release --bin dev-forge" -ForegroundColor Yellow
exit 1
