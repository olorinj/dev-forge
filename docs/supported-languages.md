# Lenguajes y Ecosistemas Soportados en `dev-forge`

`dev-forge` incluye en sus máquinas virtuales los entornos de compilación y empaquetado para los principales lenguajes de desarrollo de software:

| Ecosistema | Detección Automática | Herramientas en `forge-linux` | Herramientas en `forge-windows` | Destinos de Compilación |
| :--- | :--- | :--- | :--- | :--- |
| **Rust** | `Cargo.toml` | Rustup (Stable, Musl, Darwin), Mold, Clang | Rustup MSVC (`x86_64-pc-windows-msvc`), Visual Studio 2022 | Linux x86_64/arm64, Windows .exe, macOS Mach-O |
| **Rust + Tauri (GUI)** | `src-tauri/tauri.conf.json` | WebKit2GTK, GTK3, AppIndicator, Node.js 20, Npm, Cargo | WebView2, Node.js 20, MSVC, WiX Toolset, InnoSetup | Linux .AppImage / .deb, Windows .msi / .exe, macOS .app / .dmg |
| **Java** | `build.gradle`, `gradlew`, `pom.xml` | OpenJDK 21 LTS, Gradle | OpenJDK 21 LTS, Gradle Windows | Linux/Windows JARs/Fat-JARs |
| **Python** | `pyproject.toml`, `requirements.txt` | Python 3.12, UV, Pip, Pipx, PyInstaller | Python 3.12, Pip, PyInstaller | Linux ELF autocontenido, Windows .exe autocontenido |
| **Go** | `go.mod` | Go 1.23.2 Toolchain | Go 1.23.2 para Windows | Binarios estáticos Linux, Windows .exe, macOS |
| **C / C++** | `CMakeLists.txt`, `Makefile` | GCC 12, Clang/LLVM 16, CMake, Make, OpenSSL | MSVC 2022 C++ Build Tools, CMake, NMake | Binarios nativos ELF Linux, Windows PE32+ .exe |
| **Node.js / Web** | `package.json` | Node.js 20 LTS, Corepack (pnpm, yarn) | Node.js 20 LTS, npm | Bundles web (Vite, Rollup, Webpack) |

---

## 1. Ejemplos de Invocación

### Proyecto en Rust (o Rust + Tauri):
```bash
dev-forge build -p /home/usuario/DEV/rust/lexishield -t all
```

### Proyecto en Java:
```bash
dev-forge build -p /home/usuario/DEV/mi-app-java -t linux
```

### Proyecto en Python:
```bash
dev-forge build -p /home/usuario/DEV/mi-script -t windows
```

### Proyecto en Go:
```bash
dev-forge build -p /home/usuario/DEV/mi-microservicio -t linux
```

---

## 2. Compilación de Aplicaciones de Escritorio para macOS

`dev-forge` incluye capacidades para compilar binarios y bundles de escritorio para macOS directamente desde `forge-linux`:
- **macOS de Escritorio**: Compilación cruzada completa de binarios Mach-O, bundles `.app` y empaquetado en imágenes `.dmg` con `osxcross` y `dmgbuild`.
- **Librerías Nativas**: Compilación de lógica en Rust (`aarch64-apple-darwin` / `x86_64-apple-darwin`) o C/C++ utilizables en proyectos macOS.
- **Firmado Criptográfico**: Herramienta `rcodesign` en `forge-linux` para firmar paquetes y bundles desde Linux.


