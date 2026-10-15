[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 20-rust-msvc: Instalando Rust Toolchain (MSVC) ===" -ForegroundColor Cyan

if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
    Write-Host "Instalando Rustup (x86_64-pc-windows-msvc)..." -ForegroundColor Gray
    $rustupInit = "$env:TEMP\rustup-init.exe"
    Invoke-WebRequest -Uri "https://win.rustup.rs/x86_64" -OutFile $rustupInit
    & $rustupInit -y --default-host x86_64-pc-windows-msvc --default-toolchain stable 2>&1 | Write-Host
    Remove-Item -Force $rustupInit -ErrorAction SilentlyContinue
} else {
    Write-Host "Actualizando toolchain de Rust en Windows..." -ForegroundColor Gray
    rustup update
}

# Refrescar variable PATH en sesión actual
$cargoBin = "$env:USERPROFILE\.cargo\bin"
if ($env:PATH -notlike "*$cargoBin*") {
    $env:PATH = "$cargoBin;$env:PATH"
}

Write-Host "=== [dev-forge : Windows] 20-rust-msvc: Rust $(rustc --version) listo ===" -ForegroundColor Green

