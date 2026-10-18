[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# =============================================================================
# dev-forge : Host Resource Auto-Detection & Dimensioning (PowerShell)
# =============================================================================

$ForgeDir = (Get-Item $PSScriptRoot).Parent.FullName
$DevForge = Join-Path $ForgeDir "bin\dev-forge.ps1"
& $DevForge tune @args
exit $LASTEXITCODE
