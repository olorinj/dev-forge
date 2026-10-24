﻿[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# =============================================================================
# dev-forge : Universal One-Line Installer for Windows (PowerShell 5.1 / 7+)
# =============================================================================
$ErrorActionPreference = "Stop"

function Log-Info ($msg) { Write-Host "[dev-forge] $msg" -ForegroundColor Cyan }
function Log-Ok ($msg)   { Write-Host "[dev-forge : OK] $msg" -ForegroundColor Green }
function Log-Warn ($msg) { Write-Host "[dev-forge : AVISO] $msg" -ForegroundColor Yellow }
function Log-Err ($msg)  { Write-Host "[dev-forge : ERROR] $msg" -ForegroundColor Red }

Write-Host @"
     _                  __                     
  __| | _____   __     / _| ___  _ __ __ _  ___ 
 / _` |/ _ \ \ / /____| |_ / _ \| '__/ _` |/ _ \
| (_| |  __/\ V /_____|  _| (_) | | | (_| |  __/
 \__,_|\___| \_/      |_|  \___/|_|  \__, |\___|
                                     |___/      
"@ -ForegroundColor Cyan

Write-Host "Forja Universal de Compilación Multiplataforma (Windows MSVC / Linux / macOS)"
Write-Host "=========================================================================`n"

# 1. Comprobación de arquitectura (solo x64 soportado en Windows host para virtualización completa)
if ($env:PROCESSOR_ARCHITECTURE -ne "AMD64" -and $env:PROCESSOR_ARCHITEW6432 -ne "AMD64") {
    Log-Err "dev-forge requiere una versión de Windows de 64 bits (x64)."
    exit 1
}

# 2. Configuración de directorio de destino estándar de usuario
$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\dev-forge\bin"
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
$TargetExe = Join-Path $InstallDir "dev-forge.exe"
$TargetCmd = Join-Path $InstallDir "dev-forge.cmd"

# 3. Comprobar si se ejecuta desde repositorio Git local o descarga remota
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path -ErrorAction SilentlyContinue

if ($ScriptDir -and (Test-Path (Join-Path $ScriptDir "Cargo.toml")) -and (Test-Path (Join-Path $ScriptDir "crates\forge-cli"))) {
    Log-Info "Detectado repositorio local en '$ScriptDir'. Instalando desde fuentes locales..."
    if (Get-Command cargo -ErrorAction SilentlyContinue) {
        Push-Location $ScriptDir
        cargo build --release --bin dev-forge
        Pop-Location
        $LocalBin = Join-Path $ScriptDir "target\release\dev-forge.exe"
        if (Test-Path $LocalBin) {
            Copy-Item -Path $LocalBin -Destination $TargetExe -Force
        }
    } else {
        Log-Warn "Cargo no encontrado. Configurando enlace al lanzador inteligente de la forja..."
        Copy-Item -Path (Join-Path $ScriptDir "bin\dev-forge.cmd") -Destination $TargetCmd -Force
    }
} else {
    $Repo = if ($env:FORGE_REPO) { $env:FORGE_REPO } else { "olorinj/dev-forge" }
    Log-Info "Descargando binario nativo precompilado desde $Repo..."
    $TempZip = Join-Path $env:TEMP "dev-forge-windows.zip"
    $TempExtract = Join-Path $env:TEMP "dev-forge-extract"

    $DownloadUrl = "https://github.com/$Repo/releases/latest/download/dev-forge-x86_64-pc-windows-msvc.zip"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempZip -UseBasicParsing
        if (Test-Path $TempExtract) { Remove-Item -Recurse -Force $TempExtract }
        Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force
        $ExtractedExe = Join-Path $TempExtract "dev-forge.exe"
        if (Test-Path $ExtractedExe) {
            Copy-Item -Path $ExtractedExe -Destination $TargetExe -Force
        }
        Remove-Item -Force $TempZip -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $TempExtract -ErrorAction SilentlyContinue
    } catch {
        Log-Warn "No se pudo descargar release precompilado directo (¿aún no publicado?)."
        if (Get-Command cargo -ErrorAction SilentlyContinue) {
            Log-Info "Instalando mediante cargo..."
            cargo install --git "https://github.com/$Repo.git" --bin dev-forge --root (Join-Path $env:LOCALAPPDATA "Programs\dev-forge")
        } else {
            Log-Err "No hay binarios precompilados disponibles ni 'cargo' instalado en Windows."
            Log-Info "Instala Rust desde: https://rustup.rs/ o clona el repositorio localmente."
            exit 1
        }
    }
}

# 4. Generar wrapper dev-forge.cmd para compatibilidad con CMD y PowerShell
$CmdContent = "@echo off`r`n`"%~dp0dev-forge.exe`" %*`r`n"
Set-Content -Path $TargetCmd -Value $CmdContent -Encoding ASCII

Log-Ok "Binario dev-forge instalado en: $TargetExe"

# 5. Configuración permanente de PATH en el entorno del usuario
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$PathEntries = $UserPath -split ';' | Where-Object { $_ -ne "" }

if ($PathEntries -notcontains $InstallDir) {
    Log-Info "Añadiendo $InstallDir al PATH permanente del usuario..."
    $NewUserPath = ($UserPath.TrimEnd(';') + ";$InstallDir").Trim(';')
    [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
    $env:Path += ";$InstallDir"
    Log-Ok "PATH de usuario actualizado en el Registro de Windows."
}

# 6. Comprobación de prerrequisitos de virtualización en el host (VirtualBox y Vagrant)
$VBoxOk = [bool](Get-Command VBoxManage -ErrorAction SilentlyContinue) -or (Test-Path "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe")
$VagrantOk = [bool](Get-Command vagrant -ErrorAction SilentlyContinue)

if (-not $VBoxOk -or -not $VagrantOk) {
    Log-Warn "Prerrequisitos de virtualización incompletos en el host:"
    if (-not $VBoxOk) { Log-Warn "  - Falta Oracle VirtualBox (>= 7.0)" }
    if (-not $VagrantOk) { Log-Warn "  - Falta HashiCorp Vagrant (>= 2.3)" }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Log-Info "Puedes instalarlos automáticamente ejecutando en PowerShell como Administrador:"
        Write-Host "  winget install Oracle.VirtualBox HashiCorp.Vagrant" -ForegroundColor Yellow
    }
}

# 7. Ejecutar auto-tuning del host y diagnóstico
Write-Host ""
Log-Info "Ejecutando dimensionamiento de hardware y configuración del host..."
if (Test-Path $TargetExe) {
    & $TargetExe tune
    Write-Host ""
    Log-Info "Ejecutando diagnóstico pre-vuelo (dev-forge doctor)..."
    & $TargetExe doctor
}

Write-Host ""
Write-Host "=========================================================================" -ForegroundColor Green
Write-Host "✔ ¡Instalación de dev-forge en Windows completada con éxito!" -ForegroundColor Green
Write-Host "Puedes invocar la forja desde cualquier directorio o terminal con: dev-forge build" -ForegroundColor Cyan
Write-Host "=========================================================================`n" -ForegroundColor Green

