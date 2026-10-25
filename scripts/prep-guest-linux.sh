#!/usr/bin/env bash
# =============================================================================
# dev-forge : Script de Preparación y Optimización del Guest Linux
# =============================================================================
# Aplica hardening, poda de servicios innecesarios, bloqueo permanente de
# actualizaciones automáticas, purga de kernels obsoletos (solo 1 kernel activo)
# y llenado con ceros para máxima compactación del disco virtual VDI.
# =============================================================================
set -euo pipefail

COLOR_CYAN="\033[1;36m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RESET="\033[0m"

log_info() { echo -e "${COLOR_CYAN}[dev-forge-prep]${COLOR_RESET} $1"; }
log_ok()   { echo -e "${COLOR_GREEN}[dev-forge-prep : OK]${COLOR_RESET} $1"; }
log_warn() { echo -e "${COLOR_YELLOW}[dev-forge-prep : AVISO]${COLOR_RESET} $1"; }

if [ "$(id -u)" -ne 0 ]; then
    echo "Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

log_info "Iniciando optimización del guest Linux para empaquetado VDI..."

# -----------------------------------------------------------------------------
# 1. Bloqueo Absoluto y Permanente de Actualizaciones Automáticas
# -----------------------------------------------------------------------------
log_info "1/6 Deshabilitando y enmascarando actualizaciones automáticas (APT)..."

# Detener, deshabilitar y enmascarar timers y servicios de APT/Unattended
systemctl stop unattended-upgrades.service apt-daily.timer apt-daily.service apt-daily-upgrade.timer apt-daily-upgrade.service 2>/dev/null || true
systemctl disable unattended-upgrades.service apt-daily.timer apt-daily.service apt-daily-upgrade.timer apt-daily-upgrade.service 2>/dev/null || true
systemctl mask unattended-upgrades.service apt-daily.timer apt-daily.service apt-daily-upgrade.timer apt-daily-upgrade.service 2>/dev/null || true

# Configuración estricta en APT para no buscar ni descargar actualizaciones automáticamente
mkdir -p /etc/apt/apt.conf.d
cat << 'EOF' > /etc/apt/apt.conf.d/99devforge-no-periodic-updates
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Download-Upgradeable-Packages "0";
APT::Periodic::AutocleanInterval "0";
APT::Periodic::Unattended-Upgrade "0";
APT::Periodic::Enable "0";
EOF

log_ok "Actualizaciones automáticas desactivadas de forma permanente."

# -----------------------------------------------------------------------------
# 2. Garantía de un Único Núcleo de Kernel Activo (Purga de obsoletos)
# -----------------------------------------------------------------------------
CURRENT_KERNEL="$(uname -r)"
log_info "2/6 Verificando kernels instalados. Kernel en ejecución: ${CURRENT_KERNEL}..."

# Obtener lista de paquetes de kernel antiguos que no coincidan con el actual
OLD_KERNELS=$(dpkg -l 'linux-image-[0-9]*' 'linux-headers-[0-9]*' 2>/dev/null | awk '/^ii/{print $2}' | grep -v "${CURRENT_KERNEL}" || true)

if [ -n "${OLD_KERNELS}" ]; then
    log_info "Purgando paquetes de kernel obsoletos: ${OLD_KERNELS}"
    # shellcheck disable=SC2086
    apt-get purge -y ${OLD_KERNELS}
else
    log_ok "No se detectaron kernels secundarios obsoletos."
fi

# Regenerar cargador de arranque con el único kernel activo
log_info "Regenerando initramfs y GRUB para consolidar kernel único..."
update-initramfs -u -k "${CURRENT_KERNEL}" 2>/dev/null || true
update-grub 2>/dev/null || true
log_ok "Cargador de arranque consolidado exclusivamente con el kernel ${CURRENT_KERNEL}."

# -----------------------------------------------------------------------------
# 3. Poda de Servicios Innecesarios para una VM de Compilación
# -----------------------------------------------------------------------------
log_info "3/6 Deshabilitando servicios no aplicables a compilación..."

UNNEEDED_SERVICES=(
    "bluetooth.service"
    "cups.service"
    "cups-browsed.service"
    "avahi-daemon.service"
    "modemmanager.service"
    "whoopsie.service"
    "apport.service"
    "systemd-timesyncd.service"
)

for srv in "${UNNEEDED_SERVICES[@]}"; do
    if systemctl list-unit-files "$srv" >/dev/null 2>&1; then
        systemctl stop "$srv" 2>/dev/null || true
        systemctl disable "$srv" 2>/dev/null || true
        systemctl mask "$srv" 2>/dev/null || true
    fi
done

# Enmascarar objetivos de suspensión e hibernación para evitar suspensiones involuntarias
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
log_ok "Servicios innecesarios y estados de suspensión deshabilitados."

# -----------------------------------------------------------------------------
# 4. Limpieza de Cachés y Paquetes Huérfanos
# -----------------------------------------------------------------------------
log_info "4/6 Purgando cachés de paquetes y temporales..."
apt-get autoremove --purge -y 2>/dev/null || true
apt-get clean 2>/dev/null || true

# Reducir logs del journal de systemd
journalctl --vacuum-time=1d 2>/dev/null || true

# Limpiar temporales
rm -rf /tmp/* /var/tmp/* /var/cache/apt/archives/*.deb /var/cache/apt/*.bin 2>/dev/null || true
mkdir -p /tmp /var/tmp
chmod 1777 /tmp /var/tmp

log_ok "Cachés de paquetes y temporales purgados."

# -----------------------------------------------------------------------------
# 5. Higiene de Red y SSH para Empaquetado
# -----------------------------------------------------------------------------
log_info "5/6 Normalizando reglas de red e historiales..."
# Eliminar reglas persistentes de red para que udev genere eth0/enp0s3 limpio
rm -f /etc/udev/rules.d/70-persistent-net.rules 2>/dev/null || true
rm -f /lib/udev/rules.d/75-persistent-net-generator.rules 2>/dev/null || true

# Limpiar clave de máquina SSH temporal (se conservan claves del usuario vagrant)
find /var/log -type f -exec truncate -s 0 {} + 2>/dev/null || true
history -c 2>/dev/null || true

# -----------------------------------------------------------------------------
# 6. Rellenado de Ceros en Espacio Libre (Zeroing para Compactación VDI)
# -----------------------------------------------------------------------------
log_info "6/6 Rellenando con ceros los sectores libres de disco para compactación VDI..."
# Este paso permite que VBoxManage modifymedium --compact reduzca el archivo VDI al mínimo físico posible
dd if=/dev/zero of=/EMPTY bs=1M status=progress 2>/dev/null || true
sync
rm -f /EMPTY
sync

log_ok "¡Optimización del guest finalizada con éxito! Listo para apagado y empaquetado."

