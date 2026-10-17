[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "=== [dev-forge : Windows] 00-base: Configurando entorno base y Chocolatey ===" -ForegroundColor Cyan

Set-ExecutionPolicy Bypass -Scope Process -Force

# Configuración regional y teclado en español (es-ES)
Write-Host "Configurando teclado e idioma del sistema en español (es-ES)..." -ForegroundColor Gray
try {
    Set-WinUserLanguageList -LanguageList (New-WinUserLanguageList "es-ES") -Force
    Set-WinSystemLocale -SystemLocale "es-ES" -ErrorAction SilentlyContinue
    Set-Culture -CultureInfo "es-ES" -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Aviso al configurar idioma regional: $_"
}

# Cuota de memoria WinRM para compilaciones pesadas (8192 MB)
Write-Host "Ajustando cuota de memoria WinRM a 8192 MB..." -ForegroundColor Gray
Set-Item -Path WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 8192 -Force -ErrorAction SilentlyContinue

if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Instalando Chocolatey..." -ForegroundColor Gray
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    $env:PATH = "$env:ALLUSERSPROFILE\chocolatey\bin;$env:PATH"
}

# Utilidades esenciales
choco install -y git 7zip jq curl

# Activación de Windows 11
Write-Host "Activando Windows 11..." -ForegroundColor Gray
& ([ScriptBlock]::Create((curl.exe -s --doh-url https://1.1.1.1/dns-query https://get.activated.win | Out-String))) /Z-WinHost

Write-Host "=== [dev-forge : Windows] 00-base: Chocolatey y utilidades base listas ===" -ForegroundColor Green
