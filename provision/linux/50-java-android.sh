#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== [dev-forge : Linux] 50-java-android: Configurando repositorio de OpenJDK 21 LTS ==="

# 1. Configurar repositorio oficial de Adoptium (Eclipse Temurin) para Debian 12 (Bookworm)
apt-get install -y --no-install-recommends gnupg curl ca-certificates
mkdir -p /etc/apt/keyrings
curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor --yes -o /etc/apt/keyrings/adoptium.gpg
echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb bookworm main" > /etc/apt/sources.list.d/adoptium.list

# 2. Configurar repositorio Debian bookworm-backports como respaldo secundario
echo "deb http://deb.debian.org/debian bookworm-backports main" > /etc/apt/sources.list.d/backports.list

apt-get update

# 3. Instalación de Java 21 (Temurin 21 o OpenJDK 21 backports o default-jdk)
if apt-get install -y --no-install-recommends temurin-21-jdk; then
  echo "Eclipse Temurin 21 JDK instalado con éxito."
elif apt-get install -y --no-install-recommends -t bookworm-backports openjdk-21-jdk; then
  echo "OpenJDK 21 (backports) instalado con éxito."
else
  echo "Instalando JDK por defecto del sistema..."
  apt-get install -y --no-install-recommends default-jdk
fi

# 4. Resolver dinámicamente JAVA_HOME
JAVA_BIN=$(readlink -f "$(which java)" 2>/dev/null || echo "")
if [ -n "$JAVA_BIN" ]; then
  JAVA_PATH=$(dirname "$(dirname "$JAVA_BIN")")
else
  JAVA_PATH="/usr/lib/jvm/default-java"
fi

cat << EOF > /etc/profile.d/java.sh
export JAVA_HOME="$JAVA_PATH"
export PATH="\$JAVA_HOME/bin:\$PATH"
EOF
chmod +x /etc/profile.d/java.sh

# 5. Instalar Gradle moderno (v8.10.2) compatible con Java 21 y Android Gradle Plugin
GRADLE_VER="8.10.2"
if ! command -v gradle >/dev/null 2>&1 || [[ "$(gradle -v 2>/dev/null)" != *"$GRADLE_VER"* ]]; then
  echo "Instalando Gradle ${GRADLE_VER}..."
  curl -fsSL "https://services.gradle.org/distributions/gradle-${GRADLE_VER}-bin.zip" -o /tmp/gradle.zip
  unzip -q -o /tmp/gradle.zip -d /opt
  rm -f /tmp/gradle.zip
  ln -sf "/opt/gradle-${GRADLE_VER}/bin/gradle" /usr/local/bin/gradle
fi

# 6. Configurar Android SDK Command-Line Tools
ANDROID_ROOT="/opt/android-sdk"
mkdir -p "$ANDROID_ROOT/cmdline-tools"

if [ ! -d "$ANDROID_ROOT/cmdline-tools/latest" ]; then
  echo "Descargando Android Command-Line Tools..."
  curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o /tmp/cmdline-tools.zip
  unzip -q -o /tmp/cmdline-tools.zip -d /tmp/android-tools
  mkdir -p "$ANDROID_ROOT/cmdline-tools/latest"
  cp -r /tmp/android-tools/cmdline-tools/* "$ANDROID_ROOT/cmdline-tools/latest/"
  rm -rf /tmp/cmdline-tools.zip /tmp/android-tools
fi

cat << EOF > /etc/profile.d/android.sh
export ANDROID_HOME="$ANDROID_ROOT"
export ANDROID_SDK_ROOT="$ANDROID_ROOT"
export PATH="\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH"
EOF
chmod +x /etc/profile.d/android.sh

export ANDROID_HOME="$ANDROID_ROOT"
export PATH="$ANDROID_ROOT/cmdline-tools/latest/bin:$PATH"

if command -v sdkmanager >/dev/null 2>&1; then
  echo "Aceptando licencias de Android y verificando plataformas requeridas..."
  yes | sdkmanager --licenses >/dev/null 2>&1 || true
  yes | sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0" >/dev/null 2>&1 || true
fi

chown -R vagrant:vagrant "$ANDROID_ROOT" 2>/dev/null || true

echo "=== [dev-forge : Linux] 50-java-android: Java $(java -version 2>&1 | head -n 1) y Gradle $(gradle -v 2>&1 | grep Gradle | head -n 1) listos ==="
