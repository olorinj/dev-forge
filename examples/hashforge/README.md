# HashForge - Suite de Validación Multi-Lenguaje y Multi-VM

**HashForge** es una suite criptográfica (CLI y GUI) desarrollada como banco de pruebas integral para verificar la capacidad del orquestador **`dev-forge`** de compilar ejecutables nativos en múltiples lenguajes de programación a través de máquinas virtuales aisladas (**Linux** y **Windows**).

Todos los lenguajes implementan exactamente la misma especificación criptográfica: cálculo simultáneo de resúmenes **SHA-256** y **MD5** con salida formateada y en JSON.

```mermaid
flowchart TD
    subgraph Orquestador["Orquestador dev-forge"]
        CLI["dev-forge build -p examples/hashforge/<lenguaje> -t <target>"]
    end

    subgraph VMs["Entornos de Compilación Desacoplados"]
        LinuxVM["forge-linux (Debian 12)\nGCC, Clang, Rustup, Go, Python/PyInstaller"]
        WinVM["forge-windows (Windows 11)\nMSVC 2022, Rust MSVC, Go Win, Python/PyInstaller"]
    end

    subgraph Lenguajes["Implementaciones de HashForge"]
        L_Rust["Rust (CLI + GUI egui)"]
        L_Py["Python (CLI + GUI tkinter + PyInstaller)"]
        L_C["C (C99 / CMake / OpenSSL & CryptoAPI)"]
        L_Cpp["C++ (C++17 / CMake / OpenSSL & CryptoAPI)"]
        L_Go["Go (CLI / standard library crypto)"]
    end

    CLI --> Lenguajes
    Lenguajes -->|Target: linux| LinuxVM
    Lenguajes -->|Target: windows| WinVM

    LinuxVM -->|ELF nativo| Dist["dist/ (Binarios finales)"]
    WinVM -->|PE32+ .exe| Dist
```

---

## 1. Implementaciones Disponibles

| Directorio | Lenguaje | GUI / CLI | Sistema de Construcción | Binario Linux | Binario Windows |
| :--- | :--- | :--- | :--- | :--- | :--- |
| [`rust/`](rust/) | **Rust 2021** | CLI + GUI (`egui`/`eframe`) | Cargo | `dist/hashforge` | `dist/hashforge.exe` |
| [`python/`](python/) | **Python 3.12** | CLI + GUI (`tkinter`) | PyInstaller standalone | `dist/hashforge-py` | `dist/hashforge-py.exe` |
| [`c/`](c/) | **C (C99)** | CLI | CMake / Makefile | `dist/hashforge-c` | `dist/hashforge-c.exe` |
| [`cpp/`](cpp/) | **C++ (C++17)** | CLI | CMake / Makefile | `dist/hashforge-cpp` | `dist/hashforge-cpp.exe` |
| [`go/`](go/) | **Go 1.23** | CLI | Go toolchain (`go build`) | `dist/hashforge-go` | `dist/hashforge-go.exe` |

---

## 2. Compilación Individual de Lenguajes con `dev-forge`

```bash
# Compilar Rust para Linux en forge-linux
dev-forge build -p examples/hashforge/rust -t linux

# Compilar Python para Windows en forge-windows (genera .exe autocontenido)
dev-forge build -p examples/hashforge/python -t windows

# Compilar C para Linux en forge-linux
dev-forge build -p examples/hashforge/c -t linux

# Compilar C++ para Windows en forge-windows (compilador nativo MSVC)
dev-forge build -p examples/hashforge/cpp -t windows

# Compilar Go para ambas VMs
dev-forge build -p examples/hashforge/go -t all
```

---

## 3. Ejecución de Pruebas Automatizadas

Cada subcarpeta de lenguaje contiene su propio `test.sh` y `test.ps1`. Adicionalmente, el directorio raíz de `hashforge` cuenta con un **orquestador maestro de pruebas**:

### En Linux / Bash:
```bash
# Probar un lenguaje específico en forge-linux:
./test.sh rust linux
./test.sh python linux
./test.sh c linux
./test.sh cpp linux
./test.sh go linux

# Probar un lenguaje específico en forge-windows:
./test.sh rust windows

# Probar TODOS los lenguajes en AMBAS VMs:
./test.sh all all
```

### En Windows / PowerShell:
```powershell
# Probar un lenguaje específico:
.\test.ps1 -Language rust -Target windows
.\test.ps1 -Language python -Target windows
.\test.ps1 -Language c -Target windows

# Probar TODOS los lenguajes en AMBAS VMs:
.\test.ps1 -Language all -Target all
```
