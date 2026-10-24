#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "=== [dev-forge : Runner] Configurando maquina CI/CD Runner ==="

# 1. 2GB Swapfile para pases de compilacion exigentes en memoria
echo "=== [dev-forge : Runner] 1/5: Verificando archivo Swap (2GB) ==="
if [ ! -f /swapfile ]; then
  echo "Creando /swapfile de 2GB..."
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
else
  if ! swapon --show | grep -q '/swapfile'; then
    echo "Activando /swapfile existente..."
    swapon /swapfile || true
  fi
fi

# 2. Actualizacion del sistema y paquetes base
echo "=== [dev-forge : Runner] 2/5: Instalando paquetes esenciales y Docker ==="
apt-get update
apt-get install -y --no-install-recommends \
  curl ca-certificates gnupg lsb-release git docker.io build-essential pkg-config libssl-dev

# 3. Activacion de Docker y permisos de usuario
echo "=== [dev-forge : Runner] 3/5: Activando servicio Docker ==="
systemctl enable --now docker
usermod -aG docker vagrant

# 4. Instalacion y configuracion de GitLab Runner
echo "=== [dev-forge : Runner] 4/5: Configurando GitLab Runner ==="
if ! command -v gitlab-runner >/dev/null 2>&1; then
  echo "Descargando repositorio e instalando gitlab-runner..."
  curl -L --retry 3 --retry-delay 2 "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash
  apt-get install -y gitlab-runner
fi

usermod -aG docker gitlab-runner || true
systemctl enable --now gitlab-runner || true

# 5. Utilidades auxiliares
echo "=== [dev-forge : Runner] 5/5: Instalando utilidades auxiliares ==="

# Utilidad: /usr/local/bin/register-runner
cat << 'EOF_REG' > /usr/local/bin/register-runner
#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: register-runner <GITLAB_TOKEN> [GITLAB_URL (default: https://gitlab.com)]"
  exit 1
fi

TOKEN="$1"
URL="${2:-https://gitlab.com}"

CMD="gitlab-runner"
if [ "$(id -u)" -ne 0 ]; then
  CMD="sudo gitlab-runner"
fi

$CMD register \
  --non-interactive \
  --url "$URL" \
  --token "$TOKEN" \
  --executor "docker" \
  --docker-image "rust:1.85-slim" \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --description "devforge-bento-debian12-runner" \
  --tag-list "rust,docker,linux"

echo "Runner successfully registered!"
EOF_REG
chmod +x /usr/local/bin/register-runner

# Utilidad: /usr/local/bin/start-gitlab-server (Pruebas offline)
cat << 'EOF_GL' > /usr/local/bin/start-gitlab-server
#!/usr/bin/env bash
set -euo pipefail

DOCKER_CMD="docker"
if [ "$(id -u)" -ne 0 ] && ! groups | grep -q docker; then
  DOCKER_CMD="sudo docker"
fi

$DOCKER_CMD run --detach \
  --hostname localhost \
  --publish 80:80 --publish 443:443 --publish 2222:22 \
  --name gitlab \
  --restart always \
  --volume /srv/gitlab/config:/etc/gitlab \
  --volume /srv/gitlab/logs:/var/log/gitlab \
  --volume /srv/gitlab/data:/var/opt/gitlab \
  --shm-size 256m \
  gitlab/gitlab-ce:latest

echo "GitLab CE starting. Access at http://localhost:8080"
echo "Root initial password: $DOCKER_CMD exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password"
EOF_GL
chmod +x /usr/local/bin/start-gitlab-server

echo "=== [dev-forge : Runner] Aprovisionamiento completado con exito ==="
