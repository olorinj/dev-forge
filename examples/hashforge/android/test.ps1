[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
 = [System.Text.Encoding]::UTF8

param([string] = "android")
 = "Stop"

if ($Target -eq "all" -or $Target -eq "windows") { $Target = "android" }

 = Split-Path -Parent .MyCommand.Path
 = (Resolve-Path "\..\..\..").Path
 = "in\dev-forge.ps1"

Write-Host "[HashForge-Android Test] Compilando para target ''..." -ForegroundColor Cyan
& powershell.exe -ExecutionPolicy Bypass -NoProfile -File  build -p "" -t "" -k

 = "\dist"
 = Get-ChildItem -Path  -Filter *.apk -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $apkFile) {
    throw "No se encontro paquete APK en "
}

 = $apkFile.Length
Write-Host "[HashForge-Android Test : PASS] Paquete Android APK verificado ($sz bytes)" -ForegroundColor Green
