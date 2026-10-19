#!/usr/bin/env bash
# =============================================================================
# dev-forge : Health-Check & Validation Suite for Debian 12 Build Node
# =============================================================================
set -e
export PATH="$PATH:/sbin:/usr/sbin"

LOG_FILE="/var/log/build-vm-health.log"
echo "=== [dev-forge] Health-Check Report $(date '+%Y-%m-%d %H:%M:%S') ===" | tee "$LOG_FILE"

PASS=0
FAIL=0

check() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd"; then
    echo -e " \033[32m✔ PASS\033[0m : $name" | tee -a "$LOG_FILE"
    PASS=$((PASS + 1))
  else
    echo -e " \033[31m✘ FAIL\033[0m : $name" | tee -a "$LOG_FILE"
    FAIL=$((FAIL + 1))
  fi
}

echo "1. Verificando Servicios Críticos..."
check "OpenSSH Server activo" "systemctl is-active --quiet ssh || systemctl is-active --quiet sshd"
check "Avahi deshabilitado/enmascarado" "! systemctl is-active --quiet avahi-daemon"
check "Cups deshabilitado/enmascarado" "! systemctl is-active --quiet cups"
check "Bluetooth deshabilitado/enmascarado" "! systemctl is-active --quiet bluetooth"

echo ""
echo "2. Verificando Parámetros del Kernel..."
check "swappiness <= 10" "[ $(sysctl -n vm.swappiness) -le 10 ]"
check "vfs_cache_pressure <= 50" "[ $(sysctl -n vm.vfs_cache_pressure) -le 50 ]"
check "pid_max >= 4194304" "[ $(sysctl -n kernel.pid_max) -ge 4194304 ]"

echo ""
echo "3. Verificando Almacenamiento y Caches..."
check "tmpfs montado en /tmp" "mountpoint -q /tmp"
check "Swap configurado" "[ $(free -m | awk '/Swap:/ {print $2}') -gt 1000 ]"
check "Directorio ccache accesible" "[ -d /var/cache/ccache ]"
check "Directorio sccache accesible" "[ -d /var/cache/sccache ]"

echo ""
echo "4. Verificando Variables de Entorno de Build..."
check "build-env.sh presente en /etc/profile.d/" "[ -f /etc/profile.d/build-env.sh ]"

echo ""
echo "=========================================================="
echo " RESUMEN HEALTH-CHECK: Superados: $PASS | Fallidos: $FAIL"
echo " Reporte guardado en $LOG_FILE"
echo "=========================================================="

[ "$FAIL" -eq 0 ]
