# =============================================================================
# dev-forge : Universal Windows Packaging Engine (InnoSetup & WiX MSI + Icons)
# =============================================================================
param(
    [string]$DistDir = "C:\workspace\dist",
    [string]$TargetDir = "C:\target",
    [string]$WorkspaceDir = "C:\workspace",
    [string]$AppVersion = "",
    [string]$WixVersion = "",
    [string]$GitBranch = "",
    [switch]$FindIconOnly
)

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

function Find-ProjectIcon([string]$workspace, [string]$target) {
    if (-not (Test-Path $workspace)) { return $null }

    # 1. Search prioritized .ico files
    $priorityIcoPaths = @(
        "assets\icon.ico",
        "assets\app.ico",
        "icons\icon.ico",
        "icons\app.ico",
        "src-tauri\icons\icon.ico",
        "resources\icon.ico",
        "resources\app.ico",
        "windows\icon.ico",
        "icon.ico",
        "app.ico"
    )

    foreach ($rel in $priorityIcoPaths) {
        $candidate = Join-Path $workspace $rel
        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    # 2. General search for any .ico in workspace (excluding build and version control dirs)
    $anyIco = Get-ChildItem -Path $workspace -Filter "*.ico" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch "(\\target\\|\\dist\\|\\\.git\\|\\node_modules\\|\\build\\)" } |
        Select-Object -First 1

    if ($anyIco) {
        return $anyIco.FullName
    }

    # 3. Search prioritized .png files for conversion
    $priorityPngPaths = @(
        "assets\icon.png",
        "assets\app.png",
        "assets\logo.png",
        "icons\icon.png",
        "icons\app.png",
        "src-tauri\icons\icon.png",
        "src-tauri\icons\128x128.png",
        "src-tauri\icons\32x32.png",
        "resources\icon.png",
        "icon.png",
        "app.png",
        "logo.png"
    )

    $foundPng = $null
    foreach ($rel in $priorityPngPaths) {
        $candidate = Join-Path $workspace $rel
        if (Test-Path $candidate) {
            $foundPng = (Resolve-Path $candidate).Path
            break
        }
    }

    if (-not $foundPng) {
        $candidateItem = Get-ChildItem -Path $workspace -Filter "*.png" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch "(\\target\\|\\dist\\|\\\.git\\|\\node_modules\\|\\build\\)" -and $_.Name -match "(?i)(icon|logo|app)" } |
            Select-Object -First 1
        if ($candidateItem) {
            $foundPng = $candidateItem.FullName
        }
    }

    if ($foundPng) {
        $genIco = Join-Path $target "app_generated.ico"
        $converter = "C:\forge\provision\windows\convert-icon.py"
        if (Test-Path $converter) {
            & python $converter "$foundPng" "$genIco" 2>&1 | Out-Null
            if (Test-Path $genIco) {
                return (Resolve-Path $genIco).Path
            }
        }
    }

    return $null
}

if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

$detectedIcon = Find-ProjectIcon -workspace $WorkspaceDir -target $TargetDir

if ($FindIconOnly) {
    if ($detectedIcon) {
        Write-Output $detectedIcon
    }
    exit 0
}

if (-not (Test-Path $DistDir)) {
    exit 0
}

$exeFiles = Get-ChildItem -Path $DistDir -Filter "*.exe" | Where-Object {
    $_.Name -notmatch "(?i)(-setup\.exe|_setup\.exe|\.tmp)"
}

if (-not $exeFiles -or $exeFiles.Count -eq 0) {
    exit 0
}

if ($detectedIcon) {
    Write-Host "[dev-forge : icon] Icono de aplicacion vinculado: $detectedIcon" -ForegroundColor Green
}

# --- Detección y normalización de versión y rama Git ---
if (-not $AppVersion) {
    if (Test-Path (Join-Path $WorkspaceDir "Cargo.toml")) {
        $cargoContent = Get-Content (Join-Path $WorkspaceDir "Cargo.toml") -Raw -ErrorAction SilentlyContinue
        if ($cargoContent -match '(?m)^version\s*=\s*"([^"]+)"') { $AppVersion = $matches[1] }
    } elseif (Test-Path (Join-Path $WorkspaceDir "pyproject.toml")) {
        $pyContent = Get-Content (Join-Path $WorkspaceDir "pyproject.toml") -Raw -ErrorAction SilentlyContinue
        if ($pyContent -match '(?m)version\s*=\s*"([^"]+)"') { $AppVersion = $matches[1] }
    } elseif (Test-Path (Join-Path $WorkspaceDir "package.json")) {
        $pkgContent = Get-Content (Join-Path $WorkspaceDir "package.json") -Raw -ErrorAction SilentlyContinue
        if ($pkgContent -match '"version"\s*:\s*"([^"]+)"') { $AppVersion = $matches[1] }
    }
}
if (-not $AppVersion) { $AppVersion = "0.1.0" }

if (-not $GitBranch -and (Test-Path (Join-Path $WorkspaceDir ".git"))) {
    try {
        $branch = (& git --git-dir=(Join-Path $WorkspaceDir ".git") rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if ($branch -and $branch -ne "HEAD") { $GitBranch = $branch }
    } catch {}
}

$cleanBranch = if ($GitBranch) { ($GitBranch -replace '[/\\:*?"<>|]', '-').Trim('-') } else { "" }
$displayVersion = if ($cleanBranch) { "$AppVersion-$cleanBranch" } else { $AppVersion }

if (-not $WixVersion) {
    # WiX requires strict Major.Minor.Build format (e.g. 1.2.3)
    if ($AppVersion -match '^(\d+)(\.(\d+))?(\.(\d+))?') {
        $major = $matches[1]
        $minor = if ($matches[3]) { $matches[3] } else { "0" }
        $patch = if ($matches[5]) { $matches[5] } else { "0" }
        $WixVersion = "$major.$minor.$patch"
    } else {
        $WixVersion = "1.0.0"
    }
}

Write-Host "[dev-forge : version] Version detectada: $displayVersion (WiX: $WixVersion)" -ForegroundColor Green

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

$targetExes = @()
$guiExe = $exeFiles | Where-Object { $_.Name -match "(?i)gui" } | Select-Object -First 1
if ($guiExe) {
    $targetExes += $guiExe
} else {
    $targetExes = $exeFiles
}

foreach ($exe in $targetExes) {
    $rawBaseName = $exe.BaseName
    $cleanAppName = $rawBaseName -replace '-(gui|cli)-windows\.x86_64$', ''
    $baseName = $cleanAppName
    $exeFullName = $exe.FullName
    Write-Host "[dev-forge : packager] Empaquetando `"$baseName`" ($displayVersion)..." -ForegroundColor Cyan

    # --- 1. Generar instalador Inno Setup (.exe) ---
    if ($iscc) {
        $issPath = Join-Path $TargetDir "$baseName.iss"

        $setupIconLine = ""
        $iconFileLine = ""
        $iconParam = ""
        if ($detectedIcon -and (Test-Path $detectedIcon)) {
            $setupIconLine = "SetupIconFile=$detectedIcon"
            $iconFileLine = "Source: `"$detectedIcon`"; DestDir: `"{app}`"; DestName: `"app.ico`"; Flags: ignoreversion"
            $iconParam = "; IconFilename: `"{app}\app.ico`""
        }

        $issContent = @"
[Setup]
AppName=$baseName
AppVersion=$displayVersion
DefaultDirName={autopf}\$baseName
DefaultGroupName=$baseName
OutputDir=$DistDir
OutputBaseFilename=$baseName-setup
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
$setupIconLine

[Files]
Source: "$exeFullName"; DestDir: "{app}"; Flags: ignoreversion
$iconFileLine

[Icons]
Name: "{group}\$baseName"; Filename: "{app}\$($exe.Name)"$iconParam
Name: "{autodesktop}\$baseName"; Filename: "{app}\$($exe.Name)"$iconParam
"@
        Set-Content -Path $issPath -Value $issContent -Encoding UTF8
        Write-Host "  -> Compilando Inno Setup: $baseName-setup.exe..." -ForegroundColor Yellow
        & $iscc /Q "$issPath"
        $standardSetup = Join-Path $DistDir "$baseName-setup.exe"
        if (Test-Path $standardSetup) {
            # Duplicar con nombre versionado para releases
            Copy-Item -Path $standardSetup -Destination (Join-Path $DistDir "$baseName-$displayVersion-setup.exe") -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] Inno Setup: $baseName-setup.exe ($baseName-$displayVersion-setup.exe) generado exitosamente." -ForegroundColor Green
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

        $wixIconTag = ""
        $wixIconProp = ""
        $wixIconComponent = ""
        $wixIconFeatureRef = ""
        $wixShortcutIcon = ""
        if ($detectedIcon -and (Test-Path $detectedIcon)) {
            $wixIconTag = "<Icon Id=`"AppIcon`" SourceFile=`"$detectedIcon`" />"
            $wixIconProp = "<Property Id=`"ARPPRODUCTICON`" Value=`"AppIcon`" />"
            $wixIconComponent = @"
          <Component Id="AppIconComponent" Guid="*" Win64="yes">
            <File Id="AppIconFile" Source="$detectedIcon" Name="app.ico" KeyPath="yes" />
          </Component>
"@
            $wixIconFeatureRef = "<ComponentRef Id=`"AppIconComponent`" />"
            $wixShortcutIcon = "Icon=`"AppIcon`""
        }

        $wxsContent = @"
<?xml version="1.0" encoding="utf-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="$baseName ($displayVersion)" Language="1033" Version="$WixVersion" Manufacturer="dev-forge" UpgradeCode="$upgradeGuid">
    <Package InstallerVersion="200" Compressed="yes" InstallScope="perMachine" />
    <MediaTemplate EmbedCab="yes" />
    $wixIconTag
    $wixIconProp
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="$baseName">
          <Component Id="MainExecutable" Guid="*" Win64="yes">
            <File Id="MainExeFile" Source="$exeFullName" KeyPath="yes" />
            <Shortcut Id="DesktopShortcut" Directory="DesktopFolder" Name="$baseName" WorkingDirectory="INSTALLFOLDER" $wixShortcutIcon Advertise="yes" />
            <Shortcut Id="StartMenuShortcut" Directory="ProgramMenuFolder" Name="$baseName" WorkingDirectory="INSTALLFOLDER" $wixShortcutIcon Advertise="yes" />
          </Component>
          $wixIconComponent
        </Directory>
      </Directory>
      <Directory Id="DesktopFolder" Name="Desktop" />
      <Directory Id="ProgramMenuFolder" Name="Programs" />
    </Directory>
    <Feature Id="MainApplication" Title="$baseName" Level="1">
      <ComponentRef Id="MainExecutable" />
      $wixIconFeatureRef
    </Feature>
  </Product>
</Wix>
"@
        Set-Content -Path $wxsPath -Value $wxsContent -Encoding UTF8
        Write-Host "  -> Compilando WiX MSI: $baseName.msi (Version: $WixVersion)..." -ForegroundColor Yellow
        & $candle -nologo -out "$wixObj" "$wxsPath" 2>&1 | Out-Null
        & $light -nologo -sval -spdb -out "$msiPath" "$wixObj" 2>&1 | Out-Null
        if (Test-Path (Join-Path $DistDir "$baseName.wixpdb")) {
            Remove-Item -Path (Join-Path $DistDir "$baseName.wixpdb") -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $msiPath) {
            # Duplicar con nombre versionado para releases
            Copy-Item -Path $msiPath -Destination (Join-Path $DistDir "$baseName-$displayVersion.msi") -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] WiX MSI: $baseName.msi ($baseName-$displayVersion.msi) generado exitosamente." -ForegroundColor Green
        } else {
            Write-Warning "  [FALLO] No se pudo generar $baseName.msi"
        }
    } else {
        Write-Warning "  [AVISO] WiX Toolset (candle/light) no disponible."
    }
}
