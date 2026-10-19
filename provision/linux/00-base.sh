#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== [dev-forge : Linux] 00-base: Actualizando repositorios ==="
apt-get update

echo "=== [dev-forge : Linux] 00-base: Instalando paquetes esenciales y bibliotecas base ==="
apt-get install -y --no-install-recommends \
  curl wget git cmake ninja-build build-essential pkg-config libssl-dev ca-certificates gnupg \
  dos2unix jq unzip patchelf file rpm libfuse2 fuse3 libfuse3-3 mold clang lld \
  libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev libglib2.0-dev

# Asegurar soporte FUSE para AppImages y carpetas compartidas VirtualBox
modprobe vboxsf 2>/dev/null || true
modprobe fuse 2>/dev/null || true
chmod 666 /dev/fuse 2>/dev/null || true
usermod -aG fuse vagrant 2>/dev/null || true

mkdir -p /vagrant
if ! mountpoint -q /vagrant; then
  mount -t vboxsf -o uid=1000,gid=1000,dmode=775,fmode=775 vagrant /vagrant 2>/dev/null || true
fi

# Configuración dinámica del teclado detectado del host
HOST_KEYBOARD="${1:-es}"
echo "=== [dev-forge : Linux] 00-base: Configurando distribución de teclado a '$HOST_KEYBOARD' ==="
if [ -f /etc/default/keyboard ]; then
  sed -i "s/^XKBLAYOUT=.*/XKBLAYOUT=\"$HOST_KEYBOARD\"/" /etc/default/keyboard 2>/dev/null || true
fi
which localectl >/dev/null 2>&1 && localectl set-x11-keymap "$HOST_KEYBOARD" 2>/dev/null || true
which loadkeys >/dev/null 2>&1 && loadkeys "$HOST_KEYBOARD" 2>/dev/null || true

echo "=== [dev-forge : Linux] 00-base: Paquetes esenciales configurados con éxito ==="

