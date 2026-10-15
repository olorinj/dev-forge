#!/usr/bin/env bash
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== [dev-forge : Linux] 50-java-android: Instalando OpenJDK 21 LTS y Gradle ==="

apt-get install -y --no-install-recommends openjdk-21-jdk openjdk-21-jre-headless gradle

# Configurar JAVA_HOME global
JAVA_PATH=$(update-java-alternatives -l | head -n 1 | awk '{print $3}')
if [ -z "$JAVA_PATH" ]; then
  JAVA_PATH="/usr/lib/jvm/java-21-openjdk-amd64"
fi

cat << EOF > /etc/profile.d/java.sh
export JAVA_HOME="$JAVA_PATH"
export PATH="\$JAVA_HOME/bin:\$PATH"
EOF
chmod +x /etc/profile.d/java.sh

echo "=== [dev-forge : Linux] 50-java-android: Configurando Android Command-Line Tools base ==="
ANDROID_ROOT="/opt/android-sdk"
mkdir -p "$ANDROID_ROOT/cmdline-tools"

cat << EOF > /etc/profile.d/android.sh
export ANDROID_HOME="$ANDROID_ROOT"
export ANDROID_SDK_ROOT="$ANDROID_ROOT"
export PATH="\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$PATH"
EOF
chmod +x /etc/profile.d/android.sh

echo "=== [dev-forge : Linux] 50-java-android: Entorno Java y Android SDK listo ==="
