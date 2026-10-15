#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== [dev-forge : Linux] 40-node: Instalando Node.js (v20 LTS) y gestores de paquetes ==="

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
fi

# Habilitar corepack para soporte nativo de pnpm y yarn sin sudo
corepack enable 2>/dev/null || true
corepack prepare pnpm@latest --activate 2>/dev/null || true

echo "=== [dev-forge : Linux] 40-node: Node.js $(node -v) y npm $(npm -v) listos ==="
