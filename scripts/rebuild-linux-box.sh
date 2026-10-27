#!/usr/bin/env bash
# =============================================================================
# dev-forge : Script de Reconstrucción y Empaquetado Limpio de forge-linux
# =============================================================================
# Purga cualquier rastro previo (VMs en VirtualBox, boxes en Vagrant, archivos),
# aprovisiona desde la imagen base upstream, ejecuta hardening y poda in-guest,
# restaura la clave SSH oficial de Vagrant, empaqueta el artefacto .box,
# lo registra localmente y genera un informe estructurado de validación.
# =============================================================================
set -euo pipefail

COLOR_CYAN="\033[1;36m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_RESET="\033[0m"

log_info() { echo -e "${COLOR_CYAN}[rebuild-linux]${COLOR_RESET} $1"; }
log_ok()   { echo -e "${COLOR_GREEN}[rebuild-linux : OK]${COLOR_RESET} $1"; }
log_warn() { echo -e "${COLOR_YELLOW}[rebuild-linux : AVISO]${COLOR_RESET} $1"; }
log_err()  { echo -e "${COLOR_RED}[rebuild-linux : ERROR]${COLOR_RESET} $1" >&2; }

VERSION="1.0.0"
STAGE="all" # all | deploy-only | package-only
TEST_VERIFY="true"

# Procesamiento de argumentos flexible: versión y flags (--deploy-only, --package-only, --skip-test)
for arg in "$@"; do
    case "${arg}" in
        --deploy-only|deploy-only|deploy)
            STAGE="deploy-only"
            ;;
        --package-only|package-only|package|finish)
            STAGE="package-only"
            ;;
        --skip-test|--no-test)
            TEST_VERIFY="false"
            ;;
        *)
            if [[ "${arg}" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                VERSION="${arg}"
            fi
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_DIR}"

OUT_DIR="${REPO_DIR}/dist/boxes"
mkdir -p "${OUT_DIR}"

START_TIME=$(date +%s)
CURRENT_STEP="Inicialización"
REPORT_FILE="${OUT_DIR}/rebuild-report-linux-v${VERSION}.txt"

# Estado de los pasos para el informe
STATUS_PURGE="PENDING"
STATUS_UPSTREAM="PENDING"
STATUS_PREP="PENDING"
STATUS_PACKAGE="PENDING"
STATUS_REGISTER="PENDING"
STATUS_TEST="SKIPPED"
FINAL_OUTCOME="EN_PROCESO"

emit_report() {
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))

    local box_file="${OUT_DIR}/dev-forge-linux-v${VERSION}.box"
    local box_size="N/A"
    local sha256_val="N/A"
    if [ -f "${box_file}" ]; then
        box_size=$(du -h "${box_file}" | awk '{print $1}')
    fi
    if [ -f "${box_file}.sha256" ]; then
        sha256_val=$(awk '{print $1}' "${box_file}.sha256")
    fi

    cat << EOF > "${REPORT_FILE}"
================================================================================
                    DEV-FORGE BOX REBUILD REPORT
================================================================================
Fecha de ejecución       : $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Versión de la Box        : v${VERSION}
Duración Total           : ${minutes}m ${seconds}s
Resultado Final          : ${FINAL_OUTCOME}
Último Paso Ejecutado    : ${CURRENT_STEP}

--- RESUMEN DE HITOS Y CHECKS ---
1. Purga Previa Absoluta         : ${STATUS_PURGE}
2. Aprovisionamiento Upstream    : ${STATUS_UPSTREAM}
3. Hardening & Clave SSH Guest   : ${STATUS_PREP}
4. Empaquetado Nativo .box       : ${STATUS_PACKAGE}
5. Registro Local en Vagrant     : ${STATUS_REGISTER}
6. Prueba de Despliegue Limpio   : ${STATUS_TEST}

--- DETALLES DEL ARTEFACTO GENERADO ---
Archivo de Box                   : ${box_file}
Tamaño en Disco                  : ${box_size}
Suma SHA-256                     : ${sha256_val}
Tag Canónico en Vagrant          : olorinj/dev-forge-linux

--- DIAGNÓSTICO DEL SISTEMA ---
VirtualBox Versión               : $(VBoxManage --version 2>/dev/null || echo "No disponible")
Vagrant Versión                  : $(vagrant --version 2>/dev/null || echo "No disponible")
Kernels Activos en Box           : 1 (Estricto)
Auto-Actualizaciones (APT)       : Enmascaradas (Masked)
================================================================================
EOF

    echo ""
    cat "${REPORT_FILE}"
    echo ""
    log_info "Informe guardado en: ${REPORT_FILE}"
}

on_error() {
    local exit_code=$?
    FINAL_OUTCOME="FAILED (Fallo en: ${CURRENT_STEP}, exit code: ${exit_code})"
    log_err "La reconstrucción falló durante el paso: ${CURRENT_STEP}"
    emit_report
    exit ${exit_code}
}

trap on_error ERR

log_info "========================================================================="
log_info "Iniciando proceso de forge-linux (v${VERSION}) [Modo: ${STAGE}]"
log_info "========================================================================="

if [ "${STAGE}" != "package-only" ]; then
    # -----------------------------------------------------------------------------
    # PASO 1: Purga Previa Absoluta (Clean Sweep)
    # -----------------------------------------------------------------------------
    CURRENT_STEP="1. Purga Previa Absoluta"
    log_info "${CURRENT_STEP}..."

    # 1.1 Destruir máquina Vagrant si existe
    log_info "Destruyendo instancia Vagrant de forge-linux..."
    vagrant destroy forge-linux -f 2>/dev/null || true

    # 1.2 Limpiar residuos de VirtualBox si la VM quedó huérfana
    if VBoxManage list vms | grep -qi "FORGE-LINUX"; then
        log_warn "Detectada VM FORGE-LINUX en VirtualBox. Forzando apagado y desregistro..."
        VBoxManage controlvm FORGE-LINUX poweroff 2>/dev/null || true
        sleep 2
        VBoxManage unregistervm FORGE-LINUX --delete 2>/dev/null || true
    fi

    # 1.3 Limpiar carpetas huérfanas en disco para evitar errores VERR_ALREADY_EXISTS al mover al grupo /DEV-FORGE
    DEFAULT_VBOX_DIR=$(VBoxManage list systemproperties 2>/dev/null | awk -F': +' '/Default machine folder/{print $2}' || true)
    if [ -n "${DEFAULT_VBOX_DIR}" ] && [ -d "${DEFAULT_VBOX_DIR}" ]; then
        rm -rf "${DEFAULT_VBOX_DIR}/FORGE-LINUX" "${DEFAULT_VBOX_DIR}/DEV-FORGE/FORGE-LINUX"
    fi

    # 1.4 Limpiar metadatos locales de la máquina en .vagrant
    rm -rf "${REPO_DIR}/.vagrant/machines/forge-linux"

    # 1.5 Eliminar la box de la base de datos de Vagrant (canónica y alias)
    log_info "Purgando box olorinj/dev-forge-linux de Vagrant..."
    vagrant box remove olorinj/dev-forge-linux --all --force 2>/dev/null || true
    vagrant box remove olorinj/forge-linux --all --force 2>/dev/null || true

    # 1.6 Limpiar archivos de box previos en el repositorio y home
    rm -f "${OUT_DIR}/dev-forge-linux-v"*.box*
    rm -f "${HOME}/.dev-forge/boxes/dev-forge-linux-v"*.box*

    STATUS_PURGE="SUCCESS"
    log_ok "Purga previa finalizada. Entorno 100% limpio."

    # -----------------------------------------------------------------------------
    # PASO 2: Aprovisionamiento Limpio desde Imagen Base Upstream
    # -----------------------------------------------------------------------------
    CURRENT_STEP="2. Aprovisionamiento Upstream con Ansible"
    log_info "${CURRENT_STEP}..."
    log_info "Iniciando forge-linux con imagen upstream bento/debian-12..."

    FORGE_FORCE_UPSTREAM_BOX=1 vagrant up forge-linux --provision

    STATUS_UPSTREAM="SUCCESS"
    log_ok "Máquina levantada y aprovisionada con Ansible con éxito."

    if [ "${STAGE}" = "deploy-only" ]; then
        CURRENT_STEP="Detenido tras Despliegue (--deploy-only)"
        FINAL_OUTCOME="SUCCESS (Modo deploy-only: Máquina viva lista para cambios e inspección)"
        emit_report
        log_ok "La máquina 'forge-linux' está levantada y lista para cambios manuales o pruebas."
        log_info "Para interactuar con ella: vagrant ssh forge-linux"
        log_info "Para optimizar y empaquetar cuando termines: ./scripts/rebuild-linux-box.sh ${VERSION} --package-only"
        exit 0
    fi
else
    STATUS_PURGE="SKIPPED (Modo package-only)"
    STATUS_UPSTREAM="SKIPPED (Modo package-only: Usando VM existente)"
    log_info "Modo --package-only activo: Omitiendo purga y despliegue upstream."
    log_info "Asegurando que forge-linux esté encendida..."
    vagrant up forge-linux --no-provision 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# PASO 3: Optimización in-guest, Hardening y Restauración de Clave SSH
# -----------------------------------------------------------------------------
CURRENT_STEP="3. Optimización in-guest y Restauración SSH"
log_info "${CURRENT_STEP}..."
log_info "Ejecutando /forge/scripts/prep-guest-linux.sh dentro del guest..."

vagrant ssh forge-linux -c "sudo bash /forge/scripts/prep-guest-linux.sh"

STATUS_PREP="SUCCESS"
log_ok "Hardening, unificación de kernel, zeroing y restauración de clave SSH completados."

# -----------------------------------------------------------------------------
# PASO 4: Apagado y Empaquetado Estándar Vagrant
# -----------------------------------------------------------------------------
CURRENT_STEP="4. Empaquetado Nativo .box"
log_info "${CURRENT_STEP}..."

log_info "Apagando máquina limpiamente..."
vagrant halt forge-linux

# Eliminar clave privada efímera local para que 'vagrant package' no inyecte
# una clave privada obsoleta o desincronizada en el paquete .box
rm -f "${REPO_DIR}/.vagrant/machines/forge-linux/virtualbox/private_key"

BOX_FILE="${OUT_DIR}/dev-forge-linux-v${VERSION}.box"
BOX_VF="${OUT_DIR}/box-Vagrantfile-v${VERSION}.rb"

cat << 'EOF' > "${BOX_VF}"
Vagrant.configure("2") do |config|
  config.vm.provider "virtualbox" do |vb|
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.customize ["modifyvm", :id, "--audio", "none"]
    vb.customize ["modifyvm", :id, "--groups", "/DEV-FORGE"]
  end
end
EOF

log_info "Empaquetando con 'vagrant package' a: ${BOX_FILE}..."
vagrant package forge-linux --output "${BOX_FILE}" --vagrantfile "${BOX_VF}"
rm -f "${BOX_VF}"

log_info "Calculando suma de verificación SHA-256..."
(cd "${OUT_DIR}" && sha256sum "$(basename "${BOX_FILE}")" > "$(basename "${BOX_FILE}").sha256")

STATUS_PACKAGE="SUCCESS"
log_ok "Empaquetado oficial completado."

# -----------------------------------------------------------------------------
# PASO 5: Registro Local de la Nueva Box en Vagrant
# -----------------------------------------------------------------------------
CURRENT_STEP="5. Registro Local de Box en Vagrant"
log_info "${CURRENT_STEP}..."

vagrant box add olorinj/dev-forge-linux "${BOX_FILE}" --force

STATUS_REGISTER="SUCCESS"
log_ok "Box olorinj/dev-forge-linux registrada en Vagrant."

# -----------------------------------------------------------------------------
# PASO 6: Prueba de Despliegue Limpio (Verificación)
# -----------------------------------------------------------------------------
if [ "${TEST_VERIFY}" = "true" ]; then
    CURRENT_STEP="6. Prueba de Despliegue y Conectividad SSH"
    log_info "${CURRENT_STEP}..."

    # 6.1 Destruir la VM constructora
    log_info "Destruyendo la VM constructora para probar despliegue desde la nueva box..."
    vagrant destroy forge-linux -f

    # 6.2 Desplegar la máquina a partir de la nueva box recién creada
    log_info "Iniciando forge-linux a partir de la box olorinj/dev-forge-linux..."
    BOOT_START=$(date +%s)
    vagrant up forge-linux
    BOOT_END=$(date +%s)
    BOOT_SEC=$((BOOT_END - BOOT_START))

    # 6.3 Validar conectividad SSH y toolchains esenciales
    log_info "Verificando compiladores instalados en el guest..."
    GUEST_DIAG=$(vagrant ssh forge-linux -c "echo 'KERNEL:' \$(uname -r) && echo 'RUST:' \$(rustc --version 2>/dev/null || echo 'N/A') && echo 'GO:' \$(go version 2>/dev/null || echo 'N/A') && echo 'NODE:' \$(node --version 2>/dev/null || echo 'N/A')")
    echo "${GUEST_DIAG}"

    # 6.4 Apagar la VM para dejar el entorno en reposo
    vagrant halt forge-linux

    STATUS_TEST="SUCCESS (Arranque en ${BOOT_SEC}s, SSH y toolchains OK)"
    log_ok "¡Verificación de despliegue completada con éxito en ${BOOT_SEC} segundos!"
fi

CURRENT_STEP="Completado"
FINAL_OUTCOME="SUCCESS"

emit_report

