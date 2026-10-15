#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== [dev-forge : Linux] 60-macos-cross: Instalando Docker para compilación cruzada osxcross ==="
apt-get install -y --no-install-recommends docker.io

usermod -aG docker vagrant
systemctl enable --now docker

echo "=== [dev-forge : Linux] 60-macos-cross: Instalando herramientas de empaquetado macOS (dmgbuild, rcodesign) ==="
# dmgbuild para crear imágenes DMG de distribución
pipx install dmgbuild 2>/dev/null || pip3 install --break-system-packages dmgbuild 2>/dev/null || true

# rcodesign (Apple Code Signing & Notarization puro en Rust para firmar y notarizar apps Mac desde Linux)
RCODESIGN_VERSION="0.29.0"
RCODESIGN_TAR="apple-codesign-${RCODESIGN_VERSION}-x86_64-unknown-linux-musl.tar.gz"
RCODESIGN_URL="https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F${RCODESIGN_VERSION}/${RCODESIGN_TAR}"

if ! command -v rcodesign >/dev/null 2>&1; then
  echo "Descargando rcodesign ${RCODESIGN_VERSION}..."
  if curl -fsSL "$RCODESIGN_URL" -o "/tmp/${RCODESIGN_TAR}" 2>/dev/null; then
    tar -C /tmp -xzf "/tmp/${RCODESIGN_TAR}"
    cp /tmp/apple-codesign-${RCODESIGN_VERSION}-x86_64-unknown-linux-musl/rcodesign /usr/local/bin/ 2>/dev/null || true
    chmod +x /usr/local/bin/rcodesign 2>/dev/null || true
    rm -rf "/tmp/${RCODESIGN_TAR}" /tmp/apple-codesign*
  fi
fi

echo "=== [dev-forge : Linux] 60-macos-cross: Entorno de compilación y firma para macOS listo ==="
