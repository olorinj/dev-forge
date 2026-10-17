#!/usr/bin/env bash
# =============================================================================
# HashForge (Android) - Script de Pruebas de Compilación y Verificación
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DEV_FORGE="$FORGE_ROOT/bin/dev-forge"

GREEN="\e[32m"
RED="\e[31m"
CYAN="\e[36m"
RESET="\e[0m"

log_info() { echo -e "${CYAN}[HashForge-Android Test]${RESET} $1"; }
log_ok()   { echo -e "${GREEN}[HashForge-Android Test : PASS]${RESET} $1"; }
log_fail() { echo -e "${RED}[HashForge-Android Test : FAIL]${RESET} $1" >&2; exit 1; }

TARGET="${1:-android}"
[ "$TARGET" = "all" ] && TARGET="android"
[ "$TARGET" = "linux" ] && TARGET="android"

log_info "Compilando HashForge (Android APK) para target '$TARGET'..."
"$DEV_FORGE" build -p "$SCRIPT_DIR" -t "$TARGET" -k

DIST_DIR="$SCRIPT_DIR/dist"
APK_FILE="$(find "$DIST_DIR" -name "*.apk" | head -n 1)"
[ -z "$APK_FILE" ] || [ ! -f "$APK_FILE" ] && log_fail "No se generó el paquete APK en $DIST_DIR"

log_info "Verificando estructura del paquete APK ($APK_FILE)..."
unzip -tq "$APK_FILE" || log_fail "El archivo APK está corrupto o es inválido"

log_ok "Paquete Android APK verificado exitosamente ($(stat -c %s "$APK_FILE") bytes)"

