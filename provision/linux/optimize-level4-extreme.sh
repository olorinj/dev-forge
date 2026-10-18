#!/usr/bin/env bash
# =============================================================================
# dev-forge : Optimization Level 4 (Extreme) for Debian 12
# Scope: Level 3 + Memory Overcommit Always, Compiler march=native hints
# WARNING: Dedicated strictly to isolated build VMs!
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

if [ -f "$DIR/optimize-level3-aggressive.sh" ]; then
  bash "$DIR/optimize-level3-aggressive.sh" "$@"
fi

if [ "$1" = "--rollback" ]; then
  log "Iniciando Rollback de Nivel 4 (Extremo)..." "WARN"
  rm -f /etc/sysctl.d/99-build-level4.conf
  sysctl --system >/dev/null 2>&1 || true
  log "Rollback de Nivel 4 completado." "SUCCESS"
  exit 0
fi

log "=== INICIANDO OPTIMIZACIÓN NIVEL 4 (EXTREMO) ==="

# 1. Overcommit Memory Mode 1 (Always overcommit)
log "ADVERTENCIA: Configurando overcommit_memory = 1 (Always overcommit)..." "WARN"
cat << 'EOF' > /etc/sysctl.d/99-build-level4.conf
vm.overcommit_memory = 1
vm.overcommit_ratio = 90
EOF
sysctl --system >/dev/null 2>&1 || true

log "=== OPTIMIZACIÓN NIVEL 4 (EXTREMO) COMPLETADA CON ÉXITO ===" "SUCCESS"
