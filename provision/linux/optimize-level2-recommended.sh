#!/usr/bin/env bash
# =============================================================================
# dev-forge : Optimization Level 2 (Recommended) for Debian 12
# Scope: Level 1 + Swapfile 4GB, tmpfs en /tmp (2GB), Caches ccache/sccache persistentes,
#        Kernel Memory & File Descriptors Tuning, cgroups v2 Build Slice, Build Env Vars
# =============================================================================
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "[ERROR] Este script requiere privilegios de root." >&2
  exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/build-vm-optimize.log"
TODAY=$(date +%Y%m%d)
BACKUP_DIR="/root/backup-optimize-$TODAY"
mkdir -p "$BACKUP_DIR"

log() {
  local level="${2:-INFO}"
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $1"
  echo "$msg" | tee -a "$LOG_FILE"
}

# Ejecutar Nivel 1 primero si existe
if [ -f "$DIR/optimize-level1-conservative.sh" ]; then
  bash "$DIR/optimize-level1-conservative.sh" "$@"
fi

if [ "$1" = "--rollback" ]; then
  log "Iniciando Rollback de Nivel 2 (Recomendado)..." "WARN"
  rm -f /etc/sysctl.d/95-build-level2.conf /etc/profile.d/build-env.sh /etc/systemd/system/build.slice
  sed -i '/tmpfs \/tmp tmpfs/d' /etc/fstab
  systemctl daemon-reload
  sysctl --system >/dev/null 2>&1 || true
  log "Rollback de Nivel 2 completado." "SUCCESS"
  exit 0
fi

log "=== INICIANDO OPTIMIZACIÓN NIVEL 2 (RECOMENDADO) ==="

# 1. Configuración de Swapfile (4 GB) si no existe suficiente swap
SWAP_TOTAL=$(free -m | awk '/Swap:/ {print $2}')
if [ "$SWAP_TOTAL" -lt 3000 ]; then
  log "Creando swapfile fijo de 4 GB para evitar OOM..."
  if [ ! -f /swapfile ]; then
    fallocate -l 4G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=4096 status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile 2>/dev/null || true
    if ! grep -q "/swapfile" /etc/fstab; then
      echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
    log "Swapfile de 4 GB activado y configurado en /etc/fstab."
  fi
fi

# 2. Configurar tmpfs en RAM para /tmp (2 GB)
log "Configurando tmpfs en RAM para /tmp (2 GB)..."
if ! grep -q "tmpfs /tmp tmpfs" /etc/fstab; then
  echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777,size=2G 0 0" >> /etc/fstab
fi
mount -o remount,size=2G /tmp 2>/dev/null || mount /tmp 2>/dev/null || true

# 3. Directorios de caché persistentes en NVMe para ccache y sccache
log "Configurando directorios de caché persistentes en NVMe para ccache y sccache..."
mkdir -p /var/cache/ccache /var/cache/sccache /tmp/cargo-target /opt/go /tmp/go-cache
chown -R 1000:1000 /var/cache/ccache /var/cache/sccache /tmp/cargo-target /opt/go /tmp/go-cache 2>/dev/null || true
chmod 775 /var/cache/ccache /var/cache/sccache /tmp/cargo-target /opt/go /tmp/go-cache

if command -v ccache &>/dev/null; then
  sudo -u vagrant CCACHE_DIR=/var/cache/ccache ccache -M 10G >/dev/null 2>&1 || true
fi

# 4. Kernel Tuning Avanzado: Buffers y Descriptores
log "Aplicando kernel sysctl para gestión de memoria de compilación..."
cat << 'EOF' > /etc/sysctl.d/95-build-level2.conf
# Buffers de páginas sucias para ráfagas de escritura secuencial
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
vm.dirty_expire_centisecs = 1500
vm.dirty_writeback_centisecs = 500

# Capacidad masiva de procesos e hilos para compiladores paralelos
kernel.pid_max = 4194304
kernel.threads-max = 65536
fs.file-max = 2097152
fs.nr_open = 2097152

# Sockets de red y conexiones SSH persistentes
net.core.somaxconn = 4096
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15

# Reducir sobrecarga de scheduling
kernel.sched_autogroup_enabled = 0
kernel.numa_balancing = 0
EOF
sysctl --system >/dev/null 2>&1 || true

# 5. Cgroups v2 Build Slice para aislamiento de recursos
log "Creando cgroup v2 build.slice para compiladores..."
cat << 'EOF' > /etc/systemd/system/build.slice
[Unit]
Description=Build Workload Resource Slice
Before=slices.target

[Slice]
MemoryAccounting=true
CPUAccounting=true
TasksAccounting=true
TasksMax=32768
EOF
systemctl daemon-reload

# 6. Variables de Entorno de Build Globales
log "Configurando variables de entorno globales en /etc/profile.d/build-env.sh..."
cat << 'EOF' > /etc/profile.d/build-env.sh
# Variables de optimización de compilación universal de dev-forge
export TMPDIR=/tmp
export CARGO_TARGET_DIR=/tmp/cargo-target
export CARGO_BUILD_JOBS=2
export CCACHE_DIR=/var/cache/ccache
export SCCACHE_DIR=/var/cache/sccache
export RUSTC_WRAPPER=sccache
export GOPATH=/opt/go
export GOCACHE=/tmp/go-cache
export MAVEN_OPTS="-Xmx3584m -XX:+UseG1GC -Dfile.encoding=UTF-8"
export GRADLE_OPTS="-Xmx3584m -Dorg.gradle.jvmargs=\"-Xmx3584m -XX:+UseG1GC\" -Dorg.gradle.parallel=true"
export GIT_OPTIONAL_LOCKS=0
EOF
chmod +x /etc/profile.d/build-env.sh

log "=== OPTIMIZACIÓN NIVEL 2 (RECOMENDADO) COMPLETADA CON ÉXITO ===" "SUCCESS"
