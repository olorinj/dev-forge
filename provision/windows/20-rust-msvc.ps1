[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 20-rust-msvc: Instalando Rust Toolchain (MSVC) ===" -ForegroundColor Cyan

# Definir C:\target para CARGO_TARGET_DIR a nivel de sistema
[System.Environment]::SetEnvironmentVariable('CARGO_TARGET_DIR', 'C:\target', 'Machine')
$env:CARGO_TARGET_DIR = "C:\target"
if (-not (Test-Path "C:\target")) { New-Item -ItemType Directory -Force -Path "C:\target" | Out-Null }

if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
    Write-Host "Instalando Rustup (x86_64-pc-windows-msvc)..." -ForegroundColor Gray
    $rustupInit = "$env:TEMP\rustup-init.exe"
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
        & curl.exe -sSfL "https://win.rustup.rs/x86_64" -o $rustupInit
    } else {
        (New-Object System.Net.WebClient).DownloadFile("https://win.rustup.rs/x86_64", $rustupInit)
    }
    & $rustupInit -y --default-host x86_64-pc-windows-msvc --default-toolchain stable 2>&1 | Write-Host
    Remove-Item -Force $rustupInit -ErrorAction SilentlyContinue
} else {
    Write-Host "Actualizando toolchain de Rust en Windows..." -ForegroundColor Gray
    rustup update
}

# Añadir permanentemente Cargo bin a la variable PATH de la máquina
$cargoBin = "$env:USERPROFILE\.cargo\bin"
$machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($machinePath -notlike "*$cargoBin*") {
    [System.Environment]::SetEnvironmentVariable('Path', "$cargoBin;$machinePath", 'Machine')
}
if ($env:PATH -notlike "*$cargoBin*") {
    $env:PATH = "$cargoBin;$env:PATH"
}

# Instalar cargo-binstall y tauri-cli precompilado
if (-not (Get-Command cargo-binstall.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Instalando cargo-binstall para Windows..." -ForegroundColor Gray
    try {
        & curl.exe -sSfL "https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.ps1" -o "$env:TEMP\install-binstall.ps1"
        & powershell.exe -ExecutionPolicy Bypass -File "$env:TEMP\install-binstall.ps1"
        Remove-Item -Force "$env:TEMP\install-binstall.ps1" -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "No se pudo instalar cargo-binstall: $_"
    }
}

if (-not (Get-Command cargo-tauri.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Instalando binario oficial de tauri-cli..." -ForegroundColor Gray
    if (Get-Command cargo-binstall.exe -ErrorAction SilentlyContinue) {
        & cargo-binstall.exe --no-confirm tauri-cli 2>&1 | Write-Host
    }
    if (-not (Get-Command cargo-tauri.exe -ErrorAction SilentlyContinue)) {
        & cargo install tauri-cli --locked 2>&1 | Write-Host
    }
}

Write-Host "=== [dev-forge : Windows] 20-rust-msvc: Rust $(rustc --version) listo ===" -ForegroundColor Green

