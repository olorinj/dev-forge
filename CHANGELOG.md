# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

