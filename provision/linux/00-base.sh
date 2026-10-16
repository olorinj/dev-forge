#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== [dev-forge : Linux] 00-base: Actualizando repositorios ==="
apt-get update

echo "=== [dev-forge : Linux] 00-base: Instalando paquetes esenciales y bibliotecas base ==="
apt-get install -y --no-install-recommends \
  curl wget git build-essential pkg-config libssl-dev ca-certificates gnupg \
  dos2unix jq unzip patchelf file rpm libfuse2 mold clang lld \
  libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev

# Asegurar soporte y permisos de carpetas compartidas VirtualBox
modprobe vboxsf 2>/dev/null || true
mkdir -p /vagrant
if ! mountpoint -q /vagrant; then
  mount -t vboxsf -o uid=1000,gid=1000,dmode=775,fmode=775 vagrant /vagrant 2>/dev/null || true
fi

echo "=== [dev-forge : Linux] 00-base: Paquetes esenciales configurados con éxito ==="

