# Guía de custom boxes de despliegue instantáneo (DevForge)

Esta guía documenta la arquitectura, optimizaciones, procedimiento de empaquetado y publicación de las imágenes virtuales oficiales de DevForge (`forge-linux`, `forge-windows` y `forge-runner`) empaquetadas conforme al estándar nativo oficial de Vagrant para máxima compatibilidad y arranque instantáneo.

```mermaid
flowchart TD
    subgraph Upstream["1. Imágenes Base Upstream"]
        Bento["bento/debian-12<br/>(Bento Project)"]
        Gusztav["gusztavvargadr/windows-server-2022<br/>(Gusztáv Varga)"]
    end

    subgraph Provisioning["2. Aprovisionamiento & Hardening"]
        Ansible["Ansible / Playbooks Declarativos<br/>(Rust, Go, Node, Java, MSVC, WiX)"]
        CleanSrv["Poda de Servicios Innecesarios<br/>(bluetooth, cups, avahi, suspend, etc.)"]
        NoUpdate["Bloqueo Permanente de Auto-Updates<br/>(apt-daily, unattended-upgrades, wuauserv)"]
        OneKernel["Purga de Kernels Obsoletos<br/>(Estrictamente 1 kernel activo en /boot)"]
        InsecureKey["Restauración Clave Vagrant Oficial<br/>(Garantiza conexión SSH limpia al primer intento)"]
    end

    subgraph Packaging["3. Zeroing & Empaquetado Nativo"]
        Zeroing["Zeroing in-guest (dd /EMPTY / sdelete)"]
        BoxPkg["vagrant package (OVF + StreamOptimized)"]
        BoxTar["Generación .box + Verificación SHA-256"]
    end

    subgraph Distribution["4. Distribución Oficial"]
        LocalReg["Vagrant Local: vagrant box add olorinj/..."]
        GHReleases["GitHub Releases: Direct Assets & Multipart Volumes"]
        GHMetadata["Catálogos JSON: config/boxes/metadata-*.json"]
    end

    Upstream --> Provisioning
    Bento --> Ansible
    Gusztav --> Ansible
    Ansible --> CleanSrv --> NoUpdate --> OneKernel --> InsecureKey
    InsecureKey --> Packaging
    Packaging --> Zeroing --> BoxPkg --> BoxTar
    BoxTar --> Distribution
    Distribution --> LocalReg
    Distribution --> GHReleases
    Distribution --> GHMetadata
```

---

## 1. Imágenes de origen y atribución upstream

DevForge construye sus entornos aislados sobre cajas base mantenidas por la comunidad de software libre. Se preserva y documenta su atribución original:

| Máquina DevForge | Tag Canónico | Imagen Base Upstream | Proveedor Original | URL del Repositorio Upstream |
| :--- | :--- | :--- | :--- | :--- |
| **`forge-linux`** | `olorinj/dev-forge-linux` | `bento/debian-12` (v202510.26.0) | Bento Project (Chef Software) | [https://app.vagrantup.com/bento/boxes/debian-12](https://app.vagrantup.com/bento/boxes/debian-12) |
| **`forge-windows`** | `olorinj/dev-forge-windows` | `gusztavvargadr/windows-server-2022-standard-core` | Gusztáv Varga | [https://app.vagrantup.com/gusztavvargadr/boxes/windows-server-2022-standard-core](https://app.vagrantup.com/gusztavvargadr/boxes/windows-server-2022-standard-core) |
| **`forge-runner`** | `olorinj/dev-forge-runner` | `bento/debian-12` (v202510.26.0) | Bento Project (Chef Software) | [https://app.vagrantup.com/bento/boxes/debian-12](https://app.vagrantup.com/bento/boxes/debian-12) |

---

## 2. Optimizaciones de reducción de tamaño y seguridad

Para garantizar compilaciones 100% deterministas, arranques instantáneos (~15 segundos) y mínima huella en disco:

### 2.1 Desactivación de actualizaciones automáticas
- **Linux (`forge-linux` / `forge-runner`)**:
  - Enmascaramiento completo y permanente (`systemctl mask`) de `unattended-upgrades.service`, `apt-daily.timer`, `apt-daily.service`, `apt-daily-upgrade.timer` y `apt-daily-upgrade.service`.
  - Configuración estricta en `/etc/apt/apt.conf.d/99devforge-no-periodic-updates` anulando toda descarga o actualización desatendida.
- **Windows (`forge-windows`)**:
  - Detención y deshabilitación permanente de los servicios `wuauserv` (Windows Update), `UsoSvc` (Update Orchestrator Service) y `WaaSMedicSvc`.
  - Deshabilitación de todas las tareas programadas de update (`\Microsoft\Windows\WindowsUpdate\*`).
  - Fijación forzada en el Registro de la directiva de grupo `NoAutoUpdate = 1` y `AUOptions = 1`.

### 2.2 Política estricta de un solo núcleo de kernel activo (Linux)
- El script de preparación inspecciona el kernel en ejecución con `uname -r`.
- Purga automáticamente todos los paquetes `linux-image-*` y `linux-headers-*` secundarios u obsoletos acumulados.
- Regenera el initramfs y actualiza GRUB (`update-grub`), garantizando que `/boot` y `/lib/modules` alberguen estrictamente **un único kernel limpio**, reduciendo drásticamente el tamaño del disco y evitando inconsistencias en arranque.

### 2.3 Poda de servicios innecesarios
- **Linux**: Desactivación y enmascaramiento de `bluetooth`, `cups` (impresoras), `avahi-daemon` (mDNS), `modemmanager`, `whoopsie`/`apport` (telemetría), `sleep.target`, `suspend.target`, `hibernate.target` y `systemd-timesyncd` (la hora se sincroniza directamente por el hypervisor VirtualBox).
- **Windows**: Desactivación de Windows Search Indexing (`WSearch`), Superfetch (`SysMain`), cola de impresión (`Spooler`), telemetría (`DiagTrack`) y reporte de errores (`WerSvc`).
- **Limpieza de almacén WinSxS**: Ejecución de `dism.exe /online /cleanup-image /startcomponentcleanup /resetbase` y eliminación de puntos de restauración VSS (`vssadmin delete shadows /all /quiet`).

### 2.4 Llenado de ceros y empaquetado estándar Vagrant
- **Linux**: Rellenado de espacio no asignado con `dd if=/dev/zero of=/EMPTY bs=1M; sync; rm -f /EMPTY`.
- **Windows**: Rellenado de bloques libres mediante Sysinternals `sdelete.exe -z C:`.
- **Restauración SSH**: Inyección de la clave pública insegura oficial de Vagrant en `/home/vagrant/.ssh/authorized_keys` para garantizar que cualquier host se autentique sin timeouts en el primer arranque.
- **Empaquetado oficial**: Empaquetado mediante `vagrant package` generando discos OVF compatibles (StreamOptimized) que se importan de forma instantánea sin incompatibilidades de formato de disco en ninguna versión de VirtualBox.

---

## 3. Estrategia de dos capas: cómo ampliar o modificar las boxes a posteriori

Las boxes pre-compiladas **no congelan** los entornos. El flujo recomendado para añadir nuevos lenguajes (ej. Swift, Zig, Haskell, .NET) se estructura en dos fases:

### Fase 1: prototipado rápido con Ansible en Git (1 a 2 minutos)
1. La **Fuente de la Verdad** es el repositorio Git. Añades la tarea o receta de instalación del nuevo lenguaje en `provision/ansible/linux.yml` o `provision/ansible/windows.yml`.
2. Ejecutas el aprovisionamiento sobre tu VM activa:
   ```bash
   dev-forge provision forge-linux
   ```
3. Ansible detectará que los lenguajes existentes ya están presentes (idempotencia) e instalará **únicamente** el nuevo lenguaje.
4. Puedes compilar y probar proyectos en tu entorno de inmediato.

### Fase 2: congelación y publicación de nueva versión
Cuando el nuevo lenguaje esté validado (por ejemplo, compilando un ejemplo en `examples/hashforge/`):
```bash
dev-forge box package forge-linux --version 1.1.0
```
El CLI ejecutará la poda, purga de kernels, zeroing, compactación VDI, generará la box `dev-forge-linux-v1.1.0.box` y la dejará lista para publicar la nueva versión oficial.

---

## 4. Reconstrucción autónoma y flujo por etapas

La CLI de `dev-forge` ofrece dos flujos de trabajo: ejecución total desatendida o ejecución por etapas (`--stage deploy-only` y `--stage package-only`) para iterar antes de congelar una nueva versión:

```mermaid
flowchart LR
    A["Ejecutar --stage deploy-only"] --> B["VM Lista & Viva"]
    B --> C["Añadir SDKs / Cambios Manuales"]
    C --> D["Ejecutar --stage package-only"]
    D --> E["Box vX.Y.Z Lista"]
```

### 4.1 Flujo por etapas (iteración y modificaciones previas)
1. **Desplegar en limpio y detenerse antes de optimizar**:
   ```bash
   dev-forge box rebuild linux --version 1.1.0 --stage deploy-only
   # o para Windows:
   dev-forge box rebuild windows --version 1.1.0 --stage deploy-only
   ```
2. **Acceder a la máquina e introducir mejoras/pruebas**:
   ```bash
   vagrant ssh forge-linux
   # o en Windows:
   vagrant winrm forge-windows -s powershell -c "..."
   ```
3. **Optimizar, empaquetar y validar la nueva box**:
   ```bash
   dev-forge box rebuild linux --version 1.1.0 --stage package-only
   # o para Windows:
   dev-forge box rebuild windows --version 1.1.0 --stage package-only
   ```

### 4.2 Flujo directo de reconstrucción total
```bash
# Reconstruir una máquina específica
dev-forge box rebuild linux --version 1.1.0
dev-forge box rebuild windows --version 1.1.0
dev-forge box rebuild runner --version 1.1.0

# O reconstruir todas en secuencia con exclusión mutua de RAM
dev-forge box rebuild all --version 1.1.0
```

---

## 5. Empaquetado y prueba local con la CLI

DevForge integra comandos nativos en su orquestador Rust para gestionar todo el ciclo de vida sin depender de scripts externos:

```bash
# Empaquetar la VM forge-linux con disco VDI
dev-forge box package forge-linux --version 1.0.0

# Empaquetar todas las VMs (forge-linux, forge-windows, forge-runner)
dev-forge box package all --version 1.0.0

# Registrar la box generada localmente en Vagrant para pruebas inmediatas
dev-forge box install forge-linux

# Listar boxes de DevForge instaladas en el sistema local
dev-forge box list
```

---

## 6. Publicación y Distribución en GitHub Releases

Debido a que HashiCorp ha descontinuado la carga de nuevas boxes en Vagrant Cloud (`app.vagrantup.com`), DevForge distribuye sus imágenes pre-empaquetadas directamente como activos en **GitHub Releases** con manifiestos de catálogo JSON versionados.

### 6.1 Manejo automático de límites de tamaño (> 2 GB)

GitHub Releases impone un límite estricto de **2,0 GB por asset individual**:
- **`dev-forge-runner`** (~1,3 GB): Se sube en un único archivo `.box` íntegro.
- **`dev-forge-linux`** (~2,4 GB) y **`dev-forge-windows`** (~9,0 GB): El orquestador divide automáticamente el paquete en volúmenes multipart (`.box.part00`, `.box.part01`, etc.) de máximo 1900 MB, calculando y firmando sumas SHA-256 individuales para cada fragmento y para el archivo unificado.

### 6.2 Publicación automatizada con `dev-forge box publish`

El subcomando `publish` gestiona todo el ciclo de particionado, hashes y subida a GitHub Releases (utilizando el CLI oficial `gh` o la API REST con `GITHUB_TOKEN` / `GH_TOKEN`):

```bash
# Simulación (--dry-run): calcula hashes y particionado sin subir nada
dev-forge box publish all --version 1.0.0 --dry-run

# Publicar una máquina específica (ej. forge-linux) en tu repositorio
dev-forge box publish linux --version 1.0.0 --repo olorinj/dev-forge

# Publicación completa desatendida para CI/CD o agentes autónomos
dev-forge box publish all --version 1.0.0 --repo olorinj/dev-forge --yes
```

---

### 6.3 Instalación y ensamblado automático con `dev-forge box install`

Para desplegar una box oficial en una máquina limpia directamente desde el release de GitHub, `dev-forge box install` descarga automáticamente los chunks, verifica su integridad y los concatena en streaming:

```bash
# Instalar automáticamente descargando y ensamblando los fragmentos desde GitHub Releases
dev-forge box install linux --from-github olorinj/dev-forge --version 1.0.0
dev-forge box install windows --from-github olorinj/dev-forge --version 1.0.0
dev-forge box install runner --from-github olorinj/dev-forge --version 1.0.0
```

---

### 6.4 Consumo directo mediante manifiestos de catálogo JSON

También puedes configurar tu `Vagrantfile` para apuntar a los catálogos JSON versionados alojados en el repositorio:
```ruby
config.vm.box = "olorinj/dev-forge-linux"
config.vm.box_url = "https://raw.githubusercontent.com/olorinj/dev-forge/main/config/boxes/metadata-linux.json"
```

