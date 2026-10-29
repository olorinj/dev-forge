# Arquitectura y flujo de trabajo con subagentes en `dev-forge`

Este documento describe la integración de **subagentes especializados** en el ecosistema `dev-forge`, materializando las directrices de [`AGENTS.md`](file:///home/olorinj/DEV/dev-forge/.agents/AGENTS.md) y los roles definidos en `.agents/roles/` dentro de un modelo de orquestación desacoplado.

---

## 1. Motivación y principios

En proyectos con múltiples toolchains, compilación cruzada, interfaces gráficas de alto rendimiento (Tauri/egui) y estrictos estándares de seguridad, un modelo de agente monolítico presenta dos cuellos de botella críticos:

1. **Saturación de Contexto (Context Bloat)**: Las trazas de compiladores (`cargo clippy`, `rustc`, `VBoxManage`, WiX), tests masivos y análisis estáticos consumen rápidamente la ventana de contexto, provocando degradación en la fidelidad de seguimiento de reglas.
2. **Sesgo de Confirmación**: El mismo agente que escribe el código tiende a validar sus propios cambios con menor rigor crítico.

La arquitectura de subagentes resuelve esto dividiendo el trabajo en **un Orquestador (Tech Lead)** y **Especialistas de Ejecución y Auditoría Aislados**.

```mermaid
flowchart TD
    User["👤 Desarrollador (Host)"] <-->|"Instrucciones / Consentimiento explícito"| Orchestrator["🧠 Antigravity (Orquestador / Tech Lead)"]

    subgraph Sandbox["Entorno de Aislamiento de Subagentes"]
        Orchestrator -->|"1. Exploración / Cross-Project"| ResSub["🔍 research (Lectura y Síntesis)"]
        ResSub -->|"Resumen de patrones sin código basura"| Orchestrator

        Orchestrator -->|"2. Maquetación e IPC Desktop"| TauriSub["💻 tauri-ui-specialist"]
        TauriSub -->|"Componentes UI + Comandos Rust"| Orchestrator

        Orchestrator -->|"3. Pre-Flight Quality Gate & SecOps"| QASub["🛡️ quality-gate-auditor"]
        QASub -->|"Veredicto: Formato, Clippy 0 warnings, Tests OK"| Orchestrator

        Orchestrator -->|"4. Empaquetado Multi-Plataforma"| PackSub["📦 native-packager"]
        PackSub -->|"Instaladores MSI/Setup, AppImage, DMG en dist/"| Orchestrator

        Orchestrator -->|"5. Aprovisionamiento & Hypervisor"| VboxSub["⚙️ vagrant-virtualization-architect"]
        VboxSub -->|"VMs aprovisionadas, VirtIO, Caches en /tmp"| Orchestrator

        Orchestrator -->|"6. Sincronización Docs, Changelog & Mermaid"| DocSub["📝 documentation-specialist"]
        DocSub -->|"Docs, README, Changelog y diagramas al día"| Orchestrator
    end

    Orchestrator -->|"7. Propuesta final limpia + Solicitud de Commit"| User
```

---

## 2. Catálogo de subagentes especializados

### 2.1. `tauri-ui-specialist`
* **Definición**: Especialista en desarrollo frontend y backend IPC para aplicaciones de escritorio Tauri (Rust + Svelte/Tailwind CSS/Vite).
* **Rol de referencia**: [tauri-ui-agent.md](file:///home/olorinj/DEV/dev-forge/.agents/roles/common/tauri-ui-agent.md).
* **Invariantes que supervisa**:
  - **Experiencia de escritorio nativa**: Barras de título personalizadas, zonas de arrastre (`data-tauri-drag-region`), anulación de menús contextuales de navegador innecesarios.
  - **Estética moderna**: Distribución limpia estilo Bento Box, translucidez sutil (glassmorphism), microinteracciones y diseño enfocado en modo oscuro por defecto.
  - **Seguridad de confianza cero (Zero-Trust)**: Validación estricta en Rust de todo payload proveniente del frontend; prohibición de `eval()` o scripts remotos.
  - **Simetría y retroalimentación**: En interfaces bidireccionales (ej. cifrado/descifrado, ofuscación), garantiza señales de completado equivalentes (avisos con conteo de elementos y tiempo en ms).

### 2.2. `quality-gate-auditor`
* **Definición**: Auditor estricto de QA, seguridad, prevención de ReDoS y control de calidad previo a la integración.
* **Roles de referencia**: [quality-gate-auditor.md](file:///home/olorinj/DEV/dev-forge/.agents/roles/common/quality-gate-auditor.md), [security-auditor.md](file:///home/olorinj/DEV/dev-forge/.agents/roles/common/security-auditor.md) y [qa-fuzzer.md](file:///home/olorinj/DEV/dev-forge/.agents/roles/common/qa-fuzzer.md).
* **Invariantes que supervisa**:
  - **Control de calidad previo al commit (mandatorio)**:
    1. *Formateo*: `cargo fmt --all -- --check` / `ruff format --check .`.
    2. *Análisis estricto*: Cero errores y cero advertencias (`cargo clippy --all-targets --all-features -- -D warnings`). Verificación de `#![warn(clippy::pedantic)]`.
    3. *Cero regresiones*: Ejecución de suites de prueba (`cargo test -q`) con 100% de éxito.
    4. *Verificación de cambios*: Inspección de `git diff` para evitar modificaciones espurias.
  - **Cero pánicos en Rust**: Erradicación de `unwrap()` y `expect()` en código de producción.
  - **Prevención de ReDoS**: Detección de cuantificadores anidados o retroceso catastrófico en expresiones regulares.
  - **Higiene de CLI en Unix**: Verificación de que `stdout` se reserve exclusivamente para flujos de datos puros y `stderr` para logs.

### 2.3. `native-packager`
* **Definición**: Especialista en empaquetado nativo multiplataforma, generación de instaladores y recolección de artefactos en `dist/`.
* **Rol de referencia**: [packager.md](file:///home/olorinj/DEV/dev-forge/.agents/roles/common/packager.md).
* **Invariantes que supervisa**:
  - **Generación dual de instaladores para Windows**: Paquete corporativo `.msi` (WiX Toolset) e instalador guiado `-setup.exe` (Inno Setup).
  - **Saneamiento estricto de versiones WiX**: Conversión de semver a formato `major.minor.build` numérico estricto (`major <= 255`, `minor <= 255`, `build <= 65535`) para evitar fallos de compilación MSI.
  - **Invariante criptográfica anticolisión GUI frente a CLI**: Cálculo del hash SHA-256 del binario de la CLI para garantizar que ningún binario empaquetado como GUI comparta el mismo hash o nombre. Prohibición estricta de enmascarar binarios CLI como aplicaciones GUI.
  - **Higiene de AppImage y FUSE**: Exportación de `APPIMAGE_EXTRACT_AND_RUN=1` y `NO_STRIP=1` en entornos headless/CI sin privilegios FUSE.
  - **Inyección de metadatos y recursos**: Integración de iconos de alta resolución (`icon.ico` multirresolución 16x16 a 256x256) y metadatos de versión PE respetando `DISABLE_WINRES=1` para evitar colisiones con `tauri-build`.

### 2.4. `vagrant-virtualization-architect`
* **Definición**: Arquitecto de infraestructura virtualizada, hipervisores (VirtualBox) y orquestación hermética multientorno vía Vagrant.
* **Roles y reglas de referencia**: [vagrant-architect.md](file:///home/olorinj/DEV/dev-forge/.agents/roles/common/vagrant-architect.md), [virtualization.md](file:///home/olorinj/DEV/dev-forge/.agents/rules/core/virtualization.md) y [dev-forge.md](file:///home/olorinj/DEV/dev-forge/.agents/rules/projects/dev-forge.md).
* **Invariantes que supervisa**:
  - **Cero compilación en carpetas compartidas**: Prohibición de compilación directa en carpetas compartidas (`vboxsf`). Redirección mandatoria de cachés efímeras (`CARGO_TARGET_DIR="/tmp/devforge-target"`, CMake `/tmp/build`, Go `/tmp/go-cache`, `C:\target` en Windows).
  - **Aceleración por hardware con VirtIO y caché de I/O**: Asignación obligatoria de `virtio-net` y almacenamiento con `--hostiocache on` / `cache: "writeback"`.
  - **Compatibilidad de controladoras en Windows (evitar bug NVMe #126)**: Aplicación exclusiva de controladoras SATA (AHCI) con flags SSD (`--nonrotational on`) en huéspedes Windows.
  - **Sincronización dinámica de teclado del anfitrión**: Detección de distribución de teclado del anfitrión e inyección automática en el huésped (`Set-WinUserLanguageList` en Windows, `localectl` en Linux).
  - **Aislamiento de Vagrant fuera del árbol**: Aplicación estricta de `VAGRANT_CWD` y `VAGRANT_DOTFILE_PATH` en la raíz de `dev-forge` para mantener los repositorios de clientes libres de metadatos `.vagrant`.
  - **Política de resiliencia y apagado dual**:
    - Si falla una optimización de kernel/SO, invoca reversión automática (`optimize-levelN.sh --rollback`) conforme a la invariante HashForge.
    - Si falla una compilación normal, apaga la VM de inmediato (`vagrant halt` / ACPI) para liberar memoria y recursos del host, a menos que el usuario haya indicado explícitamente `--keep-vm` (`-k`).

### 2.5. `documentation-specialist`
* **Definición**: Especialista en sincronización continua entre código fuente, manuales de usuario, arquitectura y registro de cambios semántico.
* **Rol de referencia**: [documentation-specialist.md](file:///home/olorinj/DEV/dev-forge/.agents/roles/common/documentation-specialist.md).
* **Invariantes que supervisa**:
  - **Separación estricta de README frente a `docs/`**: El `README.md` se reserva estrictamente al usuario final (propósito, instalación, uso rápido y de la CLI). Todo detalle técnico profundo (compiladores cruzados, flags de hipervisor, expresiones regulares, pipelines) pertenece a `docs/`.
  - **Sincronización de arquitectura visual**: Garantiza que todo cambio en nodos, topologías de VM o flujo de empaquetado actualice inmediatamente los diagramas Mermaid (`flowchart`, `sequenceDiagram`).
  - **Registro de cambios semántico (*Keep a Changelog*)**: Mantiene `CHANGELOG.md` al día bajo `[Unreleased]` categorizando rigurosamente en `Added`, `Changed`, `Fixed` y `Security`.
  - **Paridad y ayuda en CLI**: Verifica que cualquier flag o subcomando añadido en Rust o Python esté reflejado con exactitud en la documentación en Bash y PowerShell.
  - **Integridad de enlaces**: Comprueba que todos los enlaces relativos y anclas existan y no generen errores de destino no encontrado.

---

## 3. Matriz de disparo y umbrales de delegación (trigger policy)

Para garantizar un balance óptimo entre velocidad y aislamiento de contexto, el Orquestador aplica la siguiente política determinista de invocación:

```mermaid
flowchart TD
    Task["Petición del Desarrollador"] --> Check{"Evaluación de Umbrales"}
    
    Check -->|Modifica ui/, Svelte o Tauri IPC| T1["Invocar tauri-ui-specialist"]
    Check -->|Modifica Vagrantfile, provision/, scripts VM| T2["Invocar vagrant-virtualization-architect"]
    Check -->|Generación de .msi, -setup.exe, AppImage, dist/| T3["Invocar native-packager"]
    Check -->|Nuevos comandos CLI, cambio arquitectónico o cierre de versión| T4["Invocar documentation-specialist"]
    Check -->|Cambio > 3 archivos o previo a Git Commit| T5["Invocar quality-gate-auditor"]
    Check -->|Cambio menor < 30 líneas o consulta conceptual| Direct["Resolver en hilo principal (baja latencia)"]
```

### Reglas cuantitativas de activación
1. **Regla de la ventana de contexto**: Toda operación que anticipe generar más de 20 líneas de salida de compilador, linter o hypervisor (`cargo clippy`, `cargo test`, `vagrant up`, `wix`) debe ejecutarse en subagente.
2. **Puerta de entrada obligatoria**: Ningún commit local puede crearse sin la aprobación explícita de `quality-gate-auditor`.
3. **Exploración limpia**: Todo análisis cruzado de repositorios externos (LexiShield, Academia, etc.) debe realizarse mediante el subagente nativo `research` en modo solo lectura.

---

## 4. Secuencia de operación típica

```mermaid
sequenceDiagram
    autonumber
    actor Dev as Desarrollador
    participant Lead as Orquestador (Antigravity)
    participant VBox as vagrant-virtualization-architect
    participant UI as tauri-ui-specialist
    participant QA as quality-gate-auditor
    participant Pack as native-packager

    Dev->>Lead: "Implementar nueva UI y generar instaladores Windows/Linux"
    Lead->>VBox: Validar estado de VMs, cuotas WinRM y montajes efímeros
    VBox-->>Lead: VM lista con VirtIO y target en C:\target
    Lead->>UI: Diseñar vista Svelte + Comandos IPC en Rust
    UI-->>Lead: Componentes listos y probados
    Lead->>QA: Ejecutar Pre-Flight Quality Gate (fmt, clippy, tests, ReDoS)
    QA-->>Lead: PASSED (0 warnings, tests verdes)
    Lead->>Pack: Generar MSI (WiX), InnoSetup y AppImage
    Note over Pack: Verifica hash anti-colisión CLI vs GUI y cosecha en dist/
    Pack-->>Lead: Artefactos generados en dist/
    Lead->>Dev: Presenta resumen conciso, binarios generados y solicita permiso para commit
    Dev->>Lead: Aprueba commit
    Note over Lead: Genera Conventional Commit semántico en inglés
```

---

## 5. Mejoras directas en el flujo de desarrollo

| Dimensión | Enfoque Monolítico Anterior | Con Subagentes Especializados |
| :--- | :--- | :--- |
| **Consumo de Contexto** | Decenas de miles de tokens consumidos en logs de compiladores, linters y trazas de Vagrant. | Hilo principal limpio; los subagentes absorben los logs y devuelven solo la síntesis. |
| **Fidelidad de Reglas** | Riesgo de relajar restricciones (`-D warnings`, consentimiento) en hilos largos. | Subagentes con system prompts hiperfocalizados que no sufren dilución de contexto. |
| **Calidad de Código** | Un solo modelo autoevalúa su propio código. | Verificación independiente por un auditor adversario (`quality-gate-auditor`). |
| **Determinismo de Build** | El agente podía olvidar redirigir targets fuera de `vboxsf`, provocando bloqueos de archivos. | `vagrant-virtualization-architect` audita y aplica sistemáticamente las redirecciones efímeras. |
| **Integridad de Release** | Riesgo de empaquetar un binario CLI bajo el nombre de la GUI. | `native-packager` valida criptográficamente la anti-colisión SHA-256. |
| **Control del Usuario** | El usuario debe revisar salidas verbosas de la terminal. | El orquestador filtra el ruido y consulta al usuario solo las decisiones arquitectónicas clave. |

---

## 6. Extensibilidad

Cualquier nuevo rol agregado en `.agents/roles/common/` o `.agents/roles/projects/` puede registrarse inmediatamente como subagente invocable, manteniendo la modularidad y escalabilidad del ecosistema `dev-forge`.
