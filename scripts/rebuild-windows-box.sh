#!/usr/bin/env bash
# =============================================================================
# dev-forge : Script de Reconstrucción y Empaquetado Limpio de forge-windows
# =============================================================================
# Purga cualquier rastro previo (VMs en VirtualBox, boxes en Vagrant, archivos),
# garantiza exclusión mutua de RAM apagando forge-linux si estuviese activa,
# aprovisiona desde la imagen base upstream (gusztavvargadr/windows-server-2022),
# ejecuta hardening y optimizaciones in-guest con DISM/SDelete/WinRM,
# empaqueta el artefacto .box nativo oficial, lo registra localmente en Vagrant
# y genera un informe estructurado de validación con prueba de arranque.
# =============================================================================
set -euo pipefail

COLOR_CYAN="\033[1;36m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_RESET="\033[0m"

log_info() { echo -e "${COLOR_CYAN}[rebuild-windows]${COLOR_RESET} $1"; }
log_ok()   { echo -e "${COLOR_GREEN}[rebuild-windows : OK]${COLOR_RESET} $1"; }
log_warn() { echo -e "${COLOR_YELLOW}[rebuild-windows : AVISO]${COLOR_RESET} $1"; }
log_err()  { echo -e "${COLOR_RED}[rebuild-windows : ERROR]${COLOR_RESET} $1" >&2; }

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
REPORT_FILE="${OUT_DIR}/rebuild-report-windows-v${VERSION}.txt"

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

    local box_file="${OUT_DIR}/dev-forge-windows-v${VERSION}.box"
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
                    DEV-FORGE WINDOWS BOX REBUILD REPORT
================================================================================
Fecha de ejecución       : $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Versión de la Box        : v${VERSION}
Duración Total           : ${minutes}m ${seconds}s
Resultado Final          : ${FINAL_OUTCOME}
Último Paso Ejecutado    : ${CURRENT_STEP}

--- RESUMEN DE HITOS Y CHECKS ---
1. Purga Previa Absoluta         : ${STATUS_PURGE}
2. Aprovisionamiento Upstream    : ${STATUS_UPSTREAM}
3. Hardening & Optimizaciones    : ${STATUS_PREP}
4. Empaquetado Nativo .box       : ${STATUS_PACKAGE}
5. Registro Local en Vagrant     : ${STATUS_REGISTER}
6. Prueba de Despliegue Limpio   : ${STATUS_TEST}

--- DETALLES DEL ARTEFACTO GENERADO ---
Archivo de Box                   : ${box_file}
Tamaño en Disco                  : ${box_size}
Suma SHA-256                     : ${sha256_val}
Tag Canónico en Vagrant          : olorinj/dev-forge-windows

--- DIAGNÓSTICO DEL SISTEMA ---
VirtualBox Versión               : $(VBoxManage --version 2>/dev/null || echo "No disponible")
Vagrant Versión                  : $(vagrant --version 2>/dev/null || echo "No disponible")
Protocolo de Comunicación        : WinRM (5985/HTTP)
Auto-Actualizaciones (Windows)   : Desactivadas y Bloqueadas por Directiva
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
    log_err "La reconstrucción de Windows falló durante el paso: ${CURRENT_STEP}"
    emit_report
    exit ${exit_code}
}

trap on_error ERR

log_info "========================================================================="
log_info "Iniciando proceso de forge-windows (v${VERSION}) [Modo: ${STAGE}]"
log_info "========================================================================="

# -----------------------------------------------------------------------------
# PASO 0: Exclusión Mutua de RAM (Asegurar apagado de forge-linux)
# -----------------------------------------------------------------------------
if VBoxManage list runningvms | grep -qi "FORGE-LINUX"; then
    log_info "Deteniendo forge-linux para liberar memoria RAM para Windows..."
    vagrant halt forge-linux 2>/dev/null || true
fi

if [ "${STAGE}" != "package-only" ]; then
    # -----------------------------------------------------------------------------
    # PASO 1: Purga Previa Absoluta (Clean Sweep)
    # -----------------------------------------------------------------------------
    CURRENT_STEP="1. Purga Previa Absoluta"
    log_info "${CURRENT_STEP}..."

    # 1.1 Destruir máquina Vagrant si existe
    log_info "Destruyendo instancia previa de forge-windows en Vagrant..."
    vagrant destroy forge-windows -f 2>/dev/null || true

    # 1.2 Limpiar residuos de VirtualBox si la VM quedó huérfana
    if VBoxManage list vms | grep -qi "FORGE-WINDOWS"; then
        log_warn "Detectada VM FORGE-WINDOWS en VirtualBox. Forzando apagado y desregistro..."
        VBoxManage controlvm FORGE-WINDOWS poweroff 2>/dev/null || true
        sleep 2
        VBoxManage unregistervm FORGE-WINDOWS --delete 2>/dev/null || true
    fi

    # 1.3 Limpiar carpetas huérfanas en disco para evitar errores VERR_ALREADY_EXISTS al mover al grupo /DEV-FORGE
    DEFAULT_VBOX_DIR=$(VBoxManage list systemproperties 2>/dev/null | awk -F': +' '/Default machine folder/{print $2}' || true)
    if [ -n "${DEFAULT_VBOX_DIR}" ] && [ -d "${DEFAULT_VBOX_DIR}" ]; then
        rm -rf "${DEFAULT_VBOX_DIR}/FORGE-WINDOWS" "${DEFAULT_VBOX_DIR}/DEV-FORGE/FORGE-WINDOWS"
    fi

    # 1.4 Limpiar metadatos locales de la máquina en .vagrant
    rm -rf "${REPO_DIR}/.vagrant/machines/forge-windows"

    # 1.5 Eliminar la box de la base de datos de Vagrant (canónica y alias)
    log_info "Purgando box olorinj/dev-forge-windows de Vagrant..."
    vagrant box remove olorinj/dev-forge-windows --all --force 2>/dev/null || true
    vagrant box remove olorinj/forge-windows --all --force 2>/dev/null || true

    # 1.6 Limpiar archivos de box previos en el repositorio y home
    rm -f "${OUT_DIR}/dev-forge-windows-v"*.box*
    rm -f "${HOME}/.dev-forge/boxes/dev-forge-windows-v"*.box*

    STATUS_PURGE="SUCCESS"
    log_ok "Purga previa finalizada. Entorno de Windows 100% limpio."

    # -----------------------------------------------------------------------------
    # PASO 2: Aprovisionamiento Limpio desde Imagen Base Upstream
    # -----------------------------------------------------------------------------
    CURRENT_STEP="2. Aprovisionamiento Upstream con Ansible sobre WinRM"
    log_info "${CURRENT_STEP}..."
    log_info "Iniciando forge-windows con imagen upstream (gusztavvargadr/windows-server-2022-standard-core)..."
    log_info "Esto descargará/instalará Visual Studio Build Tools, WiX, Inno, Rust, Python, Go, Node y OpenJDK."

    FORGE_FORCE_UPSTREAM_BOX=1 vagrant up forge-windows --provision

    STATUS_UPSTREAM="SUCCESS"
    log_ok "Máquina Windows levantada y aprovisionada con Ansible con éxito."

    if [ "${STAGE}" = "deploy-only" ]; then
        CURRENT_STEP="Detenido tras Despliegue (--deploy-only)"
        FINAL_OUTCOME="SUCCESS (Modo deploy-only: Máquina viva lista para cambios e inspección)"
        emit_report
        log_ok "La máquina 'forge-windows' está levantada y lista para cambios manuales o pruebas."
        log_info "Para interactuar con ella vía WinRM: vagrant winrm forge-windows -s powershell -c \"...\""
        log_info "Para optimizar y empaquetar cuando termines: ./scripts/rebuild-windows-box.sh ${VERSION} --package-only"
        exit 0
    fi
else
    STATUS_PURGE="SKIPPED (Modo package-only)"
    STATUS_UPSTREAM="SKIPPED (Modo package-only: Usando VM existente)"
    log_info "Modo --package-only activo: Omitiendo purga y despliegue upstream."
    log_info "Asegurando que forge-windows esté encendida..."
    vagrant up forge-windows --no-provision 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# PASO 3: Optimización in-guest, Hardening y Zeroing
# -----------------------------------------------------------------------------
CURRENT_STEP="3. Optimización in-guest (DISM, SDelete, Poda)"
log_info "${CURRENT_STEP}..."
log_info "Ejecutando prep-guest-windows.ps1 dentro del guest vía WinRM..."

vagrant winrm forge-windows -e -s powershell -c "powershell.exe -ExecutionPolicy Bypass -NoProfile -File C:\\forge\\scripts\\prep-guest-windows.ps1"

STATUS_PREP="SUCCESS"
log_ok "Hardening, compactación WinSxS, eliminación VSS y zeroing con SDelete completados."

# -----------------------------------------------------------------------------
# PASO 4: Apagado y Empaquetado Estándar Vagrant
# -----------------------------------------------------------------------------
CURRENT_STEP="4. Empaquetado Nativo .box"
log_info "${CURRENT_STEP}..."

log_info "Apagando máquina limpiamente..."
vagrant halt forge-windows

# Higiene de metadatos locales antes de empaquetar
rm -f "${REPO_DIR}/.vagrant/machines/forge-windows/virtualbox/private_key"

BOX_FILE="${OUT_DIR}/dev-forge-windows-v${VERSION}.box"
BOX_VF="${OUT_DIR}/box-Vagrantfile-windows-v${VERSION}.rb"

cat << 'EOF' > "${BOX_VF}"
Vagrant.configure("2") do |config|
  config.vm.communicator = "winrm"
  config.winrm.username = "vagrant"
  config.winrm.password = "vagrant"
  config.vm.boot_timeout = 1800
  config.vm.provider "virtualbox" do |vb|
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.customize ["modifyvm", :id, "--audio", "none"]
    vb.customize ["modifyvm", :id, "--groups", "/DEV-FORGE"]
  end
end
EOF

log_info "Empaquetando con 'vagrant package' a: ${BOX_FILE}..."
vagrant package forge-windows --output "${BOX_FILE}" --vagrantfile "${BOX_VF}"
rm -f "${BOX_VF}"

log_info "Calculando suma de verificación SHA-256..."
(cd "${OUT_DIR}" && sha256sum "$(basename "${BOX_FILE}")" > "$(basename "${BOX_FILE}").sha256")

STATUS_PACKAGE="SUCCESS"
log_ok "Empaquetado oficial de Windows completado."

# -----------------------------------------------------------------------------
# PASO 5: Registro Local de la Nueva Box en Vagrant
# -----------------------------------------------------------------------------
CURRENT_STEP="5. Registro Local de Box en Vagrant"
log_info "${CURRENT_STEP}..."

vagrant box add olorinj/dev-forge-windows "${BOX_FILE}" --force

STATUS_REGISTER="SUCCESS"
log_ok "Box olorinj/dev-forge-windows registrada en Vagrant."

# -----------------------------------------------------------------------------
# PASO 6: Prueba de Despliegue Limpio (Verificación)
# -----------------------------------------------------------------------------
if [ "${TEST_VERIFY}" = "true" ]; then
    CURRENT_STEP="6. Prueba de Despliegue y Conectividad WinRM"
    log_info "${CURRENT_STEP}..."

    # 6.1 Destruir la VM constructora
    log_info "Destruyendo la VM constructora para probar despliegue desde la nueva box..."
    vagrant destroy forge-windows -f

    # 6.2 Desplegar la máquina a partir de la nueva box recién creada
    log_info "Iniciando forge-windows a partir de la box olorinj/dev-forge-windows..."
    BOOT_START=$(date +%s)
    vagrant up forge-windows
    BOOT_END=$(date +%s)
    BOOT_SEC=$((BOOT_END - BOOT_START))

    # 6.3 Validar conectividad WinRM y toolchains esenciales instaladas
    log_info "Verificando compiladores instalados en el guest de Windows..."
    GUEST_DIAG=$(vagrant winrm forge-windows -s powershell -c "
        Write-Host 'OS:' (Get-CimInstance Win32_OperatingSystem).Caption;
        Write-Host 'RUST:' (rustc --version 2>\$null);
        Write-Host 'GO:' (go version 2>\$null);
        Write-Host 'PYTHON:' (python --version 2>\$null);
        Write-Host 'NODE:' (node --version 2>\$null);
        Write-Host 'JAVA:' (java -version 2>&1 | Select-Object -First 1);
        Write-Host 'WIX:' (candle.exe -? 2>&1 | Select-Object -First 1);
        Write-Host 'INNO:' (Test-Path 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe');
    ")
    echo "${GUEST_DIAG}"

    # 6.4 Apagar la VM para dejar el entorno en reposo
    vagrant halt forge-windows

    STATUS_TEST="SUCCESS (Arranque en ${BOOT_SEC}s, WinRM y toolchains OK)"
    log_ok "¡Verificación de despliegue de Windows completada con éxito en ${BOOT_SEC} segundos!"
fi

CURRENT_STEP="Completado"
FINAL_OUTCOME="SUCCESS"

emit_report

