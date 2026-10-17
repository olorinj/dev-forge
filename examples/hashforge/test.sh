#!/usr/bin/env bash
# =============================================================================
# HashForge - Script de Pruebas de Compilación y Verificación (Linux / Bash)
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEV_FORGE="$FORGE_ROOT/bin/dev-forge"

GREEN="\e[32m"
RED="\e[31m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"

log_info() { echo -e "${CYAN}[HashForge Test]${RESET} $1"; }
log_ok()   { echo -e "${GREEN}[HashForge Test : PASS]${RESET} $1"; }
log_fail() { echo -e "${RED}[HashForge Test : FAIL]${RESET} $1" >&2; exit 1; }

TARGET="${1:-linux}"
EXPECTED_SHA256="7fa5a0fe7bcdd886b62fc0bcddbf1a70c86801bb61dd66c430485981ee8aa6bf"
EXPECTED_MD5="00dfa0bf846830cfcae67dca1f543166"

log_info "Iniciando suite de pruebas para HashForge"
log_info "Directorio del proyecto: $SCRIPT_DIR"
log_info "Destino de compilación:   $TARGET"

# 1. Compilación mediante dev-forge
log_info "Ejecutando orquestador dev-forge..."
"$DEV_FORGE" build -p "$SCRIPT_DIR" -t "$TARGET" -k

# 2. Verificación de binarios generados
DIST_DIR="$SCRIPT_DIR/dist"
if [ ! -d "$DIST_DIR" ]; then
    log_fail "No se generó el directorio dist/ tras la compilación."
fi

if [ "$TARGET" = "linux" ] || [ "$TARGET" = "all" ]; then
    LINUX_BIN="$DIST_DIR/hashforge"
    if [ ! -f "$LINUX_BIN" ]; then
        log_fail "No se encontró el binario Linux en $LINUX_BIN"
    fi
    chmod +x "$LINUX_BIN"

    log_info "Verificando ejecución de binario Linux..."
    OUTPUT="$("$LINUX_BIN" -s "dev-forge test" -j)"
    echo "$OUTPUT"

    if echo "$OUTPUT" | grep -q "$EXPECTED_SHA256" && echo "$OUTPUT" | grep -q "$EXPECTED_MD5"; then
        log_ok "Binario Linux verificado correctamente con hash esperado (SHA-256: $EXPECTED_SHA256)"
    else
        log_fail "El binario Linux devolvió un hash incorrecto: $OUTPUT"
    fi
fi

if [ "$TARGET" = "windows" ] || [ "$TARGET" = "all" ]; then
    WIN_BIN="$DIST_DIR/hashforge.exe"
    if [ ! -f "$WIN_BIN" ]; then
        log_fail "No se encontró el binario Windows en $WIN_BIN"
    fi

    log_info "Verificando cabeceras del binario Windows MSVC ($WIN_BIN)..."
    if command -v file >/dev/null 2>&1; then
        FILE_INFO="$(file "$WIN_BIN")"
        echo "  $FILE_INFO"
        if echo "$FILE_INFO" | grep -qi "PE32"; then
            log_ok "Binario Windows verificado como ejecutable nativo PE32+ MSVC"
        else
            log_fail "El archivo no parece ser un ejecutable PE32 válido: $FILE_INFO"
        fi
    else
        log_ok "Binario Windows encontrado con tamaño: $(stat -c %s "$WIN_BIN") bytes"
    fi
fi

echo ""
log_ok "Todas las pruebas de HashForge finalizaron con éxito para target '$TARGET'."

