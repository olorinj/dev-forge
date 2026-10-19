# =============================================================================
# dev-forge : Universal Windows Packaging Engine (InnoSetup & WiX MSI)
# =============================================================================
param(
    [string]$DistDir = "C:\workspace\dist",
    [string]$TargetDir = "C:\target"
)

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Test-Path $DistDir)) {
    exit 0
}

$exeFiles = Get-ChildItem -Path $DistDir -Filter "*.exe" | Where-Object {
    $_.Name -notmatch "(?i)(-setup\.exe|_setup\.exe|\.tmp)"
}

if (-not $exeFiles -or $exeFiles.Count -eq 0) {
    exit 0
}

# Resolve Inno Setup Compiler
$iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
if (-not $iscc) {
    $fallbackIscc = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
    if (Test-Path $fallbackIscc) { $iscc = $fallbackIscc }
}

# Resolve WiX Toolset
$candle = (Get-Command candle.exe -ErrorAction SilentlyContinue).Source
if (-not $candle) {
    $fallbackCandle = "C:\Program Files (x86)\WiX Toolset v3.14\bin\candle.exe"
    if (Test-Path $fallbackCandle) { $candle = $fallbackCandle }
}

$light = (Get-Command light.exe -ErrorAction SilentlyContinue).Source
if (-not $light) {
    $fallbackLight = "C:\Program Files (x86)\WiX Toolset v3.14\bin\light.exe"
    if (Test-Path $fallbackLight) { $light = $fallbackLight }
}

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

foreach ($exe in $exeFiles) {
    $baseName = $exe.BaseName
    $exeFullName = $exe.FullName
    Write-Host "[dev-forge : packager] Empaquetando `"$baseName`"..." -ForegroundColor Cyan

    # --- 1. Generar instalador Inno Setup (.exe) ---
    if ($iscc) {
        $issPath = Join-Path $TargetDir "$baseName.iss"
        $issContent = @"
[Setup]
AppName=$baseName
AppVersion=1.0.0
DefaultDirName={autopf}\$baseName
DefaultGroupName=$baseName
OutputDir=$DistDir
OutputBaseFilename=$baseName-setup
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes

[Files]
Source: "$exeFullName"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\$baseName"; Filename: "{app}\$($exe.Name)"
Name: "{autodesktop}\$baseName"; Filename: "{app}\$($exe.Name)"
"@
        Set-Content -Path $issPath -Value $issContent -Encoding UTF8
        Write-Host "  -> Compilando Inno Setup: $baseName-setup.exe..." -ForegroundColor Yellow
        & $iscc /Q "$issPath"
        if (Test-Path (Join-Path $DistDir "$baseName-setup.exe")) {
            Write-Host "  [OK] Inno Setup: $baseName-setup.exe generado exitosamente." -ForegroundColor Green
        } else {
            Write-Warning "  [FALLO] No se pudo generar $baseName-setup.exe"
        }
    } else {
        Write-Warning "  [AVISO] InnoSetup (ISCC.exe) no disponible."
    }

    # --- 2. Generar instalador WiX Toolset (.msi) ---
    if ($candle -and $light) {
        $wxsPath = Join-Path $TargetDir "$baseName.wxs"
        $wixObj = Join-Path $TargetDir "$baseName.wixobj"
        $msiPath = Join-Path $DistDir "$baseName.msi"
        
        $upgradeGuid = [guid]::NewGuid().ToString()

        $wxsContent = @"
<?xml version="1.0" encoding="utf-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="$baseName" Language="1033" Version="1.0.0" Manufacturer="dev-forge" UpgradeCode="$upgradeGuid">
    <Package InstallerVersion="200" Compressed="yes" InstallScope="perMachine" />
    <MediaTemplate EmbedCab="yes" />
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="$baseName">
          <Component Id="MainExecutable" Guid="*" Win64="yes">
            <File Id="MainExeFile" Source="$exeFullName" KeyPath="yes" />
          </Component>
        </Directory>
      </Directory>
    </Directory>
    <Feature Id="MainApplication" Title="$baseName" Level="1">
      <ComponentRef Id="MainExecutable" />
    </Feature>
  </Product>
</Wix>
"@
        Set-Content -Path $wxsPath -Value $wxsContent -Encoding UTF8
        Write-Host "  -> Compilando WiX MSI: $baseName.msi..." -ForegroundColor Yellow
        & $candle -nologo -out "$wixObj" "$wxsPath" 2>&1 | Out-Null
        & $light -nologo -sval -spdb -out "$msiPath" "$wixObj" 2>&1 | Out-Null
        if (Test-Path (Join-Path $DistDir "$baseName.wixpdb")) {
            Remove-Item -Path (Join-Path $DistDir "$baseName.wixpdb") -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $msiPath) {
            Write-Host "  [OK] WiX MSI: $baseName.msi generado exitosamente." -ForegroundColor Green
        } else {
            Write-Warning "  [FALLO] No se pudo generar $baseName.msi"
        }
    } else {
        Write-Warning "  [AVISO] WiX Toolset (candle/light) no disponible."
    }
}
