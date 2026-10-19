#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== [dev-forge : Linux] 20-python: Instalando Python y herramientas modernas ==="
apt-get install -y --no-install-recommends \
  python3 python3-dev python3-pip python3-venv pipx

# Instalar 'uv' (gestor ultrarrápido de paquetes Python) globalmente
curl -LsSf https://astral.sh/uv/install.sh | sh
cp /root/.cargo/bin/uv /usr/local/bin/ 2>/dev/null || true
cp /root/.cargo/bin/uvx /usr/local/bin/ 2>/dev/null || true
su - vagrant -c 'curl -LsSf https://astral.sh/uv/install.sh | sh' 2>/dev/null || true

# Instalar dependencias para Nuitka (compilación C nativa y standalone)
apt-get install -y --no-install-recommends patchelf ccache

# Instalar Nuitka y PyInstaller vía pipx
pipx install nuitka 2>/dev/null || true
su - vagrant -c 'pipx install nuitka' 2>/dev/null || true
pipx install pyinstaller 2>/dev/null || true
su - vagrant -c 'pipx install pyinstaller' 2>/dev/null || true
pipx ensurepath --global 2>/dev/null || true
ln -sf /root/.local/bin/nuitka* /usr/local/bin/ 2>/dev/null || true
ln -sf /home/vagrant/.local/bin/nuitka* /usr/local/bin/ 2>/dev/null || true

echo "=== [dev-forge : Linux] 20-python: Entorno Python configurado con éxito ==="

