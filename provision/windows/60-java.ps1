[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 60-java: Instalando OpenJDK 21 LTS y Gradle ===" -ForegroundColor Cyan

if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    choco install -y openjdk21 gradle
}

Write-Host "=== [dev-forge : Windows] 60-java: Java y Gradle configurados ===" -ForegroundColor Green

