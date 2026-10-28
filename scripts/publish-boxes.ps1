ï»¿[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# =============================================================================
# dev-forge : Script de Publicación Oficial de Boxes en Vagrant Cloud (PowerShell)
# =============================================================================
# Compatible con Windows PowerShell 5.1 y PowerShell Core 7+
# Automatiza la subida, descripción, versionado y liberación de las boxes
# oficiales de DevForge (linux, windows, runner) hacia app.vagrantup.com.
# =============================================================================
param(
    [string]$Version = "1.0.0",
    [string]$Target = "all",
    [string]$Org = $env:VAGRANT_CLOUD_USER,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$Draft,
    [string]$Description,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "  dev-forge - Asistente de Publicación en Vagrant Cloud (PowerShell)" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Publica las custom boxes pre-horneadas (.box) en app.vagrantup.com con metadatos"
    Write-Host "optimizados y verificación de integridad criptográfica SHA-256."
    Write-Host ""
    Write-Host "USO:" -ForegroundColor Cyan
    Write-Host "  .\scripts\publish-boxes.ps1 [-Version <version>] [-Target <linux|windows|runner|all>] [OPCIONES]"
    Write-Host ""
    Write-Host "OPCIONES:" -ForegroundColor Cyan
    Write-Host "  -Version <string>       Versión semver a publicar (por defecto: 1.0.0)."
    Write-Host "  -Target <string>        Box a publicar: 'linux', 'windows', 'runner' o 'all' (por defecto: all)."
    Write-Host "  -Org <string>           Organización / Usuario en Vagrant Cloud (por defecto: olorinj)."
    Write-Host "  -DryRun                 Modo simulación: muestra las comprobaciones y comandos sin subir nada."
    Write-Host "  -Yes                    Modo desatendido: omite la confirmación interactiva."
    Write-Host "  -Draft                  Publica la versión en modo borrador (sin el flag --release)."
    Write-Host "  -Description <string>   Sobrescribe la descripción general de la versión."
    Write-Host "  -Help                   Muestra esta ayuda y sale."
    Write-Host ""
    Write-Host "EJEMPLOS:" -ForegroundColor Cyan
    Write-Host "  .\scripts\publish-boxes.ps1 -Version 1.0.0 -Target all"
    Write-Host "  .\scripts\publish-boxes.ps1 -Version 1.0.0 -Target windows -DryRun"
    Write-Host "  .\scripts\publish-boxes.ps1 -Version 1.1.0 -Target linux -Yes"
    exit 0
}

if ($Help) { Show-Help }

if ([string]::IsNullOrWhiteSpace($Org)) {
    $Org = "olorinj"
}

function Log-Info ($msg) { Write-Host "[publish-boxes] $msg" -ForegroundColor Cyan }
function Log-Ok ($msg)   { Write-Host "[publish-boxes : OK] $msg" -ForegroundColor Green }
function Log-Warn ($msg) { Write-Host "[publish-boxes : AVISO] $msg" -ForegroundColor Yellow }
function Log-Err ($msg)  { Write-Host "[publish-boxes : ERROR] $msg" -ForegroundColor Red }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$OutDir = Join-Path $RepoDir "distoxes"

# 1. Comprobación de Vagrant y Autenticación
if (-not (Get-Command "vagrant" -ErrorAction SilentlyContinue)) {
    Log-Err "Vagrant no está instalado o no se encuentra en el PATH del sistema."
    exit 1
}

Log-Info "Comprobando credenciales en Vagrant Cloud..."
if (-not $DryRun) {
    try {
        $currentUser = & vagrant cloud auth whoami 2>&1
        if ($currentUser -match "You are not logged in") {
            Log-Err "No has iniciado sesión en Vagrant Cloud."
            Write-Host ""
            Write-Host "Por favor, autentícate ejecutando:"
            Write-Host "    vagrant cloud auth login"
            Write-Host "o define la variable de entorno VAGRANT_CLOUD_TOKEN antes de continuar."
            Write-Host ""
            exit 1
        }
        Log-Ok "Autenticación activa: $currentUser"
    } catch {
        Log-Err "Error al verificar la sesión en Vagrant Cloud: $_"
        exit 1
    }
} else {
    Log-Warn "[DRY-RUN] Omitiendo validación estricta de sesión de red."
}

# 2. Resolución de Boxes
$BoxFiles = @{
    "linux"   = "dev-forge-linux-v$Version.box"
    "windows" = "dev-forge-windows-v$Version.box"
    "runner"  = "dev-forge-runner-v$Version.box"
}

$BoxTags = @{
    "linux"   = "$Org/dev-forge-linux"
    "windows" = "$Org/dev-forge-windows"
    "runner"  = "$Org/dev-forge-runner"
}

$BoxDescriptions = @{
    "linux"   = "DevForge Linux Native Build Box (Debian 12 + Rust/Go/Node/Java/Docker/VDI). Pre-baked toolchains, zero auto-updates, single active kernel."
    "windows" = "DevForge Windows Native Build Box (Windows Server 2022 Standard Core + MSVC/WiX/Inno/VDI). Pre-baked Visual Studio 2022 Build Tools, WiX 3.14, InnoSetup, zero auto-updates."
    "runner"  = "DevForge CI/CD Runner Box (Debian 12 + Docker Engine + GitLab Runner CLI). Entorno local aislado para pipelines declarativos offline."
}

$MachinesToPublish = @()
if ($Target -eq "all") {
    $MachinesToPublish = @("linux", "windows", "runner")
} else {
    $MachinesToPublish = @($Target.ToLower())
}

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "          PLAN DE PUBLICACIÓN EN VAGRANT CLOUD (app.vagrantup.com)" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ("Versión      : v{0}" -f $Version)
Write-Host ("Organización : {0}" -f $Org)
Write-Host ("Estado       : {0}" -f ($Draft ? "Draft (Borrador)" : "Release (Pública activa)"))
Write-Host ("Simulación   : {0}" -f ($DryRun ? "SÍ (--dry-run activo)" : "NO (Subida real)"))
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Cyan

$AllFilesValid = $true

foreach ($m in $MachinesToPublish) {
    $bfile = Join-Path $OutDir $BoxFiles[$m]
    $btag = $BoxTags[$m]
    if (Test-Path $bfile) {
        $item = Get-Item $bfile
        $bsize = [math]::Round($item.Length / 1GB, 2).ToString() + " GB"
        $shaFile = "$bfile.sha256"
        $bsha = "N/A"
        if (Test-Path $shaFile) {
            $bsha = (Get-Content $shaFile | Select-Object -First 1).Split(' ')[0]
        }
        Write-Host ("  ✔ [{0}] {1} ({2})" -f $m.ToUpper(), $btag, $bsize) -ForegroundColor Green
        Write-Host ("      Archivo : {0}" -f $bfile) -ForegroundColor Gray
        Write-Host ("      SHA-256 : {0}" -f $bsha) -ForegroundColor Gray
    } else {
        Write-Host ("  ✘ [{0}] {1}" -f $m.ToUpper(), $btag) -ForegroundColor Red
        Write-Host ("      Error: No se encontró el archivo '{0}'" -f $bfile) -ForegroundColor Red
        $AllFilesValid = $false
    }
}
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

if (-not $AllFilesValid) {
    Log-Err "Faltan archivos .box requeridos en '$OutDir'. Compílalos o empaquétalos antes de publicar."
    exit 1
}

# 3. Confirmación
if (-not $Yes -and -not $DryRun) {
    Write-Host "AVISO: La subida de boxes transferirá varios gigabytes hacia Vagrant Cloud." -ForegroundColor Yellow
    $confirm = Read-Host "¿Deseas proceder con la publicación oficial de la versión v$Version? (s/N)"
    if ($confirm -notmatch "^[sSyY]$") {
        Log-Warn "Operación cancelada por el usuario."
        exit 0
    }
}

# 4. Publicación
foreach ($m in $MachinesToPublish) {
    $bfile = Join-Path $OutDir $BoxFiles[$m]
    $btag = $BoxTags[$m]
    $bdesc = if ([string]::IsNullOrWhiteSpace($Description)) { $BoxDescriptions[$m] } else { $Description }
    $vdesc = "DevForge $([char]::ToUpper($m[0]) + $m.Substring(1)) Box Release v$Version: Pre-baked standalone toolchains, zero auto-updates, hardened single active kernel."

    $cmdArgs = @(
        "cloud", "publish",
        $btag,
        $Version,
        "virtualbox",
        $bfile,
        "--description", $bdesc,
        "--version-description", $vdesc
    )

    if (-not $Draft) {
        $cmdArgs += "--release"
    }

    Write-Host ""
    Log-Info ("Procesando publicación para [{0}] -> {1} (v{2})..." -f $m.ToUpper(), $btag, $Version)
    Write-Host ("Comando: vagrant {0}" -f ($cmdArgs -join " ")) -ForegroundColor Gray

    if ($DryRun) {
        Log-Warn "[DRY-RUN] Simulación de subida para '$btag' completada (sin tráfico de red)."
    } else {
        Log-Info "Subiendo archivo .box hacia Vagrant Cloud (esto puede tomar varios minutos dependiendo del ancho de banda)..."
        & vagrant @cmdArgs
        if ($LASTEXITCODE -ne 0) {
            Log-Err ("Fallo al publicar la box '{0}'. Exit code: {1}" -f $btag, $LASTEXITCODE)
            exit $LASTEXITCODE
        }
        Log-Ok "¡Box '$btag' v$Version publicada exitosamente!"
    }
}

Write-Host ""
Log-Ok "Todas las operaciones de publicación solicitadas han finalizado con éxito."
if (-not $DryRun) {
    Write-Host ("Puedes consultar tus boxes en: https://app.vagrantup.com/{0}" -f $Org) -ForegroundColor Cyan
}
