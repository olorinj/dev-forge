#!/usr/bin/env bash
set -e

echo "=== [dev-forge : Linux] 10-rust: Instalando Toolchain de Rust ==="

# Instalar rustup tanto para root como para el usuario vagrant
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile default
  su - vagrant -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile default'
fi

# Añadir targets habituales para Linux y compilación cruzada
TARGETS="x86_64-unknown-linux-gnu x86_64-unknown-linux-musl aarch64-unknown-linux-gnu"
for target in $TARGETS; do
  /root/.cargo/bin/rustup target add "$target" 2>/dev/null || true
  su - vagrant -c "rustup target add $target" 2>/dev/null || true
done

# Exportar PATH de Cargo globalmente
# Exportar PATH y CARGO_TARGET_DIR globalmente
echo 'export PATH="/home/vagrant/.cargo/bin:/root/.cargo/bin:$PATH"' > /etc/profile.d/rust.sh
echo 'export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/tmp/cargo-target}"' >> /etc/profile.d/rust.sh
chmod +x /etc/profile.d/rust.sh
ln -sf /root/.cargo/bin/* /usr/local/bin/ 2>/dev/null || true
ln -sf /home/vagrant/.cargo/bin/* /usr/local/bin/ 2>/dev/null || true

# Instalar sccache para aceleración de compilaciones Rust
if ! command -v sccache >/dev/null 2>&1; then
  echo "Instalando sccache..."
  curl -sSL https://github.com/mozilla/sccache/releases/download/v0.8.2/sccache-v0.8.2-x86_64-unknown-linux-musl.tar.gz | tar xz -C /tmp
  mv /tmp/sccache-v0.8.2-x86_64-unknown-linux-musl/sccache /usr/local/bin/
  chmod +x /usr/local/bin/sccache
  rm -rf /tmp/sccache*
fi

# Configurar enlazador ultrarrápido 'mold'
mkdir -p /home/vagrant/.cargo /root/.cargo
cat << 'EOF' > /home/vagrant/.cargo/config.toml
[target.x86_64-unknown-linux-gnu]
linker = "clang"
rustflags = ["-C", "link-arg=-fuse-ld=mold"]
EOF
cp /home/vagrant/.cargo/config.toml /root/.cargo/config.toml
chown -R vagrant:vagrant /home/vagrant/.cargo

echo "=== [dev-forge : Linux] 10-rust: Toolchain de Rust configurado con éxito ==="

