#!/usr/bin/env bash
# =============================================================================
# dev-forge : Optimization Level 1 (Conservative) for Debian 12
# Scope: Mask Unneeded Services, CPU Performance Governor, Basic sysctl, I/O Scheduler
# =============================================================================
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Este script requiere privilegios de root." >&2
  exit 1
fi

LOG_FILE="/var/log/build-vm-optimize.log"
TODAY=$(date +%Y%m%d)
BACKUP_DIR="/root/backup-optimize-$TODAY"
mkdir -p "$BACKUP_DIR"

log() {
  local level="${2:-INFO}"
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $1"
  echo "$msg" | tee -a "$LOG_FILE"
}

SERVICES_TO_MASK=(
  "avahi-daemon.service"
  "avahi-daemon.socket"
  "bluetooth.service"
  "cups.service"
  "cups.socket"
  "ModemManager.service"
  "thermald.service"
  "unattended-upgrades.service"
  "apt-daily.timer"
  "apt-daily-upgrade.timer"
  "e2scrub_all.timer"
  "fstrim.timer"
  "man-db.timer"
  "colord.service"
  "accounts-daemon.service"
  "udisks2.service"
  "polkit.service"
)

if [ "$1" = "--rollback" ]; then
  log "Iniciando Rollback de Nivel 1 (Conservador)..." "WARN"
  for s in "${SERVICES_TO_MASK[@]}"; do
    systemctl unmask "$s" 2>/dev/null || true
    systemctl enable "$s" 2>/dev/null || true
  done
  rm -f /etc/sysctl.d/90-build-level1.conf
  sysctl --system >/dev/null 2>&1 || true
  log "Rollback de Nivel 1 completado." "SUCCESS"
  exit 0
fi

log "=== INICIANDO OPTIMIZACIÓN NIVEL 1 (CONSERVADOR) ==="

# 1. Enmascarar servicios innecesarios
log "Enmascarando servicios y timers superfluos para entorno headless..."
for s in "${SERVICES_TO_MASK[@]}"; do
  if systemctl list-unit-files "$s" &>/dev/null; then
    systemctl stop "$s" 2>/dev/null || true
    systemctl mask "$s" 2>/dev/null || true
    log "  - Enmascarado: $s"
  fi
done

# 2. CPU Governor a Performance
log "Configurando CPU Scaling Governor a 'performance'..."
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
  if [ -f "$gov" ]; then
    echo "performance" > "$gov" 2>/dev/null || true
  fi
done
if command -v cpupower &>/dev/null; then
  cpupower frequency-set -g performance >/dev/null 2>&1 || true
fi

# 3. Sysctl básico para compilación
log "Aplicando configuración de kernel sysctl básica..."
cat << 'EOF' > /etc/sysctl.d/90-build-level1.conf
# Minimizar agresividad de swap
vm.swappiness = 10
# Retener cachés de inodos y directorios para árboles de código fuente
vm.vfs_cache_pressure = 50
EOF
sysctl --system >/dev/null 2>&1 || true

# 4. I/O Scheduler para discos virtuales
log "Ajustando I/O Scheduler y Read-Ahead para SSD/NVMe..."
for dev in /sys/block/sd* /sys/block/vd*; do
  if [ -d "$dev/queue" ]; then
    if grep -q "mq-deadline" "$dev/queue/scheduler" 2>/dev/null; then
      echo "mq-deadline" > "$dev/queue/scheduler" 2>/dev/null || true
    fi
    if [ -f "$dev/queue/read_ahead_kb" ]; then
      echo "2048" > "$dev/queue/read_ahead_kb" 2>/dev/null || true
    fi
  fi
done

log "=== OPTIMIZACIÓN NIVEL 1 (CONSERVADOR) COMPLETADA CON ÉXITO ===" "SUCCESS"
