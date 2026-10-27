# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Informe Resumen Estructurado de Compilación (`DEV-FORGE BUILD EXECUTION REPORT`)**:
  - Salida formateada y coloreada al término de cada compilación (`dev-forge build`), desglosando proyecto, versión semver detectada, sanitización WiX, destino, componente, perfil y cronometraje preciso de ejecución.
  - Censo inteligente y diferencial de artefactos en `dist/` antes y después de compilar, clasificando entradas por tipo (`[PKG]`, `[GUI]`, `[BIN]`, `[TEST]`) con tamaño formateado en KiB/MiB/GiB y conteo total de artefactos nuevos/actualizados.
- **Boxes Oficiales Pre-Horneadas y Scripts de Reconstrucción Autónoma**:
  - Scripts de reconstrucción desatendida `scripts/rebuild-linux-box.sh`, `scripts/rebuild-windows-box.sh` y `scripts/rebuild-runner-box.sh`.
  - Purgado atómico de carpetas huérfanas en VirtualBox (`/mnt/data/virtualbox/<vm>` y `/DEV-FORGE/<vm>`) para prevenir colisiones `VERR_ALREADY_EXISTS`.
  - Saneamiento y hardening guest: bloqueo permanente de actualizaciones automáticas (APT masked, Windows Update Group Policy), purga estricta de kernels antiguos (1 único kernel activo) y preservación de claves inseguras oficiales de Vagrant para arranque instantáneo.
  - Artefactos verificados y empaquetados en `dist/boxes/`: `dev-forge-linux-v1.0.0.box` (2,4 GB), `dev-forge-windows-v1.0.0.box` (9,0 GB) y `dev-forge-runner-v1.0.0.box` (1,3 GB), acompañados de sumas criptográficas SHA-256 e informes diagnósticos.
- **Resolución Directa de Visual Studio Build Tools 2022**:
  - Descarga directa del instalador oficial `vs_buildtools.exe` desde `https://aka.ms/vs/17/release/vs_buildtools.exe` en `provision/ansible/windows.yml`, solventando el error de salida 5008 ocasionado por el bootstrapper obsoleto de Chocolatey.
- **Modo de Empaquetado `single` y Aceleración `--no-bundle` (`dev-forge build --package single`)**:
  - Incorporación del subvalor `single` en `--package` y de la opción `[4] Binario único puro (Solo ejecutable con versión explícita, sin bundles)` en el menú interactivo CLI.
  - Inyección automática del flag `--no-bundle` en `cargo tauri build` y `@tauri-apps/cli` en los modos `single` y `bin` para Linux y Windows, reduciendo sustancialmente los tiempos de compilación al evitar generar bundles innecesarios.
  - Salida limpia de 1 solo fichero en `dist/` (`<app>-<component>-<version>-<target>.<ext>`) sin duplicado canónico redundante ni instaladores auxiliares en modo `single`.
- **Subagente Universal y Rol de Documentación (`documentation-specialist`)**:
  - Definición del rol transversal `.agents/roles/common/documentation-specialist.md` y registro en `.agents/AGENTS.md` para mantener la sincronización continua de changelogs, READMEs, arquitectura y diagramas Mermaid.
  - Registro de `documentation-specialist` en el catálogo de subagentes y matriz de disparo de `docs/subagents.md`.
- **Orquestación Aislada de CI/CD Runner (`dev-forge runner`)**:
  - Definición de la máquina virtual dedicada `forge-runner` en `Vagrantfile` (`bento/debian-12` + Docker Engine + GitLab Runner).
  - Script de aprovisionamiento idempotente `provision/runner/setup-runner.sh` con creación de swapfile de 2GB para pases intensivos de compilación.
  - Subcomandos en CLI (`dev-forge runner <up|halt|status|ssh|register|start-gitlab>`) implementados con paridad dual en Rust y Python.
  - Utilidades automatizadas en el guest para registro de runner (`/usr/local/bin/register-runner`) y servidor GitLab CE local para pruebas CI 100% offline (`/usr/local/bin/start-gitlab-server`).
- **Instaladores Universales en 1 Línea (`install.sh` e `install.ps1`)**:
  - Instalación desatendida multiplataforma mediante `curl | bash` en Linux/macOS e `irm | iex` en Windows PowerShell.
  - Auto-detección de arquitecturas (`x86_64` y `aarch64` Apple Silicon).
  - Configuración automática del `$PATH` de usuario en `.bashrc`, `.zshrc` y en el Registro de Windows (`HKCU\Environment\Path`) sin requerir privilegios de administrador.
  - Generación de wrappers auxiliares (`dev-forge.cmd`) para interoperabilidad inmediata en cualquier terminal de Windows.
- **Workflow de Release Multiplataforma (`.github/workflows/release.yml`)**:
  - Compilación automatizada de binarios nativos independientes para `x86_64-unknown-linux-gnu`, `x86_64-pc-windows-msvc`, `x86_64-apple-darwin` y `aarch64-apple-darwin` con empaquetado comprimido y checksums SHA-256.
- **Documentación y Diagramas Multi-Nodo**:
  - Actualización de los diagramas Mermaid en `README.md` y `docs/architecture.md` incorporando la topología de 3 nodos virtuales (`forge-linux`, `forge-windows`, `forge-runner`).
  - Nuevas secciones operativas en `README.md` y `docs/gitlab-ci-runner.md` para el control integral de runners desde CLI.

### Fixed
- **Protección Anti-Bloqueo en Invocaciones de VirtualBox**:
  - Inyección de salvaguardas con timeout (2 segundos) en consultas a `VBoxManage` (`doctor`, `hardware` y `vagrant`) para evitar bloqueos indefinidos en entornos donde el daemon VBoxSVC no responde o está aislado.
- **Detección Segura de Carpeta Almacén de Máquinas Virtuales**:
  - Filtrado estricto de puntos de montaje de sistema (`/bin`, `/boot`, `/etc`, `/usr`, `/var`, etc.) en `detect_optimal_vbox_folder()` para garantizar que la carpeta de almacenamiento de VMs recaiga siempre en rutas de usuario seguras o particiones de datos válidas.

## [0.2.0] - 2026-10-24

### Added
- **Asistente Interactivo de Compilación en 4 Pasos (`dev-forge build`)**:
  - Asistente guiado por consola con selección inteligente de proyecto (inspección de `$PWD` o historial MRU de los últimos 5 proyectos en `~/.dev-forge/recent_projects.json` con soporte de `~`), componente (CLI, GUI, All, Tests), destino (Linux, Windows, macOS, All), formato (binarios, instaladores o ambos) y perfil (Release vs Testing/Debug).
- **Compilación de Artefactos de Prueba (`dev-forge build --test`)**:
  - Soporte para compilar suites de prueba y test runners nativos de forma aislada en máquinas virtuales para validación headless.
- **Convenio Universal de Nombres Versionados y Canónicos**:
  - Salida dual en `dist/` depositando binarios canónicos (`<app>-<component>-<target>.<ext>`) y versionados (`<app>-<component>-<version>-<target>.<ext>`) en todas las plataformas.
- **Ejecución Fuera del Árbol e Instalación de Usuario (`dev-forge install-bin`)**:
  - Enlace simbólico o copia en `~/.local/bin/dev-forge` sin requerir `sudo`.
  - Operación desacoplada desde cualquier ruta del host sin polución de directorios.
- **Contenedorización Dinámica de macOS Cross-Compilation (`osxcross`)**:
  - Fallback automático que genera y construye dinámicamente una imagen Docker basada en `crazymax/osxcross:latest-ubuntu` para compilar targets Darwin (`x86_64-apple-darwin` y `aarch64-apple-darwin`) en `forge-linux`.
- **Elevación Automática de Cuota de Memoria WinRM (8192 MB)**:
  - Configuración previa automática de `MaxMemoryPerShellMB = 8192` antes de ejecutar compilaciones complejas en Windows Server Core.
- **Sincronización Automática de Versión desde Ramas Git**:
  - Inferencia y propagación de versión semver a partir de ramas activas (`feature/v2.0.1` -> `2.0.1`) cuando el manifiesto del proyecto cliente carece de versión explícita.

### Changed
- **Aprovisionamiento Mínimo con Ansible**:
  - Migración del aprovisionamiento de Vagrant hacia playbooks de Ansible optimizados y mínimos para reducir huella de memoria en VMs.
- **Enrutamiento Multi-Crate para Aplicaciones de Escritorio (Tauri v2)**:
  - Detección explícita de `src-tauri/Cargo.toml` para compilar exclusivamente con `--manifest-path src-tauri/Cargo.toml` al seleccionar componente GUI.

### Fixed
- **Bloqueos de `vboxsf` con Frontends Web (Vite / Esbuild) en Windows Guest**:
  - Staging automático del código fuente web a almacenamiento volátil nativo (`$env:TEMP\build_ui`), compilación con `npm run build` y sincronización de artefactos compilados (`dist/`) de vuelta al workspace compartido.
- **Conflicto de Recursos de Windows (`winres` vs `tauri-build`)**:
  - Inyección de `$env:DISABLE_WINRES = '1'` y `$env:NO_STRIP = 'true'` en compilaciones de Tauri para Windows.
- **Invariante Criptográfico Anti-Colisión (CLI vs GUI)**:
  - Cálculo de hash SHA-256 del ejecutable CLI para verificar que ningún binario GUI cosechado coincida con el CLI. Detención inmediata con código de salida 1 ante ausencia de GUI real.
- **Aislamiento de Estado de Vagrant (`VAGRANT_DOTFILE_PATH`)**:
  - Exportación estricta de `VAGRANT_CWD` y `VAGRANT_DOTFILE_PATH` hacia la raíz de DevForge, resolviendo el error `The machine with the name 'forge-linux' was not found configured for this Vagrant environment` al ejecutar desde rutas externas.
- **Agotamiento de Tmpfs y Sanitización de Ramas en Linuxdeploy**:
  - Aplicación de `APPIMAGE_EXTRACT_AND_RUN=1` y `NO_STRIP=1` en AppImages de Linux y sanitización de caracteres en nombres de ramas.

## [0.1.0] - 2026-10-19

### Added
- **Multi-Platform Diagnostic Doctor (`dev-forge doctor`)**:
  - Implemented comprehensive pre-flight diagnostic suite across Linux, Windows, and macOS inspecting CPU hardware virtualization (Intel VT-x / AMD-V), host RAM, free disk space on VM target volumes, VirtualBox CLI, Vagrant, forwarded ports (2222, 55985), and OS kernel modules (`vboxdrv`, `/dev/kvm`).
  - Available across both native Rust CLI (`crates/forge-cli/src/doctor.rs`) and pure Python engine (`dev_forge/doctor.py`).
- **Persistent Host Compiler Cache & Cache Pruning (`dev-forge clean-cache`)**:
  - Synced host directory `~/.dev-forge/cache` into guests (`/forge-cache` on Linux, `C:\forge-cache` on Windows) providing shared caching for Cargo (`registry`), Go (`pkg/mod`), Pip (`cache`), and Gradle.
  - Implemented `dev-forge clean-cache` (with optional `--subsystem` selector) to measure and prune cached artifacts on demand.
- **Instant Boot & Storage Efficiency with Linked Clones**:
  - Enabled `vb.linked_clone = true` in `Vagrantfile` for both `forge-linux` and `forge-windows`, reducing initial instance creation time from minutes to seconds and dropping host disk footprint from ~25 GB to ~2-3 GB per VM.
- **Automated Windows Packaging Engine (Inno Setup & WiX MSI)**:
  - Automatically compiles standalone `.exe` binaries into Inno Setup installers (`<app>-setup.exe` with solid `lzma2` compression) and corporate Windows Installer packages (`<app>.msi` via WiX Toolset v3.14 `candle.exe` and `light.exe`) deposited directly into `dist/`.
  - Implemented in `provision/windows/package-artifacts.ps1` and triggered seamlessly across both Rust CLI (`crates/forge-cli/src/vagrant.rs`) and Python engine (`dev_forge/vagrant.py`).
  - Added WiX Toolset (`candle.exe`, `light.exe`) and Inno Setup (`ISCC.exe`) assertions to `provision/windows/health-check.ps1` (12/12 checks passing).
- **Universal Application Icon Discovery & Binding**:
  - Auto-detects project icons (`.ico` or `.png`) across prioritized standard locations (`assets/`, `icons/`, `src-tauri/icons/`, `resources/`, workspace root).
  - Implemented `provision/windows/convert-icon.py` providing automatic multi-resolution PNG-to-ICO conversion fallback (`16x16` up to `256x256`) when only PNG images exist.
  - Automatically binds discovered icons to Inno Setup installers (`SetupIconFile`, `{app}\app.ico`, and desktop/start-menu shortcuts).
  - Automatically binds discovered icons to WiX MSI packages (`<Icon Id="AppIcon">`, `ARPPRODUCTICON` registry for Windows Programs & Features, and advertised shortcuts).
  - Injects `--icon` CLI parameter automatically into PyInstaller compilation passes.
- **Native Rust Orchestrator CLI (`dev-forge`)**:
  - Implemented standalone, type-safe Rust binary in `crates/forge-cli` replacing ~1,150 lines of duplicate shell scripts.
  - Subcommands: `tune`, `status`, `up`, `halt`, `provision`, `ssh`, `build`, `test-vm`, and `completions`.
  - Native shell completion generator for Bash, Zsh, Fish, and PowerShell (`dev-forge completions <shell>`).
  - Cross-platform 7-bit ASCII banner and Win32 ANSI console initialization.
- **Dynamic Hardware Sizing & Profile Relocation**:
  - Auto-evaluates host physical CPU cores, logical threads, RAM, keyboard layout, and storage devices.
  - Relocated configuration out of workspace root into dedicated user profile directory `~/.dev-forge/` (`config.toml` and synchronized `forge-host.env`).
  - Strict host memory protection with adaptive tier sizing (4096 MB for 16 GB hosts, leaving $>11\text{ GB}$ headroom for host desktop and IDE).
- **Virtual Machine Mutual Exclusion**:
  - Automatic mutual exclusion for hosts with $\le 16\text{ GB}$ RAM in `crates/forge-cli/src/vagrant.rs`.
  - Transparently and gracefully halts the sibling VM (`vagrant halt <sibling>`) before starting the requested machine to prevent kernel OOM-killer invocations.
- **Debian 12 Headless Build Node (`forge-linux`)**:
  - Modular shell provisioning scripts (`00-base.sh` to `60-macos-cross.sh`).
  - 4-level optimization suite (`optimize-level2-recommended.sh`) tuning sysctl kernel buffers, tmpfs 2GB on `/tmp`, `mold` linker, and `sccache 0.8.2`.
  - Comprehensive automated guest health-check validation (`provision/linux/health-check.sh`, 12/12 checks passing).
- **Windows Server 2022 Standard Core Build Node (`forge-windows`)**:
  - Headless server core virtualization profile (`gusztavvargadr/windows-server-2022-standard-core`).
  - Multi-level optimization suite (`optimize-level2-recommended.ps1`) configuring Windows Defender compilation exclusions, filesystem optimizations, and WinRM quotas.
  - Automated guest health-check validation (`provision/windows/health-check.ps1`, 9/9 checks passing).
- **Pure Python Orchestrator Engine (`dev-forge.py` & `dev_forge/`)**:
  - Modular Python package achieving 100% subcommand and behavioral parity with the native Rust CLI (`dev_forge/cli.py`, `config.py`, `hardware.py`, `detector.py`, `vagrant.py`, `banner.py`).
  - Zero-dependency execution on host Python 3.10+ with cross-platform Win32/POSIX resource evaluation.
  - Transparent fallback integrated into `bin/dev-forge` (Bash) and `bin/dev-forge.ps1` (PowerShell with UTF-8 BOM).
  - Standalone entrypoint `dev-forge.py` and package runner `python -m dev_forge`.
  - Comprehensive unit test suite in `tests/test_dev_forge.py`.
- **Universal Multi-Language Verification Suite (`HashForge`)**:
  - Reference implementation in `examples/hashforge/` verifying toolchain health with deterministic SHA-256 and MD5 test vectors across Rust, Python, Go, Node, Java, and C/C++.
  - Dual-shell test harnesses (`test.sh` and `test.ps1`).
  - Documented full-matrix execution commands (`all all`, per-language, and per-target) in the main `README.md`.

### Changed
- **Purge of Android Toolchain & Mobile Scope**:
  - Purged Android Command-line Tools, SDK, and licenses from guest provisioning (`provision/linux/50-java.sh`) to optimize storage and host memory headroom.
  - Removed Android target and test matrix from `examples/hashforge/` (7 active desktop/backend ecosystems verified 7/7).
- **Windows MSVC Build Tools Provisioning**:
  - Upgraded [`provision/windows/10-msvc.ps1`](provision/windows/10-msvc.ps1) to install official Visual Studio 2022 C++ Build Tools (`visualstudio2022buildtools` with `Microsoft.VisualStudio.Workload.VCTools`), providing `cl.exe`, `link.exe`, and the Windows SDK.
  - Added `ninja v1.13.2` to baseline Windows provisioning in [`provision/windows/00-base.ps1`](provision/windows/00-base.ps1).
- **Headless Cryptographic Portability**:
  - Decoupled `gui` (`eframe`/OpenGL) feature in `examples/hashforge/rust/Cargo.toml` (`default = []`), eliminating `0xC0000135` (`STATUS_DLL_NOT_FOUND`) on Windows Server Core while preserving optional GUI capabilities.

### Fixed
- **Host Memory Starvation & Kernel OOM**:
  - Diagnosed concurrent VM execution on 15 GB host and fixed memory allocation policy to prevent host OOM killer kills on `VBoxHeadless`.
  - Formatted 16 GB high-speed swapfile on NVMe (`/mnt/data/swapfile`).
- **Windows VirtualBox Network Driver**:
  - Replaced VirtIO network adapter with native Intel PRO/1000 MT adapter for `forge-windows` to eliminate lack of in-box VirtIO drivers in Windows Server 2022.
- **Storage Controller Identifier**:
  - Fixed storage controller name from `"SATA"` to `"SATA Controller"` for VirtualBox storage attachment in `Vagrantfile`.
- **Dynamic Workspace Shared Folder Mounting**:
  - Resolved `Protocol error` (`EPROTO`) by adding pre-unmount sequence inside guests and transient shared folder attachment (`\\VBoxSvr\workspace` mapped to `C:\workspace` on Windows and `/workspace` on Linux).
  - Ensured WinRM commands in `dev-forge build` and `dev-forge test-vm` execute via PowerShell (`-s powershell -c`).

### Security
- **Air-Gapped & 100% Offline Compilation**:
  - All compiler passes run locally within guest VMs without pulling remote dependencies during build phases.
  - Target output directories isolated inside guests (`/tmp/cargo-target`, `C:\target`) and final artifacts deposited strictly into client `dist/`.

