# Lenguajes y Ecosistemas Soportados en `dev-forge`

`dev-forge` incluye en sus máquinas virtuales los entornos de compilación y empaquetado para los principales lenguajes de desarrollo de software:

| Ecosistema | Detección Automática | Herramientas en `forge-linux` | Herramientas en `forge-windows` | Destinos de Compilación |
| :--- | :--- | :--- | :--- | :--- |
| **Rust** | `Cargo.toml` | Rustup (Stable, Musl, Darwin), Mold, Clang | Rustup MSVC (`x86_64-pc-windows-msvc`), Visual Studio 2022 | Linux x86_64/arm64, Windows .exe, macOS Mach-O |
| **Rust + Tauri (GUI)** | `src-tauri/tauri.conf.json` | WebKit2GTK, GTK3, AppIndicator, Node.js 20, Npm, Cargo, Fuse3 | WebView2, Node.js 20, MSVC, WiX Toolset, InnoSetup | Linux .AppImage / .deb / .rpm, Windows .msi / -setup.exe / .exe, macOS .app / .dmg |
| **Java** | `build.gradle`, `gradlew`, `pom.xml` | OpenJDK 21 LTS, Gradle | OpenJDK 21 LTS, Gradle Windows | Linux/Windows JARs/Fat-JARs |
| **Python** | `pyproject.toml`, `requirements.txt` | Python 3.12, UV, Pip, Pipx, PyInstaller, Nuitka | Python 3.12, Pip, PyInstaller, Nuitka, MSVC | Linux ELF / C-compilado, Windows .exe (PyInstaller o Nuitka anti-EDR) |
| **Go** | `go.mod` | Go 1.23.2 Toolchain | Go 1.23.2 para Windows | Binarios estáticos Linux, Windows .exe, macOS |
| **C / C++** | `CMakeLists.txt`, `Makefile` | GCC 12, Clang/LLVM 16, CMake, Make, OpenSSL | MSVC 2022 C++ Build Tools, CMake, NMake | Binarios nativos ELF Linux, Windows PE32+ .exe |
| **Node.js / Web** | `package.json` | Node.js 20 LTS, Corepack (pnpm, yarn) | Node.js 20 LTS, npm | Bundles web (Vite, Rollup, Webpack) |

---

## 1. Ejemplos de Invocación

### Proyecto en Rust (o Rust + Tauri):
```bash
dev-forge build -p /home/usuario/DEV/rust/lexishield -t all
```

### Proyecto en Python con Nuitka (Mitigación EDR/Antivirus):
```bash
dev-forge build -p /home/usuario/DEV/mi-script -t windows --compiler nuitka
```

### Proyecto en Java:
```bash
dev-forge build -p /home/usuario/DEV/mi-app-java -t linux
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

---

## 3. Compilación Resistente a Antivirus/EDR con Nuitka

Para aplicaciones en Python distribuidas en entornos corporativos o Windows donde herramientas tradicionales como PyInstaller sufren falsos positivos por heurística:
- Selecciona Nuitka mediante `--compiler nuitka` en el comando `build`.
- Transpila el código fuente a C y genera un binario PE32+ con MSVC nativo en `forge-windows`.
- Inserta automáticamente la versión del proyecto y metadatos de producto en el ejecutable.

---

## 4. Configuración de Entornos de Desarrollo en VS Code

`dev-forge` permite convertir la máquina virtual `forge-linux` en un entorno de desarrollo interactivo para VS Code con todas las cadenas de herramientas nativas:
```bash
dev-forge ide setup-vscode --project /home/usuario/DEV/mi-proyecto --profile <rust|python|go|java|c>
```
Este comando configura automáticamente:
- **SSH Remoto**: Extrae llaves y puertos de `forge-linux` para la extensión *Remote - SSH*.
- **Perfiles por Lenguaje**:
  - `rust`: Configuración de `rust-analyzer`, debugger `CodeLLDB`, y tareas `cargo build` / `cargo test`.
  - `python`: Intérprete Python de la VM, formateador Ruff y tareas de ejecución.
  - `go`: Extensión oficial de Go, debugger Delve (`dlv`).
  - `java`: Extensión Language Support for Java, tareas Gradle/Maven.
  - `c`: IntelliSense `clangd` / C/C++ Extension, tareas CMake.



