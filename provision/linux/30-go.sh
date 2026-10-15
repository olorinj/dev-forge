#!/usr/bin/env bash
set -e

echo "=== [dev-forge : Linux] 30-go: Instalando Go Toolchain ==="

GO_VERSION="1.23.2"
ARCH="amd64"

if ! command -v go >/dev/null 2>&1 || [[ "$(go version)" != *"$GO_VERSION"* ]]; then
  echo "Descargando Go $GO_VERSION..."
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" -o /tmp/go.tar.gz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tar.gz
  rm -f /tmp/go.tar.gz
fi

# Exportar variables de entorno de Go globalmente
cat << 'EOF' > /etc/profile.d/golang.sh
export GOROOT="/usr/local/go"
export GOPATH="/home/vagrant/go"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"
EOF
chmod +x /etc/profile.d/golang.sh

ln -sf /usr/local/go/bin/* /usr/local/bin/ 2>/dev/null || true

echo "=== [dev-forge : Linux] 30-go: Toolchain de Go configurado con éxito ==="

