#!/usr/bin/env bash
# =============================================================================
# HashForge (Java) - Script de Pruebas de Compilación y Verificación
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEV_FORGE="$FORGE_ROOT/bin/dev-forge"

GREEN="\e[32m"
RED="\e[31m"
CYAN="\e[36m"
RESET="\e[0m"

log_info() { echo -e "${CYAN}[HashForge-Java Test]${RESET} $1"; }
log_ok()   { echo -e "${GREEN}[HashForge-Java Test : PASS]${RESET} $1"; }
log_fail() { echo -e "${RED}[HashForge-Java Test : FAIL]${RESET} $1" >&2; exit 1; }

TARGET="${1:-linux}"
EXPECTED_SHA="3424cecd9bc9384046f4b97b5012cc51037a0a58cbf547642dc71dc6a0ac0825"
EXPECTED_MD5="253c885072f588436970bcbc0fe47b9e"

log_info "Compilando HashForge (Java) para target '$TARGET'..."
"$DEV_FORGE" build -p "$SCRIPT_DIR" -t "$TARGET" -k

DIST_DIR="$SCRIPT_DIR/dist"
JAR_BIN="$DIST_DIR/hashforge-java.jar"
[ ! -f "$JAR_BIN" ] && JAR_BIN="$(find "$DIST_DIR" -name "*.jar" ! -name "*-plain.jar" | head -n 1)"
[ ! -f "$JAR_BIN" ] && log_fail "No se generó el paquete JAR en $DIST_DIR"

log_info "Verificando integridad del archivo JAR ($JAR_BIN)..."
unzip -tq "$JAR_BIN" || log_fail "El archivo JAR está corrupto o es inválido"

if command -v java >/dev/null 2>&1; then
    log_info "Verificando ejecución de Java en el host..."
    OUT="$(java -jar "$JAR_BIN" -s "dev-forge test" -j)"
    echo "  $OUT"
    echo "$OUT" | grep -q "$EXPECTED_SHA" && echo "$OUT" | grep -q "$EXPECTED_MD5" || log_fail "Hash inválido"
    log_ok "Ejecución Java validada (SHA-256: $EXPECTED_SHA)"
else
    log_ok "JAR compilado y verificado estructuralmente ($(stat -c %s "$JAR_BIN") bytes)"
fi

