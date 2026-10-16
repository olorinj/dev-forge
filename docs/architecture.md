# Arquitectura del Sistema - `dev-forge`

`dev-forge` es una plataforma desacoplada de virtualización y compilación cruzada multi-lenguaje concebida para ejecutar compilaciones limpias e independientes del host (Modo B offline).

## 1. Diagrama de Arquitectura Global

```mermaid
flowchart TD
    subgraph Host["Máquina Anfitriona (Host Linux)"]
        User["Usuario / Desarrollador"] --> CLI["CLI: dev-forge build"]
        CLI --> Detector["Motor de Detección de Lenguajes"]
        CLI --> VagrantHost["Vagrant Host Engine"]
    end

    subgraph Proyectos_Clientes["Proyectos Clientes Externos"]
        RustP["Rust / Tauri (ej. lexishield)"]
        JavaP["Java / Android (Gradle)"]
        PyP["Python (Scripts / PyInstaller)"]
        GoP["Go (CLIs / Microservicios)"]
    end

    subgraph Forja["dev-forge Runtime"]
        Agents[".agents -> /home/olorinj/DEV/.agents/"]
        
        subgraph VM_Linux["forge-linux (Debian 12)"]
            L_Base["Toolchain Base (GCC, Clang, Mold, LLD)"]
            L_Rust["Rustup (GNU + Musl + Apple Darwin targets)"]
            L_Java["OpenJDK 21 LTS + Gradle + Android Cmdline Tools"]
            L_Py["Python 3.12 + Pyenv + UV + PyInstaller"]
            L_Go["Go 1.23.2 Toolchain"]
            L_Node["Node.js 20 LTS + Corepack (pnpm, yarn)"]
            L_Mac["Docker + osxcross + dmgbuild + rcodesign"]
        end

        subgraph VM_Win["forge-windows (Windows 11)"]
            W_MSVC["Visual Studio 2022 Community (MSVC + Windows SDK)"]
            W_Rust["Rust MSVC Toolchain (x86_64-pc-windows-msvc)"]
            W_Java["OpenJDK 21 LTS + Gradle Windows"]
            W_PyGo["Python 3.12 + Go Toolchain"]
            W_Pack["WiX Toolset v3/v4 + InnoSetup"]
        end
    end

    Detector -->|"Detecta tipo"| Proyectos_Clientes
    VagrantHost -->|"Monta en /workspace"| VM_Linux
    VagrantHost -->|"Monta en c:\\workspace"| VM_Win

    VM_Linux -->|"Deposita binarios"| Dist["dist/ (del proyecto cliente)"]
    VM_Win -->|"Deposita binarios"| Dist
```

---

## 2. Flujo de Compilación Desacoplada (Modo B)

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Desarrollador
    participant CLI as dev-forge CLI
    participant VBox as VirtualBox / Vagrant
    participant VM as VM (Linux o Windows)
    participant Client as Proyecto Cliente

    Dev->>CLI: dev-forge build -p /ruta/al/proyecto -t all
    CLI->>Client: Inspecciona ficheros (Cargo.toml, build.gradle, pyproject.toml, go.mod)
    CLI->>CLI: Determina tipo de proyecto y comando de compilación
    CLI->>VBox: Setea FORGE_WORKSPACE=/ruta/al/proyecto y arranca VM
    VBox->>VM: Monta proyecto en /workspace (Linux) o c:\workspace (Windows)
    CLI->>VM: Ejecuta compilación nativa en entorno aislado
    VM->>Client: Escribe ejecutables resultantes en dist/
    CLI->>VBox: Detiene la VM (si no se indicó --keep-vm)
    CLI-->>Dev: Notifica finalización exitosa
```

---

## 3. Principios de Aislamiento y Seguridad
1. **Host Inmutable**: La máquina host no requiere tener instalados compiladores de Windows, emuladores ni SDKs pesados.
2. **Cero Polución**: Las dependencias temporales y archivos intermedios de compilación se procesan dentro de la VM, manteniendo el proyecto cliente limpio.
3. **Persistencia de Bóveda y Agentes**: El enlace simbólico a `.agents` asegura el cumplimiento de las directrices y estándares universales del ecosistema.

