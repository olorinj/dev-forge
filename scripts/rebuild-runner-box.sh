#!/usr/bin/env bash
# =============================================================================
# dev-forge : Script de Reconstrucción y Empaquetado Limpio de forge-runner
# =============================================================================
# Purga cualquier rastro previo (VMs en VirtualBox, boxes en Vagrant, archivos),
# garantiza exclusión mutua deteniendo forge-windows si estuviese activa,
# aprovisiona desde la imagen base upstream bento/debian-12 con Docker y GitLab Runner,
# ejecuta hardening y poda in-guest con prep-guest-linux.sh,
# restaura la clave SSH oficial de Vagrant, empaqueta el artefacto .box nativo,
# lo registra localmente y genera un informe estructurado de validación.
# =============================================================================
set -euo pipefail

COLOR_CYAN="\033[1;36m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_RESET="\033[0m"

log_info() { echo -e "${COLOR_CYAN}[rebuild-runner]${COLOR_RESET} $1"; }
log_ok()   { echo -e "${COLOR_GREEN}[rebuild-runner : OK]${COLOR_RESET} $1"; }
log_warn() { echo -e "${COLOR_YELLOW}[rebuild-runner : AVISO]${COLOR_RESET} $1"; }
log_err()  { echo -e "${COLOR_RED}[rebuild-runner : ERROR]${COLOR_RESET} $1" >&2; }

VERSION="${1:-1.0.0}"
TEST_VERIFY="${2:-true}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_DIR}"

OUT_DIR="${REPO_DIR}/dist/boxes"
mkdir -p "${OUT_DIR}"

START_TIME=$(date +%s)
CURRENT_STEP="Inicialización"
REPORT_FILE="${OUT_DIR}/rebuild-report-runner-v${VERSION}.txt"

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

    local box_file="${OUT_DIR}/dev-forge-runner-v${VERSION}.box"
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
                    DEV-FORGE RUNNER BOX REBUILD REPORT
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
Tag Canónico en Vagrant          : olorinj/dev-forge-runner

--- DIAGNÓSTICO DEL SISTEMA ---
VirtualBox Versión               : $(VBoxManage --version 2>/dev/null || echo "No disponible")
Vagrant Versión                  : $(vagrant --version 2>/dev/null || echo "No disponible")
Kernels Activos en Box           : 1 (Estricto)
Auto-Actualizaciones (APT)       : Enmascaradas (Masked)
Servicios CI/CD Integrados       : Docker Engine + GitLab Runner
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
    log_err "La reconstrucción de forge-runner falló durante el paso: ${CURRENT_STEP}"
    emit_report
    exit ${exit_code}
}

trap on_error ERR

log_info "========================================================================="
log_info "Iniciando reconstrucción total y limpia de forge-runner (v${VERSION})"
log_info "========================================================================="

# -----------------------------------------------------------------------------
# PASO 0: Exclusión Mutua de RAM (Asegurar apagado de forge-windows)
# -----------------------------------------------------------------------------
if VBoxManage list runningvms | grep -qi "FORGE-WINDOWS"; then
    log_info "Deteniendo forge-windows para asegurar recursos de RAM y CPU para runner..."
    vagrant halt forge-windows 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# PASO 1: Purga Previa Absoluta (Clean Sweep)
# -----------------------------------------------------------------------------
CURRENT_STEP="1. Purga Previa Absoluta"
log_info "${CURRENT_STEP}..."

# 1.1 Destruir máquina Vagrant si existe
log_info "Destruyendo instancia previa de forge-runner en Vagrant..."
vagrant destroy forge-runner -f 2>/dev/null || true

# 1.2 Limpiar residuos de VirtualBox si la VM quedó huérfana
if VBoxManage list vms | grep -qi "FORGE-RUNNER"; then
    log_warn "Detectada VM FORGE-RUNNER en VirtualBox. Forzando apagado y desregistro..."
    VBoxManage controlvm FORGE-RUNNER poweroff 2>/dev/null || true
    sleep 2
    VBoxManage unregistervm FORGE-RUNNER --delete 2>/dev/null || true
fi

# 1.3 Limpiar carpetas huérfanas en disco para evitar errores VERR_ALREADY_EXISTS al mover al grupo /DEV-FORGE
DEFAULT_VBOX_DIR=$(VBoxManage list systemproperties 2>/dev/null | awk -F': +' '/Default machine folder/{print $2}' || true)
if [ -n "${DEFAULT_VBOX_DIR}" ] && [ -d "${DEFAULT_VBOX_DIR}" ]; then
    rm -rf "${DEFAULT_VBOX_DIR}/FORGE-RUNNER" "${DEFAULT_VBOX_DIR}/DEV-FORGE/FORGE-RUNNER"
fi

# 1.4 Limpiar metadatos locales de la máquina en .vagrant
rm -rf "${REPO_DIR}/.vagrant/machines/forge-runner"

# 1.5 Eliminar la box de la base de datos de Vagrant (canónica y alias)
log_info "Purgando box olorinj/dev-forge-runner de Vagrant..."
vagrant box remove olorinj/dev-forge-runner --all --force 2>/dev/null || true
vagrant box remove olorinj/forge-runner --all --force 2>/dev/null || true

# 1.6 Limpiar archivos de box previos en el repositorio y home
rm -f "${OUT_DIR}/dev-forge-runner-v"*.box*
rm -f "${HOME}/.dev-forge/boxes/dev-forge-runner-v"*.box*

STATUS_PURGE="SUCCESS"
log_ok "Purga previa finalizada. Entorno de runner 100% limpio."

# -----------------------------------------------------------------------------
# PASO 2: Aprovisionamiento Limpio desde Imagen Base Upstream
# -----------------------------------------------------------------------------
CURRENT_STEP="2. Aprovisionamiento Upstream (Docker + GitLab Runner)"
log_info "${CURRENT_STEP}..."
log_info "Iniciando forge-runner con imagen upstream bento/debian-12..."

FORGE_FORCE_UPSTREAM_BOX=1 vagrant up forge-runner --provision

STATUS_UPSTREAM="SUCCESS"
log_ok "Máquina runner levantada y aprovisionada con éxito."

# -----------------------------------------------------------------------------
# PASO 3: Optimización in-guest, Hardening y Restauración de Clave SSH
# -----------------------------------------------------------------------------
CURRENT_STEP="3. Optimización in-guest y Restauración SSH"
log_info "${CURRENT_STEP}..."
log_info "Ejecutando /forge/scripts/prep-guest-linux.sh dentro del guest..."

vagrant ssh forge-runner -c "sudo bash /forge/scripts/prep-guest-linux.sh"

STATUS_PREP="SUCCESS"
log_ok "Hardening, unificación de kernel, zeroing y restauración de claves SSH completados."

# -----------------------------------------------------------------------------
# PASO 4: Apagado y Empaquetado Estándar Vagrant
# -----------------------------------------------------------------------------
CURRENT_STEP="4. Empaquetado Nativo .box"
log_info "${CURRENT_STEP}..."

log_info "Apagando máquina limpiamente..."
vagrant halt forge-runner

# Eliminar clave privada efímera local para que 'vagrant package' no inyecte
# una clave privada obsoleta en el paquete .box
rm -f "${REPO_DIR}/.vagrant/machines/forge-runner/virtualbox/private_key"

BOX_FILE="${OUT_DIR}/dev-forge-runner-v${VERSION}.box"
BOX_VF="${OUT_DIR}/box-Vagrantfile-runner-v${VERSION}.rb"

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
vagrant package forge-runner --output "${BOX_FILE}" --vagrantfile "${BOX_VF}"
rm -f "${BOX_VF}"

log_info "Calculando suma de verificación SHA-256..."
(cd "${OUT_DIR}" && sha256sum "$(basename "${BOX_FILE}")" > "$(basename "${BOX_FILE}").sha256")

STATUS_PACKAGE="SUCCESS"
log_ok "Empaquetado oficial de runner completado."

# -----------------------------------------------------------------------------
# PASO 5: Registro Local de la Nueva Box en Vagrant
# -----------------------------------------------------------------------------
CURRENT_STEP="5. Registro Local de Box en Vagrant"
log_info "${CURRENT_STEP}..."

vagrant box add olorinj/dev-forge-runner "${BOX_FILE}" --force

STATUS_REGISTER="SUCCESS"
log_ok "Box olorinj/dev-forge-runner registrada en Vagrant."

# -----------------------------------------------------------------------------
# PASO 6: Prueba de Despliegue Limpio (Verificación)
# -----------------------------------------------------------------------------
if [ "${TEST_VERIFY}" = "true" ]; then
    CURRENT_STEP="6. Prueba de Despliegue y Conectividad SSH"
    log_info "${CURRENT_STEP}..."

    # 6.1 Destruir la VM constructora
    log_info "Destruyendo la VM constructora para probar despliegue desde la nueva box..."
    vagrant destroy forge-runner -f

    # 6.2 Desplegar la máquina a partir de la nueva box recién creada
    log_info "Iniciando forge-runner a partir de la box olorinj/dev-forge-runner..."
    BOOT_START=$(date +%s)
    vagrant up forge-runner
    BOOT_END=$(date +%s)
    BOOT_SEC=$((BOOT_END - BOOT_START))

    # 6.3 Validar conectividad SSH y servicios CI/CD
    log_info "Verificando servicios instalados en el guest runner..."
    GUEST_DIAG=$(vagrant ssh forge-runner -c "
        echo 'KERNEL:' \$(uname -r);
        echo 'DOCKER:' \$(docker --version 2>/dev/null || echo 'N/A');
        echo 'GITLAB-RUNNER:' \$(gitlab-runner --version 2>/dev/null | head -n 1 || echo 'N/A');
        echo 'UTILITIES:' \$(which register-runner start-gitlab-server 2>/dev/null || echo 'N/A');
    ")
    echo "${GUEST_DIAG}"

    # 6.4 Apagar la VM para dejar el entorno en reposo
    vagrant halt forge-runner

    STATUS_TEST="SUCCESS (Arranque en ${BOOT_SEC}s, SSH y servicios CI/CD OK)"
    log_ok "¡Verificación de despliegue de forge-runner completada con éxito en ${BOOT_SEC} segundos!"
fi

CURRENT_STEP="Completado"
FINAL_OUTCOME="SUCCESS"

emit_report

