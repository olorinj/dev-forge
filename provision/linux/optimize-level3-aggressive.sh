#!/usr/bin/env bash
# =============================================================================
# dev-forge : Optimization Level 3 (Aggressive) for Debian 12
# Scope: Level 2 + C-States 0 (Wake Latency), Transparent Huge Pages Off,
#        Kernel Scheduler Latency Tuning, limits.conf
# =============================================================================
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Este script requiere privilegios de root." >&2
  exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/build-vm-optimize.log"

log() {
  local level="${2:-INFO}"
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $1"
  echo "$msg" | tee -a "$LOG_FILE"
}

if [ -f "$DIR/optimize-level2-recommended.sh" ]; then
  bash "$DIR/optimize-level2-recommended.sh" "$@"
fi

if [ "$1" = "--rollback" ]; then
  log "Iniciando Rollback de Nivel 3 (Agresivo)..." "WARN"
  rm -f /etc/sysctl.d/98-build-level3.conf /etc/security/limits.d/99-build-limits.conf /etc/systemd/system/disable-thp.service
  systemctl daemon-reload
  sysctl --system >/dev/null 2>&1 || true
  log "Rollback de Nivel 3 completado." "SUCCESS"
  exit 0
fi

log "=== INICIANDO OPTIMIZACIÓN NIVEL 3 (AGRESIVO) ==="

# 1. Desactivar C-States profundos para latencia de wake cero
log "Desactivando estados de bajo consumo C-States en procesador..."
for state in /sys/devices/system/cpu/cpu*/cpuidle/state[1-9]/disable; do
  if [ -f "$state" ]; then
    echo 1 > "$state" 2>/dev/null || true
  fi
done

# 2. Desactivar Transparent Huge Pages (eliminar pausas de compactación de memoria)
log "Desactivando Transparent Huge Pages (THP)..."
echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true

cat << 'EOF' > /etc/systemd/system/disable-thp.service
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysinit.target local-fs.target
Before=basic.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled && echo never > /sys/kernel/mm/transparent_hugepage/defrag'

[Install]
WantedBy=basic.target
EOF
systemctl daemon-reload
systemctl enable disable-thp.service 2>/dev/null || true

# 3. Tuning de latencia del planificador CFS/EEVDF
log "Ajustando granularidad de scheduling para hilos de compilación..."
cat << 'EOF' > /etc/sysctl.d/98-build-level3.conf
kernel.sched_min_granularity_ns = 10000000
kernel.sched_wakeup_granularity_ns = 5000000
EOF
sysctl --system >/dev/null 2>&1 || true

# 4. Descriptores y límites de procesos en limits.conf
log "Configurando límites máximos de descriptores de archivos para compilación..."
cat << 'EOF' > /etc/security/limits.d/99-build-limits.conf
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65536
* hard nproc 65536
root soft nofile 1048576
root hard nofile 1048576
EOF

log "=== OPTIMIZACIÓN NIVEL 3 (AGRESIVO) COMPLETADA CON ÉXITO ===" "SUCCESS"
