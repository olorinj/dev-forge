#!/usr/bin/env bash
# =============================================================================
# HashForge (Go) - Script de Pruebas de Compilación y Verificación
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEV_FORGE="$FORGE_ROOT/bin/dev-forge"

GREEN="\e[32m"
RED="\e[31m"
CYAN="\e[36m"
RESET="\e[0m"

log_info() { echo -e "${CYAN}[HashForge-Go Test]${RESET} $1"; }
log_ok()   { echo -e "${GREEN}[HashForge-Go Test : PASS]${RESET} $1"; }
log_fail() { echo -e "${RED}[HashForge-Go Test : FAIL]${RESET} $1" >&2; exit 1; }

TARGET="${1:-linux}"
EXPECTED_SHA="3424cecd9bc9384046f4b97b5012cc51037a0a58cbf547642dc71dc6a0ac0825"
EXPECTED_MD5="253c885072f588436970bcbc0fe47b9e"

log_info "Compilando HashForge (Go) para target '$TARGET'..."
"$DEV_FORGE" build -p "$SCRIPT_DIR" -t "$TARGET" -k

DIST_DIR="$SCRIPT_DIR/dist"
if [ "$TARGET" = "linux" ] || [ "$TARGET" = "all" ]; then
    BIN="$DIST_DIR/hashforge-go"
    [ ! -f "$BIN" ] && BIN="$DIST_DIR/go"
    [ ! -f "$BIN" ] && log_fail "No se generó el binario Linux en $DIST_DIR"
    chmod +x "$BIN"
    log_info "Verificando ejecución en Linux: $BIN"
    OUT="$("$BIN" -s "dev-forge test" -j)"
    echo "  $OUT"
    echo "$OUT" | grep -q "$EXPECTED_SHA" && echo "$OUT" | grep -q "$EXPECTED_MD5" || log_fail "Hash inválido"
    log_ok "Binario Go verificado (SHA-256: $EXPECTED_SHA)"
fi

if [ "$TARGET" = "windows" ] || [ "$TARGET" = "all" ]; then
    WIN_BIN="$DIST_DIR/hashforge-go.exe"
    [ ! -f "$WIN_BIN" ] && WIN_BIN="$DIST_DIR/go.exe"
    [ ! -f "$WIN_BIN" ] && log_fail "No se generó el binario Windows en $DIST_DIR"
    file "$WIN_BIN" | grep -qi "PE32" || log_fail "No es un ejecutable PE32 válido"
    log_ok "Binario Windows verificado como PE32+ ($(stat -c %s "$WIN_BIN") bytes)"
fi
