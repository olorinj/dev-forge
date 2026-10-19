# Arquitectura del Sistema - `dev-forge`

`dev-forge` es una plataforma desacoplada de virtualización y compilación cruzada multi-lenguaje concebida para ejecutar compilaciones limpias e independientes del host (100% offline).

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
        JavaP["Java (Gradle / Maven)"]
        PyP["Python (Scripts / PyInstaller)"]
        GoP["Go (CLIs / Microservicios)"]
    end

    subgraph Forja["dev-forge Runtime"]
        Agents[".agents -> /home/olorinj/DEV/.agents/"]
        
        subgraph VM_Linux["forge-linux (Debian 12)"]
            L_Base["Toolchain Base (GCC, Clang, Mold, LLD, Fuse3)"]
            L_Rust["Rustup (GNU + Musl + Darwin targets) + Tauri"]
            L_Java["OpenJDK 21 LTS + Gradle"]
            L_Py["Python 3.12 + UV + PyInstaller + Nuitka"]
            L_Go["Go 1.23.2 Toolchain"]
            L_Node["Node.js 20 LTS + Corepack (pnpm, yarn)"]
            L_Mac["Docker + osxcross + dmgbuild + rcodesign"]
        end

        subgraph VM_Win["forge-windows (Windows 11)"]
            W_MSVC["Visual Studio 2022 Community (MSVC + Windows SDK)"]
            W_Rust["Rust MSVC Toolchain (x86_64-pc-windows-msvc)"]
            W_Java["OpenJDK 21 LTS + Gradle Windows"]
            W_PyGo["Python 3.12 (PyInstaller + Nuitka) + Go Toolchain"]
            W_Pack["WiX Toolset v3/v4 (.msi) + InnoSetup (-setup.exe)"]
        end
    end

    Detector -->|"Detecta tipo"| Proyectos_Clientes
    VagrantHost -->|"Monta en /workspace"| VM_Linux
    VagrantHost -->|"Monta en c:\\workspace"| VM_Win

    VM_Linux -->|"Deposita binarios"| Dist["dist/ (del proyecto cliente)"]
    VM_Win -->|"Deposita binarios"| Dist
```

---

## 2. Flujo de Compilación Desacoplada (100% Offline)

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

---

## 4. Optimizaciones de Rendimiento y Virtualización

Para garantizar compilaciones a máxima velocidad de I/O y red, la arquitectura incorpora los siguientes mecanismos:

### 4.1 VirtIO Networking
- En la máquina Linux (`forge-linux`), la tarjeta de red NAT principal está configurada con `--nictype1 virtio`.
- Esto reduce drásticamente la sobrecarga de interrupciones del kernel emuladas y acelera la descarga de dependencias externas (crates de crates.io, paquetes npm, módulos Go).

### 4.2 Host I/O Cache en Controladoras SATA
- Las controladoras de almacenamiento SATA tanto en `forge-linux` (`SATA Controller`) como en `forge-windows` (`SATA`) tienen activado `--hostiocache on`.
- Permite que VirtualBox aproveche la memoria RAM y la caché del sistema operativo anfitrión para operaciones asíncronas de lectura/escritura en disco.

### 4.3 Desacoplamiento de Build Target del Sistema Compartido (`vboxsf`)
- Las carpetas compartidas de VirtualBox (`vboxsf`) sufren de alta latencia y contención de bloqueos con miles de archivos pequeños temporales (como los generados por `cargo` o `npm`).
- `dev-forge` redirige automáticamente los directorios de compilación a los sistemas de archivos nativos de cada máquina virtual:
  - **Linux**: `CARGO_TARGET_DIR=/tmp/cargo-target` (en disco rápido ext4 con linker ultrarrápido `mold`).
  - **Windows**: `CARGO_TARGET_DIR=C:\target` (en disco nativo NTFS).
- Al finalizar la compilación, únicamente los binarios y librerías finales (`.exe`, `.dll`, ejecutables ELF, `.so`) son copiados al directorio `dist/` montado en el host.

### 4.4 Empaquetado Automático y Vinculación Universal de Iconos (Windows)
- Tras depositar los ejecutables en `dist/`, el script [`provision/windows/package-artifacts.ps1`](../provision/windows/package-artifacts.ps1) se dispara automáticamente:
  - **Detección de Iconos**: Busca `.ico` en rutas estándar (`assets/`, `icons/`, `src-tauri/icons/`, `resources/`, raíz). Si solo existe un `.png`, ejecuta [`provision/windows/convert-icon.py`](../provision/windows/convert-icon.py) para generar un `.ico` multi-capa (`16x16` a `256x256`) sin intervención del usuario.
  - **Inno Setup (`<app>-setup.exe`)**: Genera el manifiesto `.iss`, compila con `ISCC.exe`, aplica `SetupIconFile`, instala el `.ico` en `{app}` y asocia los accesos directos.
  - **WiX Toolset (`<app>.msi`)**: Genera el archivo `.wxs` con GUIDs deterministas, compila con `candle.exe` y enlaza con `light.exe -sval -spdb`, registrando la propiedad `ARPPRODUCTICON` para el panel de desinstalación de Windows y accesos directos.
  - **Compiladores (PyInstaller)**: Inyecta dinámicamente `--icon <ruta_ico>` en la generación del binario principal.

### 4.5 Clones Enlazados (`linked_clone = true`) para Ahorro de Disco e Instanciación en Segundos
- Ambas máquinas virtuales (`forge-linux` y `forge-windows`) tienen habilitada la directiva `vb.linked_clone = true` en el `Vagrantfile`.
- En lugar de clonar un disco virtual completo de 25-30 GB para cada VM, VirtualBox crea discos diferenciales copy-on-write basados en la imagen maestra (`base box`).
- **Beneficios**:
  - Tiempo de creación o recreación de la máquina virtual reducido de 5-10 minutos a $<10$ segundos.
  - Ocupación en disco reducida de ~25 GB a ~2-3 GB por máquina virtual.

### 4.6 Caché Persistente de Compiladores en el Host (`~/.dev-forge/cache`)
- Para evitar descargas repetitivas de paquetes y módulos de terceros entre compilaciones de diferentes proyectos o reinicios de máquinas virtuales, `dev-forge` monta `~/.dev-forge/cache` como volumen compartido:
  - **Linux**: Montado en `/forge-cache` (`CARGO_HOME=/forge-cache/cargo`, `GOMODCACHE=/forge-cache/go/pkg/mod`, `PIP_CACHE_DIR=/forge-cache/pip`, `GRADLE_USER_HOME=/forge-cache/gradle`).
  - **Windows**: Montado en `C:\forge-cache`.
- Los artefactos intermedios activos permanecen aislados en discos rápidos locales (`/tmp/cargo-target`, `C:\target`) para evitar bloqueos de red `vboxsf`, mientras que las descargas de paquetes se benefician de la persistencia en el host.
- El usuario puede purgar la caché en cualquier momento mediante `dev-forge clean-cache [--subsystem <nombre>]`.

### 4.7 Bypass de FUSE para AppImages y Bundles de Tauri en Linux Headless
- En compilaciones para Linux (`forge-linux`), el empaquetado de Tauri invoca internamente `linuxdeploy` para generar paquetes `.AppImage`. Dado que `linuxdeploy` es a su vez un ejecutable AppImage, su ejecución en entornos virtualizados headless o contenedores falla si requiere montar `/dev/fuse`.
- `dev-forge` inyecta automáticamente:
  - `export APPIMAGE_EXTRACT_AND_RUN=1`: Fuerza a los AppImages a auto-extraerse en `/tmp` y ejecutarse directamente sin requerir llamadas al sistema de montaje FUSE.
  - `export NO_STRIP=1`: Previene fallos de stripping en bibliotecas compartidas complejas empaquetadas por `linuxdeploy`.
- **Recolección Multi-Ruta de Bundles**: Debido al aislamiento en `/tmp/cargo-target`, Tauri genera los paquetes en `/tmp/cargo-target/release/bundle/`. El recolector de `dev-forge` escanea recursivamente tanto `/tmp/cargo-target/release/bundle/` como `src-tauri/target/release/bundle/` y copia todos los paquetes `.deb`, `.rpm` y `.AppImage` hacia `/workspace/dist/`.

### 4.8 Sanitización Determinista de Versiones Semver para WiX Toolset
- Las especificaciones del instalador de Windows (MSI) y de WiX Toolset exigen estrictamente números enteros en formato `Major.Minor.Build` (`Major <= 255`, `Minor <= 255`, `Build <= 65535`). Las etiquetas Semver convencionales (ej. `2.0.1-beta.1` o `1.0.0+build.42`) provocan fallos de sintaxis en `candle.exe`.
- `dev-forge` incorpora un motor de sanitización de versión:
  - Extrae la versión del manifiesto (`Cargo.toml`, `pyproject.toml`, `package.json`) o del árbol Git (`git describe --tags`).
  - Limpia y formatea los 3 componentes enteros requeridos por WiX (ej. `2.0.1`), asegurando la validez del MSI.
  - Conserva la versión semver completa en los nombres de archivo y en la metadata amigable de Inno Setup (`AppVersion`).

### 4.9 Compilación C Ahead-of-Time con Nuitka para Python (Anti-EDR/Antivirus)
- Los empaquetadores basados en cargadores ejecutables (como PyInstaller) empaquetan el runtime de Python y el bytecode comprimido, lo que a menudo dispara falsas alarmas heurísticas en motores antivirus y soluciones EDR corporativas en Windows.
- `dev-forge` soporta compilación mediante Nuitka (`--compiler nuitka`):
  - Transpila el código fuente Python a código C nativo y lo compila con GCC (Linux) o MSVC (Windows).
  - Produce ejecutables totalmente autónomos (`--standalone --onefile`) de arranque instantáneo y resistentes a bloqueos heurísticos.

---

## 5. Ergonomía del Entorno y Estabilidad Operativa

### 5.1 Cuotas de Memoria WinRM en Windows
- Por defecto, WinRM impone un límite estricto de memoria (`MaxMemoryPerShellMB = 512-1024 MB`), lo cual provoca bloqueos de conexión o fallos silenciosos durante compilaciones exigentes de MSVC o C++ nativo.
- El aprovisionamiento de `dev-forge` eleva automáticamente esta cuota a 8192 MB:
  ```powershell
  Set-Item WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 8192 -Force
  ```

### 5.2 Prevención de Latencia en Prompts Modernos (Starship)
- Shells con prompts interactivos (como [Starship](https://starship.rs)) disponen de un módulo `vagrant` que consulta `vagrant status` al ingresar en cualquier directorio que contenga un `Vagrantfile`. Esto introduce una molesta latencia de 1 a 2 segundos por comando.
- Se recomienda desactivar este módulo en la configuración del host (`~/.config/starship.toml`):
  ```toml
  [vagrant]
  disabled = true
  ```

### 5.3 Localización y Teclado Dinámico Host-to-Guest
- Tanto la máquina Linux (`forge-linux`) como la de Windows (`forge-windows`) detectan automáticamente en tiempo de ejecución la distribución de teclado y configuración regional de la máquina anfitriona (host):
  - **Detección Host**: En Linux anfitrión inspecciona `localectl`, `/etc/default/keyboard`, `setxkbmap` y `$LANG`. En Windows anfitrión consulta `Get-WinUserLanguageList` y `CultureInfo`.
  - **Mapeo Biyectivo**: Normaliza el código de distribución (ej. `es`, `us`, `fr`, `de`, `latam`) y lo traduce al identificador de consola Linux (ej. `es`) y a la etiqueta BCP-47 de Windows (ej. `es-ES`, `en-US`, `fr-FR`).
  - **Aprovisionamiento**: Se inyecta como parámetro en los scripts de aprovisionamiento base (`00-base.sh` en Linux y `00-base.ps1` en Windows), garantizando una experiencia de teclado 100% fiel al host físico del desarrollador sin mapeos manuales.

### 5.4 Entornos de Desarrollo Remoto con VS Code (`dev-forge ide`)
- Para desarrolladores que prefieren programar directamente dentro del entorno virtualizado (con todas las herramientas y bibliotecas nativas preinstaladas), el CLI ofrece el comando:
  ```bash
  dev-forge ide setup-vscode --project /ruta/a/mi-proyecto --profile rust
  ```
- **Capacidades**:
  - Extrae automáticamente la configuración SSH activa de la máquina virtual (`vagrant ssh-config`).
  - Genera dentro del proyecto la carpeta `.vscode/` con `launch.json`, `tasks.json`, `settings.json` y recomendaciones de extensiones adaptadas al lenguaje (`rust`, `python`, `go`, `java`, `c`).
  - Permite abrir VS Code y conectarse transparentemente a `forge-linux` usando la extensión *Remote - SSH*.



