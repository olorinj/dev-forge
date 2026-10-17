[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
 = [System.Text.Encoding]::UTF8

param([string] = "windows")
 = "Stop"

 = Split-Path -Parent .MyCommand.Path
 = (Resolve-Path "\..\..\..").Path
 = "in\dev-forge.ps1"

Write-Host "[HashForge-Java Test] Compilando para target ''..." -ForegroundColor Cyan
& powershell.exe -ExecutionPolicy Bypass -NoProfile -File  build -p "" -t "" -k

 = "\dist"
 = Join-Path  "hashforge-java.jar"
if (-not (Test-Path )) {
     = Get-ChildItem -Path  -Filter *.jar -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '*-plain.jar' } | Select-Object -First 1
    if ($found) { $jarBin = $found.FullName }
}

if (-not (Test-Path )) {
    throw "No se encontro paquete JAR en "
}

 = (Get-Item ).Length
Write-Host "[HashForge-Java Test : PASS] Paquete JAR verificado ( bytes)" -ForegroundColor Green
