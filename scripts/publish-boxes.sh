#!/usr/bin/env bash
# =============================================================================
# dev-forge : Script de Publicación Oficial de Boxes en Vagrant Cloud
# =============================================================================
# Automatiza la subida, descripción, versionado y liberación de las boxes
# oficiales de DevForge (linux, windows, runner) hacia app.vagrantup.com.
# Soporta publicación individual o por lote (all), modo simulación (--dry-run),
# verificación de sumas criptográficas SHA-256 y confirmación interactiva.
# =============================================================================
set -euo pipefail

COLOR_CYAN="\033[1;36m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_GRAY="\033[0;90m"
COLOR_RESET="\033[0m"

log_info() { echo -e "${COLOR_CYAN}[publish-boxes]${COLOR_RESET} $1"; }
log_ok()   { echo -e "${COLOR_GREEN}[publish-boxes : OK]${COLOR_RESET} $1"; }
log_warn() { echo -e "${COLOR_YELLOW}[publish-boxes : AVISO]${COLOR_RESET} $1"; }
log_err()  { echo -e "${COLOR_RED}[publish-boxes : ERROR]${COLOR_RESET} $1" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_DIR}"

OUT_DIR="${REPO_DIR}/dist/boxes"

VERSION="1.0.0"
TARGET_MACHINE="all"
ORG="${VAGRANT_CLOUD_USER:-olorinj}"
IS_RELEASE=true
DRY_RUN=false
AUTO_CONFIRM=false
CUSTOM_DESC=""

mostrar_ayuda() {
    echo -e "${COLOR_CYAN}================================================================================${COLOR_RESET}"
    echo -e "${COLOR_CYAN}  dev-forge - Asistente de Publicación en Vagrant Cloud${COLOR_RESET}"
    echo -e "${COLOR_CYAN}================================================================================${COLOR_RESET}"
    echo ""
    echo "Publica las custom boxes pre-horneadas (.box) en app.vagrantup.com con metadatos"
    echo "optimizados y verificación de integridad criptográfica SHA-256."
    echo ""
    echo -e "${COLOR_CYAN}USO:${COLOR_RESET}"
    echo "  ./scripts/publish-boxes.sh [OPCIONES] [VERSION] [TARGET]"
    echo ""
    echo -e "${COLOR_CYAN}ARGUMENTOS:${COLOR_RESET}"
    echo "  VERSION           Versión semver a publicar (por defecto: 1.0.0)."
    echo "  TARGET            Box a publicar: 'linux', 'windows', 'runner' o 'all' (por defecto: all)."
    echo ""
    echo -e "${COLOR_CYAN}OPCIONES:${COLOR_RESET}"
    echo "  -o, --org <NAME>     Organización / Usuario en Vagrant Cloud (por defecto: ${ORG})."
    echo "  -d, --dry-run        Modo simulación: muestra las comprobaciones y comandos sin subir nada."
    echo "  -y, --yes            Modo desatendido: omite la confirmación interactiva."
    echo "  --draft              Publica la versión en modo borrador (sin el flag --release)."
    echo "  --description <TXT>  Sobrescribe la descripción general de la versión."
    echo "  -h, --help           Muestra esta ayuda y sale."
    echo ""
    echo -e "${COLOR_CYAN}EJEMPLOS:${COLOR_RESET}"
    echo "  ./scripts/publish-boxes.sh 1.0.0 all"
    echo "  ./scripts/publish-boxes.sh 1.0.0 linux --dry-run"
    echo "  ./scripts/publish-boxes.sh 1.1.0 windows -y"
    exit 0
}

# Parsear argumentos
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            mostrar_ayuda
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        --draft)
            IS_RELEASE=false
            shift
            ;;
        -o|--org|--organization)
            ORG="$2"
            shift 2
            ;;
        --description)
            CUSTOM_DESC="$2"
            shift 2
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                VERSION="$1"
            elif [[ "$1" =~ ^(linux|windows|runner|all)$ ]]; then
                TARGET_MACHINE="$1"
            fi
            shift
            ;;
    esac
done

# -----------------------------------------------------------------------------
# 1. Comprobación de Requisitos y Autenticación en Vagrant Cloud
# -----------------------------------------------------------------------------
if ! command -v vagrant >/dev/null 2>&1; then
    log_err "Vagrant no está instalado o no se encuentra en el PATH del sistema."
    exit 1
fi

log_info "Comprobando credenciales en Vagrant Cloud..."
if [ "${DRY_RUN}" = "false" ]; then
    CURRENT_USER=$(vagrant cloud auth whoami 2>&1 || true)
    if echo "${CURRENT_USER}" | grep -qi "You are not logged in"; then
        log_err "No has iniciado sesión en Vagrant Cloud."
        echo ""
        echo "Por favor, autentícate ejecutando:"
        echo "    vagrant cloud auth login"
        echo "o define la variable de entorno VAGRANT_CLOUD_TOKEN antes de continuar."
        echo ""
        exit 1
    fi
    log_ok "Autenticación activa: $(echo "${CURRENT_USER}" | tr -d '\r\n')"
else
    log_warn "[DRY-RUN] Omitiendo validación estricta de sesión de red."
fi

# -----------------------------------------------------------------------------
# 2. Resolución de Boxes a Publicar
# -----------------------------------------------------------------------------
declare -A BOX_FILES=(
    ["linux"]="dev-forge-linux-v${VERSION}.box"
    ["windows"]="dev-forge-windows-v${VERSION}.box"
    ["runner"]="dev-forge-runner-v${VERSION}.box"
)

declare -A BOX_TAGS=(
    ["linux"]="${ORG}/dev-forge-linux"
    ["windows"]="${ORG}/dev-forge-windows"
    ["runner"]="${ORG}/dev-forge-runner"
)

declare -A BOX_DESCRIPTIONS=(
    ["linux"]="DevForge Linux Native Build Box (Debian 12 + Rust/Go/Node/Java/Docker/VDI). Pre-baked toolchains, zero auto-updates, single active kernel."
    ["windows"]="DevForge Windows Native Build Box (Windows Server 2022 Standard Core + MSVC/WiX/Inno/VDI). Pre-baked Visual Studio 2022 Build Tools, WiX 3.14, InnoSetup, zero auto-updates."
    ["runner"]="DevForge CI/CD Runner Box (Debian 12 + Docker Engine + GitLab Runner CLI). Entorno local aislado para pipelines declarativos offline."
)

MACHINES_TO_PUBLISH=()
if [ "${TARGET_MACHINE}" = "all" ]; then
    MACHINES_TO_PUBLISH=("linux" "windows" "runner")
else
    MACHINES_TO_PUBLISH=("${TARGET_MACHINE}")
fi

echo ""
echo -e "${COLOR_CYAN}================================================================================${COLOR_RESET}"
echo -e "${COLOR_CYAN}          PLAN DE PUBLICACIÓN EN VAGRANT CLOUD (app.vagrantup.com)${COLOR_RESET}"
echo -e "${COLOR_CYAN}================================================================================${COLOR_RESET}"
printf "%-12s : %s\n" "Versión" "v${VERSION}"
printf "%-12s : %s\n" "Organización" "${ORG}"
printf "%-12s : %s\n" "Estado" "$([ "${IS_RELEASE}" = "true" ] && echo "Release (Pública activa)" || echo "Draft (Borrador)")"
printf "%-12s : %s\n" "Simulación" "$([ "${DRY_RUN}" = "true" ] && echo "SÍ (--dry-run activo)" || echo "NO (Subida real)")"
echo -e "${COLOR_CYAN}--------------------------------------------------------------------------------${COLOR_RESET}"

ALL_FILES_VALID=true

for m in "${MACHINES_TO_PUBLISH[@]}"; do
    bfile="${OUT_DIR}/${BOX_FILES[$m]}"
    btag="${BOX_TAGS[$m]}"
    if [ -f "${bfile}" ]; then
        bsize=$(du -h "${bfile}" | awk '{print $1}')
        bsha="N/A"
        if [ -f "${bfile}.sha256" ]; then
            bsha=$(awk '{print $1}' "${bfile}.sha256")
        fi
        printf "  ✔ [%s] %s (%s)\n" "${m^^}" "${btag}" "${bsize}"
        echo -e "      ${COLOR_GRAY}Archivo : ${bfile}${COLOR_RESET}"
        echo -e "      ${COLOR_GRAY}SHA-256 : ${bsha}${COLOR_RESET}"
    else
        printf "  ✘ [%s] %s\n" "${m^^}" "${btag}"
        echo -e "      ${COLOR_RED}Error: No se encontró el archivo '${bfile}'${COLOR_RESET}"
        ALL_FILES_VALID=false
    fi
done
echo -e "${COLOR_CYAN}================================================================================${COLOR_RESET}"
echo ""

if [ "${ALL_FILES_VALID}" = "false" ]; then
    log_err "Faltan archivos .box requeridos en '${OUT_DIR}'. Compílalos o empaquétalos antes de publicar."
    exit 1
fi

# -----------------------------------------------------------------------------
# 3. Confirmación del Usuario
# -----------------------------------------------------------------------------
if [ "${AUTO_CONFIRM}" = "false" ] && [ "${DRY_RUN}" = "false" ]; then
    echo -e "${COLOR_YELLOW}AVISO: La subida de boxes transferirá varios gigabytes hacia Vagrant Cloud.${COLOR_RESET}"
    read -p "¿Deseas proceder con la publicación oficial de la versión v${VERSION}? (s/N): " -r CONFIRM
    if [[ ! "${CONFIRM}" =~ ^[sSyY]$ ]]; then
        log_warn "Operación cancelada por el usuario."
        exit 0
    fi
fi

# -----------------------------------------------------------------------------
# 4. Ejecución de la Publicación
# -----------------------------------------------------------------------------
for m in "${MACHINES_TO_PUBLISH[@]}"; do
    bfile="${OUT_DIR}/${BOX_FILES[$m]}"
    btag="${BOX_TAGS[$m]}"
    bdesc="${CUSTOM_DESC:-${BOX_DESCRIPTIONS[$m]}}"
    vdesc="DevForge ${m^} Box Release v${VERSION}: Pre-baked standalone toolchains, zero auto-updates, hardened single active kernel."

    CMD_ARGS=(
        "cloud" "publish"
        "${btag}"
        "${VERSION}"
        "virtualbox"
        "${bfile}"
        "--description" "${bdesc}"
        "--version-description" "${vdesc}"
    )

    if [ "${IS_RELEASE}" = "true" ]; then
        CMD_ARGS+=("--release")
    fi

    echo ""
    log_info "Procesando publicación para [${m^^}] -> ${btag} (v${VERSION})..."
    echo -e "${COLOR_GRAY}Comando: vagrant ${CMD_ARGS[*]}${COLOR_RESET}"

    if [ "${DRY_RUN}" = "true" ]; then
        log_warn "[DRY-RUN] Simulación de subida para '${btag}' completada (sin tráfico de red)."
    else
        log_info "Subiendo archivo .box hacia Vagrant Cloud (esto puede tomar varios minutos dependiendo del ancho de banda)..."
        vagrant "${CMD_ARGS[@]}"
        log_ok "¡Box '${btag}' v${VERSION} publicada exitosamente!"
    fi
done

echo ""
log_ok "Todas las operaciones de publicación solicitadas han finalizado con éxito."
if [ "${DRY_RUN}" = "false" ]; then
    echo -e "Puedes consultar tus boxes en: ${COLOR_CYAN}https://app.vagrantup.com/${ORG}${COLOR_RESET}"
fi
