#!/usr/bin/env bash
# =============================================================================
# HashForge (Rust) - Script de Pruebas de Compilación y Verificación
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEV_FORGE="$FORGE_ROOT/bin/dev-forge"

GREEN="\e[32m"
RED="\e[31m"
CYAN="\e[36m"
RESET="\e[0m"

log_info() { echo -e "${CYAN}[HashForge-Rust Test]${RESET} $1"; }
log_ok()   { echo -e "${GREEN}[HashForge-Rust Test : PASS]${RESET} $1"; }
log_fail() { echo -e "${RED}[HashForge-Rust Test : FAIL]${RESET} $1" >&2; exit 1; }

TARGET="${1:-linux}"
EXPECTED_SHA="3424cecd9bc9384046f4b97b5012cc51037a0a58cbf547642dc71dc6a0ac0825"
EXPECTED_MD5="253c885072f588436970bcbc0fe47b9e"

log_info "Compilando HashForge (Rust) para target '$TARGET'..."
"$DEV_FORGE" build -p "$SCRIPT_DIR" -t "$TARGET" -k

DIST_DIR="$SCRIPT_DIR/dist"
if [ "$TARGET" = "linux" ] || [ "$TARGET" = "all" ]; then
    BIN="$DIST_DIR/hashforge"
    [ ! -f "$BIN" ] && log_fail "No se generó el binario Linux en $BIN"
    chmod +x "$BIN"
    log_info "Verificando ejecución en Linux: $BIN"
    OUT="$("$BIN" -s "dev-forge test" -j)"
    echo "  $OUT"
    echo "$OUT" | grep -q "$EXPECTED_SHA" && echo "$OUT" | grep -q "$EXPECTED_MD5" || log_fail "Hash inválido"
    log_ok "Binario Linux verificado (SHA-256: $EXPECTED_SHA)"
fi

if [ "$TARGET" = "windows" ] || [ "$TARGET" = "all" ]; then
    WIN_BIN="$DIST_DIR/hashforge.exe"
    [ ! -f "$WIN_BIN" ] && log_fail "No se generó el binario Windows en $WIN_BIN"
    file "$WIN_BIN" | grep -qi "PE32" || log_fail "No es un ejecutable PE32 válido"
    log_ok "Binario Windows verificado como PE32+ ($(stat -c %s "$WIN_BIN") bytes)"

    WIN_SETUP="$DIST_DIR/hashforge-setup.exe"
    [ ! -f "$WIN_SETUP" ] && log_fail "No se generó el instalador InnoSetup en $WIN_SETUP"
    file "$WIN_SETUP" | grep -qi "PE32" || log_fail "El instalador InnoSetup no es un ejecutable PE32 válido"
    log_ok "Instalador InnoSetup verificado ($(stat -c %s "$WIN_SETUP") bytes)"

    WIN_MSI="$DIST_DIR/hashforge.msi"
    [ ! -f "$WIN_MSI" ] && log_fail "No se generó el paquete WiX MSI en $WIN_MSI"
    file "$WIN_MSI" | grep -qi "Composite Document File\|OLE 2" || log_fail "El archivo MSI no es un paquete OLE válido"
    log_ok "Paquete WiX MSI verificado ($(stat -c %s "$WIN_MSI") bytes)"
fi

