#!/usr/bin/env bash
# =============================================================================
# dev-forge : Script de Empaquetado de Custom Boxes VDI de Despliegue Instantáneo
# =============================================================================
# Orquesta la optimización in-guest, apagado, exportación a OVF, conversión y
# compactación del disco virtual a formato VDI nativo, y empaquetado final a .box
# con verificación de espacio libre y cálculo de suma SHA-256.
# =============================================================================
set -euo pipefail

COLOR_CYAN="\033[1;36m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_RESET="\033[0m"

log_info() { echo -e "${COLOR_CYAN}[dev-forge-box]${COLOR_RESET} $1"; }
log_ok()   { echo -e "${COLOR_GREEN}[dev-forge-box : OK]${COLOR_RESET} $1"; }
log_warn() { echo -e "${COLOR_YELLOW}[dev-forge-box : AVISO]${COLOR_RESET} $1"; }
log_err()  { echo -e "${COLOR_RED}[dev-forge-box : ERROR]${COLOR_RESET} $1" >&2; }

TARGET_MACHINE="${1:-all}"
VERSION="${2:-1.0.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# -----------------------------------------------------------------------------
# 1. Detección Inteligente de la Partición con Mayor Espacio Libre
# -----------------------------------------------------------------------------
# Se evalúa el espacio disponible en /home y en el directorio del repositorio
# para evitar saturar particiones llenas (como /mnt/data).
HOME_FREE_KB=$(df -k "${HOME}" | awk 'NR==2 {print $4}')
REPO_FREE_KB=$(df -k "${REPO_DIR}" | awk 'NR==2 {print $4}')

if [ "${HOME_FREE_KB}" -ge "${REPO_FREE_KB}" ]; then
    BASE_STORAGE="${HOME}/.dev-forge/boxes"
else
    BASE_STORAGE="${REPO_DIR}/dist/boxes"
fi

OUT_DIR="${3:-${BASE_STORAGE}}"
mkdir -p "${OUT_DIR}"

AVAILABLE_GB=$(df -BG "${OUT_DIR}" | awk 'NR==2 {print $4}' | tr -d 'G')
log_info "Destino de empaquetado seleccionado: ${OUT_DIR}"
log_info "Espacio disponible en la partición: ${AVAILABLE_GB} GB"

if [ "${AVAILABLE_GB}" -lt 15 ]; then
    log_err "Espacio en disco insuficiente (${AVAILABLE_GB} GB disponibles). Se requieren al menos 15 GB libres."
    exit 1
fi

# -----------------------------------------------------------------------------
# 2. Función de Empaquetado por Máquina Virtual
# -----------------------------------------------------------------------------
package_single_machine() {
    local machine="$1"
    local vbox_name=""

    case "$machine" in
        forge-linux)
            vbox_name="FORGE-LINUX"
            ;;
        forge-windows)
            vbox_name="FORGE-WINDOWS"
            ;;
        forge-runner)
            vbox_name="FORGE-RUNNER"
            ;;
        *)
            log_err "Máquina desconocida: $machine. Opciones: forge-linux, forge-windows, forge-runner"
            return 1
            ;;
    esac

    echo ""
    log_info "========================================================================="
    log_info "Iniciando empaquetado VDI para: ${machine} (${vbox_name}) v${VERSION}"
    log_info "========================================================================="

    # 1. Asegurar que la VM esté arriba para ejecutar el script de preparación in-guest
    log_info "Verificando estado de ${machine}..."
    cd "${REPO_DIR}"
    
    # Iniciar la VM si no está corriendo
    if ! VBoxManage list runningvms | grep -q "${vbox_name}"; then
        log_info "Levantando ${machine} para aplicar optimización y poda..."
        vagrant up "${machine}"
    fi

    # 2. Ejecutar script de preparación in-guest
    log_info "Ejecutando script de preparación y hardening in-guest..."
    if [ "$machine" = "forge-windows" ]; then
        vagrant winrm "${machine}" -s powershell -c "powershell.exe -ExecutionPolicy Bypass -NoProfile -File C:\\forge\\scripts\\prep-guest-windows.ps1"
    else
        vagrant ssh "${machine}" -c "sudo bash /forge/scripts/prep-guest-linux.sh"
    fi

    # 3. Apagado limpio y ordenado de la VM
    log_info "Apagando limpiamente ${machine}..."
    vagrant halt "${machine}"

    # 4. Crear directorio temporal en la partición con espacio
    local tmp_export
    tmp_export=$(mktemp -d "${OUT_DIR}/tmp-export-${machine}-XXXXXX")
    trap 'rm -rf "${tmp_export}"' EXIT

    log_info "Exportando appliance OVF inicial desde VirtualBox..."
    VBoxManage export "${vbox_name}" --output "${tmp_export}/box.ovf"

    # 5. Localizar el disco virtual exportado
    local src_disk
    src_disk=$(find "${tmp_export}" -maxdepth 1 -name "*.vmdk" | head -n 1)

    if [ -z "${src_disk}" ]; then
        log_err "No se encontró el disco VMDK exportado en ${tmp_export}."
        return 1
    fi

    local vdi_disk="${tmp_export}/box-disk001.vdi"
    log_info "Convirtiendo disco exportado a formato nativo VDI..."
    VBoxManage clonemedium disk "${src_disk}" "${vdi_disk}" --format VDI

    log_info "Compactando disco VDI para eliminar bloques vacíos..."
    VBoxManage modifymedium disk "${vdi_disk}" --compact

    # Eliminar el VMDK original para liberar gigabytes inmediatamente
    rm -f "${src_disk}"
    # Desregistrar el VDI temporal del registro global de VirtualBox para evitar UUID leaks
    VBoxManage closemedium disk "${vdi_disk}" 2>/dev/null || true

    # 6. Actualizar descriptor box.ovf para referenciar el disco VDI
    # NOTA: En el estándar OVF de VirtualBox CLI, el atributo ovf:format DEBE mantenerse
    # como el estándar OVF para que el parser de VBoxManage import acepte el archivo.
    # VirtualBox detecta y monta el disco VDI nativamente por la extensión del archivo .vdi.
    log_info "Actualizando descriptor box.ovf con el disco VDI..."
    local vmdk_name
    vmdk_name=$(basename "${src_disk}")
    local vdi_name="box-disk001.vdi"

    sed -i "s|${vmdk_name}|${vdi_name}|g" "${tmp_export}/box.ovf"

    # 7. Crear metadata.json de Vagrant
    cat << 'EOF' > "${tmp_export}/metadata.json"
{
  "provider": "virtualbox"
}
EOF

    # 8. Crear Vagrantfile embebido mínimo de la box
    cat << 'EOF' > "${tmp_export}/Vagrantfile"
Vagrant.configure("2") do |config|
  config.vm.provider "virtualbox" do |vb|
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.customize ["modifyvm", :id, "--audio", "none"]
    vb.customize ["modifyvm", :id, "--groups", "/DEV-FORGE"]
  end
end
EOF

    # 9. Empaquetar el archivo .box final (tar.gz)
    local box_filename="dev-forge-${machine}-v${VERSION}.box"
    local box_filepath="${OUT_DIR}/${box_filename}"
    log_info "Comprimiendo y generando ${box_filepath}..."

    (cd "${tmp_export}" && tar -czf "${box_filepath}" ./box.ovf ./${vdi_name} ./metadata.json ./Vagrantfile)

    # 10. Calcular SHA-256 del artefacto
    log_info "Calculando suma de verificación SHA-256..."
    (cd "${OUT_DIR}" && sha256sum "${box_filename}" > "${box_filename}.sha256")

    # Limpiar directorio temporal
    rm -rf "${tmp_export}"
    trap - EXIT

    local box_size
    box_size=$(du -h "${box_filepath}" | awk '{print $1}')
    local sha256_val
    sha256_val=$(awk '{print $1}' "${box_filepath}.sha256")

    local canonical_tag="olorinj/dev-${machine}"
    if [[ "${machine}" == dev-* ]]; then
        canonical_tag="olorinj/${machine}"
    fi

    echo ""
    log_ok "========================================================================="
    log_ok "✔ Box generada exitosamente: ${box_filepath} (${box_size})"
    log_ok "  SHA-256: ${sha256_val}"
    log_ok "========================================================================="
    echo ""
    echo -e "${COLOR_CYAN}Comandos para probar la box en local inmediatamente:${COLOR_RESET}"
    echo "  vagrant box add ${canonical_tag} ${box_filepath} --force"
    echo ""
    echo -e "${COLOR_CYAN}Comando para publicar en Vagrant Cloud (Open Source):${COLOR_RESET}"
    echo "  vagrant cloud publish ${canonical_tag} ${VERSION} virtualbox ${box_filepath}"
    echo ""
}

# -----------------------------------------------------------------------------
# 3. Flujo Principal
# -----------------------------------------------------------------------------
case "${TARGET_MACHINE}" in
    forge-linux|linux)
        package_single_machine "forge-linux"
        ;;
    forge-windows|windows)
        package_single_machine "forge-windows"
        ;;
    forge-runner|runner)
        package_single_machine "forge-runner"
        ;;
    all)
        log_info "Empaquetando todas las máquinas virtuales secuencialmente..."
        package_single_machine "forge-linux"
        package_single_machine "forge-windows"
        package_single_machine "forge-runner"
        ;;
    *)
        log_err "Opción no válida: ${TARGET_MACHINE}"
        echo "Uso: $0 [forge-linux|forge-windows|forge-runner|all] [version] [out_dir]"
        exit 1
        ;;
esac

