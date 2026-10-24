#!/usr/bin/env bash
# =============================================================================
# dev-forge : Universal One-Line Installer for Linux & macOS
# =============================================================================
set -e

COLOR_CYAN="\033[1;36m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_RESET="\033[0m"

log_info() { echo -e "${COLOR_CYAN}[dev-forge]${COLOR_RESET} $1"; }
log_ok()   { echo -e "${COLOR_GREEN}[dev-forge : OK]${COLOR_RESET} $1"; }
log_warn() { echo -e "${COLOR_YELLOW}[dev-forge : AVISO]${COLOR_RESET} $1"; }
log_err()  { echo -e "${COLOR_RED}[dev-forge : ERROR]${COLOR_RESET} $1" >&2; }

echo -e "${COLOR_CYAN}"
cat << 'EOF'
     _                  __                     
  __| | _____   __     / _| ___  _ __ __ _  ___ 
 / _` |/ _ \ \ / /____| |_ / _ \| '__/ _` |/ _ \
| (_| |  __/\ V /_____|  _| (_) | | | (_| |  __/
 \__,_|\___| \_/      |_|  \___/|_|  \__, |\___|
                                     |___/      
EOF
echo -e "${COLOR_RESET}"
echo -e "Forja Universal de Compilación Multiplataforma (Linux / macOS / Windows)"
echo -e "=========================================================================\n"

# 1. Detección de Sistema Operativo y Arquitectura
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
    x86_64|amd64) TARGET_ARCH="x86_64" ;;
    aarch64|arm64) TARGET_ARCH="aarch64" ;;
    *)
        log_err "Arquitectura '$ARCH' no soportada directamente."
        exit 1
        ;;
esac

case "$OS" in
    linux)
        TARGET_OS="unknown-linux-gnu"
        ;;
    darwin)
        TARGET_OS="apple-darwin"
        ;;
    *)
        log_err "Sistema operativo '$OS' no soportado por install.sh (usa install.ps1 en Windows)."
        exit 1
        ;;
esac

TARGET_TRIPLE="${TARGET_ARCH}-${TARGET_OS}"
log_info "Plataforma detectada: ${TARGET_TRIPLE}"

# 2. Directorio de instalación local de usuario (sin requerir sudo)
INSTALL_DIR="${DEV_FORGE_INSTALL_DIR:-${HOME}/.local/bin}"
mkdir -p "$INSTALL_DIR"
TARGET_BIN="${INSTALL_DIR}/dev-forge"

# 3. Determinar método de instalación (local o descarga remota)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

if [ -n "$SCRIPT_DIR" ] && [ -f "${SCRIPT_DIR}/Cargo.toml" ] && [ -d "${SCRIPT_DIR}/crates/forge-cli" ]; then
    log_info "Detectado repositorio local en '${SCRIPT_DIR}'. Instalando desde fuentes locales..."
    if command -v cargo >/dev/null 2>&1; then
        (cd "$SCRIPT_DIR" && cargo build --release --bin dev-forge)
        cp -f "${SCRIPT_DIR}/target/release/dev-forge" "$TARGET_BIN"
    else
        log_warn "Cargo no encontrado en el host. Enlazando lanzador de arranque inteligente..."
        ln -sf "${SCRIPT_DIR}/bin/dev-forge" "$TARGET_BIN"
    fi
else
    # Descarga de Release precompilado desde GitHub
    REPO="${FORGE_REPO:-olorinj/dev-forge}"
    log_info "Descargando binario nativo precompilado desde ${REPO}..."
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT

    LATEST_RELEASE_URL="https://github.com/${REPO}/releases/latest/download/dev-forge-${TARGET_TRIPLE}.tar.gz"
    if curl -sSfL "$LATEST_RELEASE_URL" -o "${TMP_DIR}/dev-forge.tar.gz" 2>/dev/null; then
        tar -xzf "${TMP_DIR}/dev-forge.tar.gz" -C "$TMP_DIR"
        mv -f "${TMP_DIR}/dev-forge" "$TARGET_BIN"
    else
        log_warn "No se pudo descargar release precompilado directo (¿aún no publicado?)."
        if command -v cargo >/dev/null 2>&1; then
            log_info "Compilando con cargo desde repositorio Git..."
            cargo install --git "https://github.com/${REPO}.git" --bin dev-forge --root "${HOME}/.local"
        else
            log_err "No hay binarios precompilados disponibles ni 'cargo' instalado."
            log_info "Instala Rust con: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
            exit 1
        fi
    fi
fi

chmod +x "$TARGET_BIN"
log_ok "Binario dev-forge instalado en: ${TARGET_BIN}"

# 4. Configuración automática de PATH en el perfil del usuario
PATH_UPDATED=0
case ":$PATH:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
        log_info "Añadiendo ${INSTALL_DIR} a tu PATH..."
        SHELL_RC=""
        if [ -n "$ZSH_VERSION" ] || [ -f "${HOME}/.zshrc" ]; then
            SHELL_RC="${HOME}/.zshrc"
        elif [ -n "$BASH_VERSION" ] || [ -f "${HOME}/.bashrc" ]; then
            SHELL_RC="${HOME}/.bashrc"
        elif [ -f "${HOME}/.profile" ]; then
            SHELL_RC="${HOME}/.profile"
        fi

        if [ -n "$SHELL_RC" ]; then
            if ! grep -q 'export PATH="\$HOME/\.local/bin:\$PATH"' "$SHELL_RC" 2>/dev/null; then
                if [ -w "$SHELL_RC" ] && echo -e '\n# dev-forge global binary access\nexport PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC" 2>/dev/null; then
                    PATH_UPDATED=1
                    log_ok "Configuración persistente añadida a ${SHELL_RC}"
                else
                    log_warn "No se pudo modificar ${SHELL_RC} automáticamente. Añade manualmente: export PATH=\"\$HOME/.local/bin:\$PATH\""
                fi
            fi
        fi
        export PATH="${INSTALL_DIR}:${PATH}"
        ;;
esac

# 5. Ejecutar auto-tuning del host y diagnóstico
echo ""
log_info "Ejecutando dimensionamiento de hardware y configuración del host..."
"$TARGET_BIN" tune

echo ""
log_info "Ejecutando diagnóstico pre-vuelo (dev-forge doctor)..."
"$TARGET_BIN" doctor || true

echo ""
echo -e "${COLOR_GREEN}=========================================================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}✔ ¡Instalación de dev-forge completada con éxito!${COLOR_RESET}"
if [ $PATH_UPDATED -eq 1 ]; then
    echo -e "${COLOR_YELLOW}Nota: Ejecuta 'source ${SHELL_RC}' o abre una nueva terminal para recargar el PATH.${COLOR_RESET}"
fi
echo -e "Puedes invocar la forja desde cualquier directorio con: ${COLOR_CYAN}dev-forge build${COLOR_RESET}"
echo -e "${COLOR_GREEN}=========================================================================${COLOR_RESET}\n"
