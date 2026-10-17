#!/usr/bin/env bash
# =============================================================================
# HashForge - Orquestador Maestro de Pruebas Multi-Lenguaje y Multi-VM
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANG_ARG="${1:-all}"
TARGET_ARG="${2:-all}"

GREEN="\e[32m"
RED="\e[31m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

echo -e "${CYAN}${BOLD}"
echo "================================================================="
echo "   HashForge: Suite Universal de Pruebas Multi-Lenguaje"
echo "================================================================="
echo -e "${RESET}"
echo -e "Lenguaje(s): ${BOLD}${LANG_ARG}${RESET}"
echo -e "Destino(s):  ${BOLD}${TARGET_ARG}${RESET}"
echo ""

if [ "$LANG_ARG" = "all" ]; then
    LANGUAGES=("rust" "python" "c" "cpp" "go" "java" "android")
else
    LANGUAGES=("$LANG_ARG")
fi

FAILED=0
PASSED=0

for lang in "${LANGUAGES[@]}"; do
    SUB_DIR="$SCRIPT_DIR/$lang"
    if [ ! -d "$SUB_DIR" ]; then
        echo -e "${RED}[ERROR] Lenguaje '$lang' no encontrado en $SUB_DIR${RESET}"
        FAILED=$((FAILED + 1))
        continue
    fi

    echo -e "${CYAN}-----------------------------------------------------------------${RESET}"
    echo -e "${BOLD}▶ Ejecutando pruebas para: ${lang^^} (Target: $TARGET_ARG)${RESET}"
    echo -e "${CYAN}-----------------------------------------------------------------${RESET}"

    if [ -f "$SUB_DIR/test.sh" ]; then
        if bash "$SUB_DIR/test.sh" "$TARGET_ARG"; then
            echo -e "${GREEN}✔ ${lang^^}: PRUEBAS SUPERADAS${RESET}\n"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}✘ ${lang^^}: PRUEBAS FALLIDAS${RESET}\n"
            FAILED=$((FAILED + 1))
        fi
    else
        echo -e "${RED}[AVISO] No se encontró test.sh en $SUB_DIR${RESET}\n"
        FAILED=$((FAILED + 1))
    fi
done

echo -e "${CYAN}=================================================================${RESET}"
echo -e "${BOLD}RESUMEN DE PRUEBAS MULTI-LENGUAJE:${RESET}"
echo -e "  ${GREEN}Superados:${RESET} $PASSED"
echo -e "  ${RED}Fallidos: ${RESET} $FAILED"
echo -e "${CYAN}=================================================================${RESET}"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
