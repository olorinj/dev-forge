#!/usr/bin/env bash
# =============================================================================
# HashForge (Node.js & Web) - Script de Pruebas de Compilación y Verificación
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEV_FORGE="$FORGE_ROOT/bin/dev-forge"

GREEN="\e[32m"
RED="\e[31m"
CYAN="\e[36m"
RESET="\e[0m"

log_info() { echo -e "${CYAN}[HashForge-Node Test]${RESET} $1"; }
log_ok()   { echo -e "${GREEN}[HashForge-Node Test : PASS]${RESET} $1"; }
log_fail() { echo -e "${RED}[HashForge-Node Test : FAIL]${RESET} $1" >&2; exit 1; }

TARGET="${1:-linux}"
EXPECTED_SHA="3424cecd9bc9384046f4b97b5012cc51037a0a58cbf547642dc71dc6a0ac0825"
EXPECTED_MD5="253c885072f588436970bcbc0fe47b9e"

log_info "Compilando y empaquetando HashForge (Node.js / Web) para target '$TARGET'..."
"$DEV_FORGE" build -p "$SCRIPT_DIR" -t "$TARGET" -k

DIST_DIR="$SCRIPT_DIR/dist"
NODE_BIN="$DIST_DIR/hashforge-node.js"
WEB_HTML="$DIST_DIR/index.html"

[ ! -f "$NODE_BIN" ] && log_fail "No se generó el archivo CLI en $NODE_BIN"
[ ! -f "$WEB_HTML" ] && log_fail "No se generó la interfaz Web en $WEB_HTML"

chmod +x "$NODE_BIN"
log_info "Verificando ejecución de Node.js: $NODE_BIN"
OUT="$(node "$NODE_BIN" -s "dev-forge test" -j)"
echo "  $OUT"
echo "$OUT" | grep -q "$EXPECTED_SHA" && echo "$OUT" | grep -q "$EXPECTED_MD5" || log_fail "Hash inválido"
log_ok "HashForge Node.js / Web verificado exitosamente (SHA-256: $EXPECTED_SHA)"

