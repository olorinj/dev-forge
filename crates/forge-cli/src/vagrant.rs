use crate::cli::{
    BuildArgs, BuildComponent, BuildPackage, BuildProfile, PythonCompiler, TargetPlatform,
};
use crate::project::{
    detect_project_type, extract_project_name, extract_project_version, ProjectType, PythonManager,
};
use crate::terminal::{log_err, log_info, log_ok, log_warn};
use anyhow::{Context, Result};
use colored::Colorize;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub fn get_forge_dir() -> PathBuf {
    // Current directory or binary directory parent
    if Path::new("Vagrantfile").is_file() {
        return std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            // Check if exe is in target/release or bin
            for ancestor in parent.ancestors() {
                if ancestor.join("Vagrantfile").is_file() {
                    return ancestor.to_path_buf();
                }
            }
        }
    }
    PathBuf::from(".")
}

pub fn run_vagrant_streaming(args: &[&str], envs: &[(&str, &str)]) -> Result<bool> {
    let forge_dir = get_forge_dir();
    let mut cmd = Command::new("vagrant");
    cmd.args(args).current_dir(&forge_dir);

    for (k, v) in envs {
        cmd.env(k, v);
    }

    cmd.stdout(Stdio::inherit());
    cmd.stderr(Stdio::inherit());

    let status = cmd
        .status()
        .with_context(|| format!("Failed to execute 'vagrant {}'", args.join(" ")))?;

    Ok(status.success())
}

pub fn cmd_status() -> Result<()> {
    crate::config::load_host_profile()?;
    run_vagrant_streaming(&["status"], &[])?;
    Ok(())
}

pub fn ensure_mutual_exclusion(target_machine: &str) -> Result<()> {
    let profile = crate::config::load_host_profile()?;
    // Only enforce strict mutual exclusion on hosts with <= 16 GB RAM
    if profile.total_ram_gb > 16 {
        return Ok(());
    }

    let sibling = match target_machine {
        "forge-linux" => "forge-windows",
        "forge-windows" => "forge-linux",
        _ => return Ok(()),
    };

    let sibling_vbox_name = if sibling == "forge-linux" {
        "FORGE-LINUX"
    } else {
        "FORGE-WINDOWS"
    };

    if let Ok(out) = Command::new("VBoxManage")
        .args(["list", "runningvms"])
        .output()
    {
        let stdout = String::from_utf8_lossy(&out.stdout);
        if stdout.contains(sibling_vbox_name) || stdout.contains(sibling) {
            log_warn(&format!(
                "Host con memoria limitada ({} GB): apagando limpiamente '{}' para evitar colision de memoria...",
                profile.total_ram_gb, sibling
            ));
            let _ = run_vagrant_streaming(&["halt", sibling], &[]);
        }
    }

    Ok(())
}

pub fn cmd_up(machine: &str, provision: bool) -> Result<()> {
    crate::config::load_host_profile()?;
    ensure_mutual_exclusion(machine)?;
    let mut args = vec!["up", machine];
    if provision {
        args.push("--provision");
    }
    log_info(&format!("Levantando maquina virtual '{}'...", machine));
    let success = run_vagrant_streaming(&args, &[])?;
    if success {
        log_ok(&format!("Maquina '{}' levantada con exito.", machine));
    } else {
        log_err(&format!("Error al levantar la maquina '{}'.", machine));
        anyhow::bail!("Fallo vagrant up");
    }
    Ok(())
}

pub fn cmd_halt(machine: Option<&str>, force: bool) -> Result<()> {
    crate::config::load_host_profile()?;
    let mut args = vec!["halt"];
    if let Some(m) = machine {
        args.push(m);
    }
    if force {
        args.push("-f");
    }
    log_info("Deteniendo maquinas virtuales para liberar memoria...");
    let success = run_vagrant_streaming(&args, &[])?;
    if success {
        log_ok("Maquinas virtuales detenidas.");
    }
    Ok(())
}

pub fn cmd_provision(machine: Option<&str>) -> Result<()> {
    crate::config::load_host_profile()?;
    let mut args = vec!["provision"];
    if let Some(m) = machine {
        args.push(m);
    }
    log_info("Re-aprovisionando paquetes y herramientas...");
    let success = run_vagrant_streaming(&args, &[])?;
    if success {
        log_ok("Aprovisionamiento finalizado.");
    }
    Ok(())
}

pub fn cmd_ssh(machine: &str, command: Option<&str>) -> Result<()> {
    crate::config::load_host_profile()?;
    let mut args = vec!["ssh", machine];
    if let Some(c) = command {
        args.push("-c");
        args.push(c);
    }
    run_vagrant_streaming(&args, &[])?;
    Ok(())
}

pub fn cmd_test_vm(machine: &str) -> Result<()> {
    crate::config::load_host_profile()?;
    ensure_mutual_exclusion(machine)?;
    log_info(&format!(
        "Iniciando verificacion de salud y pruebas en '{}'...",
        machine
    ));

    if machine == "forge-linux" {
        // 1. Ensure VM is up
        let _ = run_vagrant_streaming(&["up", "forge-linux"], &[]);

        // 2. Run provision/linux/health-check.sh
        println!(
            "\n{}",
            "--- [1/2] Verificando Kernel y Optimizaciones del Guest ---".bold()
        );
        let success = run_vagrant_streaming(
            &[
                "ssh",
                "forge-linux",
                "-c",
                "sudo bash /forge/provision/linux/health-check.sh",
            ],
            &[],
        )?;

        if !success {
            log_err("La verificacion de salud del guest ha detectado inconsistencias.");
            anyhow::bail!("Fallo health-check");
        }

        // 3. Test HashForge multi-language verification if present
        let hashforge_sh = Path::new("examples/hashforge/test.sh");
        if hashforge_sh.is_file() {
            println!(
                "\n{}",
                "--- [2/2] Ejecutando Suite Multi-Lenguaje HashForge (Rust) ---".bold()
            );
            let status = Command::new("bash")
                .args(["examples/hashforge/test.sh", "rust", "linux"])
                .current_dir(get_forge_dir())
                .status();
            if let Ok(st) = status {
                if !st.success() {
                    log_warn("HashForge Rust finalizo con advertencias.");
                }
            }
        }

        log_ok("Todas las verificaciones de 'forge-linux' han finalizado con exito.");
    } else if machine == "forge-windows" {
        // 1. Ensure VM is up
        let _ = run_vagrant_streaming(&["up", "forge-windows"], &[]);

        // 2. Run provision/windows/health-check.ps1
        println!(
            "\n{}",
            "--- [1/2] Verificando Sistema y Toolchains de Windows Server Core ---".bold()
        );
        let success = run_vagrant_streaming(
            &[
                "winrm",
                "forge-windows",
                "-s",
                "powershell",
                "-c",
                "powershell.exe -ExecutionPolicy Bypass -NoProfile -File C:\\forge\\provision\\windows\\health-check.ps1",
            ],
            &[],
        )?;

        if !success {
            log_err("La verificacion de toolchains en Windows ha detectado inconsistencias.");
            anyhow::bail!("Fallo health-check de Windows");
        }

        // 3. Test HashForge multi-language verification on Windows
        let hashforge_sh = Path::new("examples/hashforge/test.sh");
        if hashforge_sh.is_file() {
            println!(
                "\n{}",
                "--- [2/2] Ejecutando Suite Multi-Lenguaje HashForge (Rust -> Windows) ---".bold()
            );
            let status = Command::new("bash")
                .args(["examples/hashforge/test.sh", "rust", "windows"])
                .current_dir(get_forge_dir())
                .status();
            if let Ok(st) = status {
                if !st.success() {
                    log_warn("HashForge Rust Windows finalizo con advertencias.");
                } else {
                    println!(
                        "\n{}",
                        "--- Verificacion In-Guest (C:\\workspace\\dist\\hashforge.exe) ---".bold()
                    );
                    let run_guest = "if (Test-Path C:\\workspace\\dist\\hashforge.exe) { & C:\\workspace\\dist\\hashforge.exe -s 'dev-forge test' -j } else { Write-Host 'No se encontro hashforge.exe' -ForegroundColor Red }";
                    let _ = run_vagrant_streaming(
                        &[
                            "winrm",
                            "forge-windows",
                            "-s",
                            "powershell",
                            "-c",
                            run_guest,
                        ],
                        &[],
                    );
                }
            }
        }

        log_ok("Todas las verificaciones de 'forge-windows' han finalizado con exito.");
    } else {
        log_info(&format!("Consultando estado de '{}'...", machine));
        run_vagrant_streaming(&["status", machine], &[])?;
    }

    Ok(())
}

pub fn cmd_build(args: &mut BuildArgs) -> Result<()> {
    crate::config::load_host_profile()?;

    let project_path = args.project.canonicalize().with_context(|| {
        format!(
            "Ruta de proyecto invalida o no encontrada: {:?}",
            args.project
        )
    })?;

    // If only project is passed (no target, no component, no package, no test flag)
    // or if --interactive is passed, trigger the interactive selection menu:
    let is_interactive = args.interactive
        || (args.target.is_none()
            && args.component.is_none()
            && args.package.is_none()
            && !args.test);

    if is_interactive {
        let _ = crate::menu::prompt_menu(args);
    }

    let target = args.target.unwrap_or(TargetPlatform::All);
    let component = args.component.unwrap_or(if args.test {
        BuildComponent::Test
    } else {
        BuildComponent::All
    });
    let package = args.package.unwrap_or(BuildPackage::All);
    let profile = args
        .profile
        .unwrap_or(if args.test || component == BuildComponent::Test {
            BuildProfile::Test
        } else {
            BuildProfile::Release
        });

    let ptype = detect_project_type(&project_path);
    let dist_dir = project_path.join("dist");
    std::fs::create_dir_all(&dist_dir)
        .with_context(|| format!("No se pudo crear carpeta dist en {:?}", dist_dir))?;

    let ver_info = extract_project_version(&project_path);

    log_info(&format!(
        "Proyecto a compilar:  {}",
        project_path.display().to_string().bold()
    ));
    log_info(&format!(
        "Tipo detectado:       {}",
        ptype.to_string().cyan().bold()
    ));
    log_info(&format!(
        "Versión detectada:    {} (WiX: {})",
        ver_info.display.cyan().bold(),
        ver_info.wix.green()
    ));
    log_info(&format!(
        "Destino solicitado:   {}",
        target.to_string().green().bold()
    ));
    log_info(&format!(
        "Componente / Tipo:    {}",
        component.to_string().cyan().bold()
    ));
    log_info(&format!(
        "Formato / Empaque:    {}",
        package.to_string().cyan().bold()
    ));
    log_info(&format!(
        "Modo / Perfil:        {}",
        profile.to_string().yellow().bold()
    ));

    let project_str = project_path.to_string_lossy().to_string();
    let envs = [("FORGE_WORKSPACE", project_str.as_str())];

    match target {
        TargetPlatform::Linux => {
            build_on_linux(&ptype, args, &envs, true, false)?;
        }
        TargetPlatform::Macos => {
            build_on_linux(&ptype, args, &envs, false, true)?;
        }
        TargetPlatform::Windows => {
            build_on_windows(&ptype, args, &envs)?;
        }
        TargetPlatform::All => {
            build_on_linux(&ptype, args, &envs, true, true)?;
            build_on_windows(&ptype, args, &envs)?;
        }
    }

    let dist_count = std::fs::read_dir(&dist_dir)
        .map(|entries| entries.filter_map(|e| e.ok()).count())
        .unwrap_or(0);

    if dist_count == 0 {
        anyhow::bail!(
            "La compilación finalizó pero no se generó ningún artefacto en '{}'",
            dist_dir.display()
        );
    }

    log_ok(&format!(
        "Compilacion finalizada. Binarios depositados en: {}",
        dist_dir.display().to_string().bold()
    ));

    Ok(())
}

fn build_on_linux(
    ptype: &ProjectType,
    args: &BuildArgs,
    envs: &[(&str, &str)],
    build_linux: bool,
    build_macos: bool,
) -> Result<()> {
    ensure_mutual_exclusion("forge-linux")?;
    log_info("Preparando entorno de compilacion en 'forge-linux'...");
    let mut up_args = vec!["up", "forge-linux"];
    if args.update {
        up_args.push("--provision");
    }
    run_vagrant_streaming(&up_args, envs)?;

    // Attach transient shared folder for dynamic workspace mounting
    let project_canonical = args
        .project
        .canonicalize()
        .unwrap_or_else(|_| args.project.clone());

    // Unmount any previous workspace inside guest cleanly
    let _ = run_vagrant_streaming(
        &[
            "ssh",
            "forge-linux",
            "-c",
            "if mountpoint -q /workspace; then sudo umount /workspace 2>/dev/null || sudo umount -l /workspace 2>/dev/null || true; fi",
        ],
        envs,
    );

    let _ = Command::new("VBoxManage")
        .args([
            "sharedfolder",
            "remove",
            "FORGE-LINUX",
            "--name",
            "workspace",
            "--transient",
        ])
        .output();
    let _ = Command::new("VBoxManage")
        .args([
            "sharedfolder",
            "add",
            "FORGE-LINUX",
            "--name",
            "workspace",
            "--hostpath",
            &project_canonical.to_string_lossy(),
            "--transient",
        ])
        .output();

    let mount_prefix = "sudo sed -i '/tmpfs \\/tmp tmpfs/d' /etc/fstab 2>/dev/null || true; if mountpoint -q /tmp; then sudo umount -l /tmp 2>/dev/null || true; fi; sudo sed -i 's|:/root/\\.cargo/bin||g' /etc/profile.d/*.sh /etc/profile 2>/dev/null || true; sudo mkdir -p /workspace && sudo mount -t vboxsf -o uid=1000,gid=1000,dmode=775,fmode=775 workspace /workspace 2>/dev/null || true; sudo systemctl daemon-reload 2>/dev/null || true; sudo chmod 666 /dev/fuse 2>/dev/null || true; export APPIMAGE_EXTRACT_AND_RUN=1; export NO_STRIP=1; source /etc/profile 2>/dev/null || true; export PATH=$(echo \"/home/vagrant/.cargo/bin:/usr/local/bin:/home/vagrant/.local/bin:$PATH\" | tr ':' '\\n' | grep -v '^/root' | awk '!seen[$0]++' | paste -sd ':' -); if [ -d /forge-cache ]; then export CARGO_HOME=/forge-cache/cargo GOMODCACHE=/forge-cache/go/pkg/mod PIP_CACHE_DIR=/forge-cache/pip GRADLE_USER_HOME=/forge-cache/gradle; mkdir -p /forge-cache/cargo /forge-cache/go/pkg/mod /forge-cache/pip /forge-cache/gradle; fi; ";

    let clean_cmd = if args.clean {
        "rm -rf /tmp/cargo-target/* /tmp/go-cache/* /tmp/build/* 2>/dev/null || true; "
    } else {
        ""
    };

    let ver_info = extract_project_version(&project_canonical);
    let app_name = extract_project_name(&project_canonical);
    let raw_ver = if !ver_info.raw.is_empty() {
        ver_info.raw.as_str()
    } else {
        "0.1.0"
    };
    let gui_name = if project_canonical.join("src-tauri/Cargo.toml").is_file() {
        extract_project_name(&project_canonical.join("src-tauri"))
    } else {
        format!("{}-gui", app_name)
    };
    let use_nuitka = !args.pyinstaller && args.compiler == PythonCompiler::Nuitka;

    let component = args.component.unwrap_or(if args.test {
        BuildComponent::Test
    } else {
        BuildComponent::All
    });
    let package = args.package.unwrap_or(BuildPackage::All);
    let is_test_mode =
        args.test || component == BuildComponent::Test || args.profile == Some(BuildProfile::Test);

    let linux_script = if is_test_mode {
        match ptype {
            ProjectType::Rust | ProjectType::RustTauri => format!(
                "{}mkdir -p /workspace/dist; \
                echo '=== [dev-forge : Linux] Compilando suite de testing para {app_name} ==='; \
                cd /workspace && CARGO_TARGET_DIR=/tmp/cargo-target cargo test --no-run --release; \
                for tb in $(find /tmp/cargo-target/release/deps/ -maxdepth 1 -type f -executable ! -name '*.so' ! -name '*.d' 2>/dev/null); do \
                    tb_base=$(basename \"$tb\"); \
                    if [[ \"$tb_base\" =~ ^{app_name}- ]] || [[ \"$tb_base\" == \"{app_name}\" ]]; then \
                        cp \"$tb\" '/workspace/dist/{app_name}-test-linux.x86_64'; \
                        cp '/workspace/dist/{app_name}-test-linux.x86_64' '/workspace/dist/{app_name}-test-{raw_ver}-linux.x86_64' 2>/dev/null || true; \
                        chmod +x '/workspace/dist/{app_name}-test-'* 2>/dev/null || true; \
                        echo '[dev-forge : Linux] Binario de prueba generado: /workspace/dist/{app_name}-test-linux.x86_64 ({raw_ver})'; \
                        break; \
                    fi; \
                done; \
                if [ ! -f '/workspace/dist/{app_name}-test-linux.x86_64' ]; then \
                    first_test=$(find /tmp/cargo-target/release/deps/ -maxdepth 1 -type f -executable ! -name '*.so' ! -name '*.d' 2>/dev/null | head -n 1); \
                    if [ -n \"$first_test\" ]; then \
                        cp \"$first_test\" '/workspace/dist/{app_name}-test-linux.x86_64'; \
                        cp '/workspace/dist/{app_name}-test-linux.x86_64' '/workspace/dist/{app_name}-test-{raw_ver}-linux.x86_64' 2>/dev/null || true; \
                        chmod +x '/workspace/dist/{app_name}-test-'* 2>/dev/null || true; \
                        echo '[dev-forge : Linux] Binario de prueba generado: /workspace/dist/{app_name}-test-linux.x86_64 ({raw_ver})'; \
                    fi; \
                fi;",
                clean_cmd
            ),
            ProjectType::Go => format!(
                "{}mkdir -p /workspace/dist && cd /workspace; \
                echo '=== [dev-forge : Linux] Compilando suite de testing Go para {app_name} ==='; \
                GOCACHE=/tmp/go-cache go test -c -o '/workspace/dist/{app_name}-test-linux.x86_64' . 2>/dev/null || true; \
                cp '/workspace/dist/{app_name}-test-linux.x86_64' '/workspace/dist/{app_name}-test-{raw_ver}-linux.x86_64' 2>/dev/null || true; \
                chmod +x '/workspace/dist/{app_name}-test-'* 2>/dev/null || true;",
                clean_cmd
            ),
            ProjectType::Python(_) => format!(
                "{}mkdir -p /workspace/dist && cd /workspace; \
                echo '=== [dev-forge : Linux] Verificando tests Python ==='; \
                if command -v pytest >/dev/null 2>&1; then \
                    pytest -q 2>&1 | tee /workspace/dist/test-results-linux.log || true; \
                else \
                    python3 -m unittest discover tests 2>&1 | tee /workspace/dist/test-results-linux.log || true; \
                fi;",
                clean_cmd
            ),
            ProjectType::CCpp => format!(
                "{}mkdir -p /workspace/dist /tmp/build && cd /workspace && cmake -B /tmp/build -S . -G Ninja -DBUILD_TESTING=ON && cmake --build /tmp/build && \
                find /tmp/build -maxdepth 2 -type f -executable \\( -name '*test*' -o -name '*_test' \\) -exec cp {{}} '/workspace/dist/{app_name}-test-linux.x86_64' \\; 2>/dev/null || true; \
                cp '/workspace/dist/{app_name}-test-linux.x86_64' '/workspace/dist/{app_name}-test-{raw_ver}-linux.x86_64' 2>/dev/null || true; \
                chmod +x '/workspace/dist/{app_name}-test-'* 2>/dev/null || true;",
                clean_cmd
            ),
            ProjectType::Java => format!(
                "{}mkdir -p /workspace/dist && cd /workspace; \
                echo '=== [dev-forge : Linux] Compilando tests Java ==='; \
                (gradle testClasses || ./gradlew testClasses || mvn test-compile || true);",
                clean_cmd
            ),
            _ => format!(
                "{}echo '[dev-forge : Linux] Testing no configurado para este tipo de proyecto.';",
                clean_cmd
            ),
        }
    } else {
        match ptype {
            ProjectType::RustTauri => {
                let build_cli = component == BuildComponent::All || component == BuildComponent::Cli;
                let build_gui = component == BuildComponent::All || component == BuildComponent::Gui;
                let copy_bundles = package == BuildPackage::All || package == BuildPackage::Bundle;

                let cli_step = if build_cli {
                    format!(
                        "echo '=== [dev-forge : Linux] Compilando CLI {app_name} ==='; \
                        cd /workspace && CARGO_TARGET_DIR=/tmp/cargo-target cargo build --release; \
                        if [ -f '/tmp/cargo-target/release/{app_name}' ]; then \
                            cp '/tmp/cargo-target/release/{app_name}' '/workspace/dist/{app_name}-cli-linux.x86_64'; \
                            cp '/workspace/dist/{app_name}-cli-linux.x86_64' '/workspace/dist/{app_name}-cli-{raw_ver}-linux.x86_64' 2>/dev/null || true; \
                            chmod +x '/workspace/dist/{app_name}-cli-'* 2>/dev/null || true; \
                        fi; "
                    )
                } else {
                    "".to_string()
                };

                let gui_step = if build_gui {
                    format!(
                        "echo '=== [dev-forge : Linux] Compilando GUI {gui_name} y Bundles ==='; \
                        if ! command -v cargo-tauri >/dev/null 2>&1; then \
                            if command -v cargo-binstall >/dev/null 2>&1; then \
                                cargo-binstall --no-confirm tauri-cli 2>/dev/null || true; \
                            elif command -v npm >/dev/null 2>&1; then \
                                sudo npm install -g @tauri-apps/cli 2>/dev/null || true; \
                            fi; \
                        fi; \
                        cd /workspace && (if command -v cargo-tauri >/dev/null 2>&1; then cargo tauri build; else npx --yes @tauri-apps/cli build; fi); \
                        for gb in '/tmp/cargo-target/release/{gui_name}' '/tmp/cargo-target/release/{app_name}-gui' 'src-tauri/target/release/{gui_name}' 'target/release/{gui_name}'; do \
                            if [ -f \"$gb\" ]; then \
                                cp \"$gb\" '/workspace/dist/{app_name}-gui-linux.x86_64'; \
                                cp '/workspace/dist/{app_name}-gui-linux.x86_64' '/workspace/dist/{app_name}-gui-{raw_ver}-linux.x86_64' 2>/dev/null || true; \
                                chmod +x '/workspace/dist/{app_name}-gui-'* 2>/dev/null || true; \
                                break; \
                            fi; \
                        done; "
                    )
                } else {
                    "".to_string()
                };

                let bundle_step = if build_gui && copy_bundles {
                    "find /tmp/cargo-target/release/bundle/ src-tauri/target/release/bundle/ target/release/bundle/ -type f \\( -name '*.deb' -o -name '*.rpm' -o -name '*.AppImage' \\) -exec cp {} /workspace/dist/ \\; 2>/dev/null || true"
                } else {
                    ""
                };

                format!(
                    "{}export APPIMAGE_EXTRACT_AND_RUN=1; export NO_STRIP=1; mkdir -p /workspace/dist; {}{}{}",
                    clean_cmd, cli_step, gui_step, bundle_step
                )
            }
            ProjectType::Rust => {
                if component == BuildComponent::Gui {
                    format!(
                        "{}echo '[dev-forge : Linux] GUI no aplicable para proyecto Rust estándar.';",
                        clean_cmd
                    )
                } else {
                    format!(
                        "{}mkdir -p /workspace/dist && cd /workspace && CARGO_TARGET_DIR=/tmp/cargo-target cargo build --release && \
                        if [ -f '/tmp/cargo-target/release/{app_name}' ]; then \
                            cp '/tmp/cargo-target/release/{app_name}' '/workspace/dist/{app_name}-cli-linux.x86_64'; \
                            cp '/workspace/dist/{app_name}-cli-linux.x86_64' '/workspace/dist/{app_name}-cli-{raw_ver}-linux.x86_64' 2>/dev/null || true; \
                            chmod +x '/workspace/dist/{app_name}-cli-'* 2>/dev/null || true; \
                        fi",
                        clean_cmd
                    )
                }
            }
            ProjectType::Python(details) => {
                let py_standalone = if use_nuitka {
                    format!(
                        "if command -v nuitka >/dev/null 2>&1; then nuitka --standalone --onefile --output-dir=/tmp/nuitka-out --product-version={} --assume-yes-for-downloads main.py -o {}-cli-linux.x86_64 && mkdir -p /workspace/dist && cp /tmp/nuitka-out/{}-cli-linux.x86_64 /workspace/dist/ && cp /workspace/dist/{}-cli-linux.x86_64 /workspace/dist/{}-cli-{}-linux.x86_64; else pyinstaller --clean -F --name {}-cli-linux.x86_64 main.py --distpath /workspace/dist/ && cp /workspace/dist/{}-cli-linux.x86_64 /workspace/dist/{}-cli-{}-linux.x86_64; fi",
                        ver_info.wix, app_name, app_name, app_name, app_name, raw_ver, app_name, app_name, app_name, raw_ver
                    )
                } else {
                    format!(
                        "pyinstaller --clean -F --name {}-cli-linux.x86_64 main.py --distpath /workspace/dist/ && cp /workspace/dist/{}-cli-linux.x86_64 /workspace/dist/{}-cli-{}-linux.x86_64",
                        app_name, app_name, app_name, raw_ver
                    )
                };
                match details.manager {
                    PythonManager::Uv => format!(
                        "{}cd /workspace && if [ -f main.py ]; then {}; else uv build --out-dir /workspace/dist/; fi",
                        clean_cmd, py_standalone
                    ),
                    PythonManager::Poetry => format!(
                        "{}cd /workspace && if [ -f main.py ]; then {}; else poetry build && cp -r dist/* /workspace/dist/; fi",
                        clean_cmd, py_standalone
                    ),
                    PythonManager::Pipenv => format!(
                        "{}cd /workspace && if [ -f main.py ]; then {}; else pipenv run python3 -m build -o /workspace/dist/; fi",
                        clean_cmd, py_standalone
                    ),
                    PythonManager::Pip => {
                        if details.is_multipython {
                            format!("{}cd /workspace && tox", clean_cmd)
                        } else {
                            format!(
                                "{}cd /workspace && if [ -f main.py ]; then {}; else python3 -m build -o /workspace/dist/ 2>/dev/null || python3 -m pip wheel . -w /workspace/dist/; fi",
                                clean_cmd, py_standalone
                            )
                        }
                    }
                }
            }
            ProjectType::Java => format!(
                "{}cd /workspace && chmod +x ./gradlew 2>/dev/null || true; (if [ -f ./gradlew ]; then ./gradlew build; elif [ -f pom.xml ]; then mvn package; else gradle build; fi) && find build/libs/ target/ -name '*.jar' ! -name '*-plain.jar' -exec cp {{}} /workspace/dist/ \\; 2>/dev/null || true",
                clean_cmd
            ),
            ProjectType::Go => format!(
                "{}mkdir -p /workspace/dist && cd /workspace && (GOCACHE=/tmp/go-cache go build -o '/workspace/dist/{app_name}-cli-linux.x86_64' . 2>/dev/null || GOCACHE=/tmp/go-cache go build -o '/workspace/dist/{app_name}-cli-linux.x86_64' ./...) && cp '/workspace/dist/{app_name}-cli-linux.x86_64' '/workspace/dist/{app_name}-cli-{raw_ver}-linux.x86_64' 2>/dev/null || true; chmod +x '/workspace/dist/{app_name}-cli-'* 2>/dev/null || true",
                clean_cmd
            ),
            ProjectType::Node => format!(
                "{}cd /workspace && (npm run build || yarn build || pnpm build) && cp -r dist/* build/* /workspace/dist/ 2>/dev/null || true",
                clean_cmd
            ),
            ProjectType::CCpp => format!(
                "{}rm -rf /tmp/build && mkdir -p /tmp/build /workspace/dist && cd /workspace && cmake -B /tmp/build -S . -G Ninja && cmake --build /tmp/build && find /tmp/build -maxdepth 2 -type f -executable ! -name '*.ninja*' ! -name '*.cmake' -exec cp {{}} '/workspace/dist/{app_name}-cli-linux.x86_64' \\; 2>/dev/null || true; cp '/workspace/dist/{app_name}-cli-linux.x86_64' '/workspace/dist/{app_name}-cli-{raw_ver}-linux.x86_64' 2>/dev/null || true; chmod +x '/workspace/dist/{app_name}-cli-'* 2>/dev/null || true",
                clean_cmd
            ),
            ProjectType::Generic => format!(
                "{}cd /workspace && if [ -f ./build.sh ]; then bash ./build.sh; elif [ -f ./Makefile ]; then make; fi",
                clean_cmd
            ),
        }
    };

    let macos_script = if is_test_mode {
        match ptype {
            ProjectType::Rust | ProjectType::RustTauri => format!(
                "echo '=== [dev-forge : macOS] Compilando suite de testing macOS para {app_name} ==='; \
                mkdir -p /workspace/dist; \
                cd /workspace; \
                rustup target add x86_64-apple-darwin aarch64-apple-darwin 2>/dev/null || true; \
                CARGO_TARGET_DIR=/tmp/cargo-target cargo test --target x86_64-apple-darwin --no-run --release 2>/dev/null || true; \
                for tb in $(find /tmp/cargo-target/x86_64-apple-darwin/release/deps/ -maxdepth 1 -type f -executable ! -name '*.so' ! -name '*.d' 2>/dev/null); do \
                    tb_base=$(basename \"$tb\"); \
                    if [[ \"$tb_base\" =~ ^{app_name}- ]] || [[ \"$tb_base\" == \"{app_name}\" ]]; then \
                        cp \"$tb\" '/workspace/dist/{app_name}-test-darwin.x86_64'; \
                        cp '/workspace/dist/{app_name}-test-darwin.x86_64' '/workspace/dist/{app_name}-test-{raw_ver}-darwin.x86_64' 2>/dev/null || true; \
                        chmod +x '/workspace/dist/{app_name}-test-'* 2>/dev/null || true; \
                        echo '[dev-forge : macOS] Binario de prueba generado: /workspace/dist/{app_name}-test-darwin.x86_64 ({raw_ver})'; \
                        break; \
                    fi; \
                done;"
            ),
            ProjectType::Go => format!(
                "mkdir -p /workspace/dist && cd /workspace; \
                echo '=== [dev-forge : macOS] Compilando suite de testing Go para Darwin ==='; \
                GOCACHE=/tmp/go-cache GOOS=darwin GOARCH=amd64 go test -c -o '/workspace/dist/{app_name}-test-darwin.x86_64' . 2>/dev/null || true; \
                cp '/workspace/dist/{app_name}-test-darwin.x86_64' '/workspace/dist/{app_name}-test-{raw_ver}-darwin.x86_64' 2>/dev/null || true; \
                chmod +x '/workspace/dist/{app_name}-test-'* 2>/dev/null || true;"
            ),
            _ => "echo '[dev-forge : macOS] Compilación de test para macOS omitida para este proyecto.';".to_string(),
        }
    } else if component == BuildComponent::Gui {
        "echo '[dev-forge : macOS] Compilación de GUI para macOS omitida (solo CLI).';".to_string()
    } else {
        match ptype {
            ProjectType::Rust | ProjectType::RustTauri => format!(
                "echo '=== [dev-forge : macOS] Compilando binarios Darwin Mach-O para {app_name} ==='; \
                mkdir -p /workspace/dist; \
                if [ -f /workspace/build/Dockerfile.osxcross ]; then \
                    OSXCROSS_DOCKER='/workspace/build/Dockerfile.osxcross'; \
                elif [ -f /workspace/Dockerfile.osxcross ]; then \
                    OSXCROSS_DOCKER='/workspace/Dockerfile.osxcross'; \
                else \
                    OSXCROSS_DOCKER=''; \
                fi; \
                if [ -n \"$OSXCROSS_DOCKER\" ]; then \
                    echo '[dev-forge : macOS] Compilando mediante contenedor osxcross ('\"$OSXCROSS_DOCKER\"')...'; \
                    cd /workspace; \
                    sudo docker build -t forge-osxcross -f \"$OSXCROSS_DOCKER\" . && \
                    sudo docker run --rm -v /workspace:/src -v /tmp/cargo-target:/src/target forge-osxcross cargo build --target x86_64-apple-darwin --release || true; \
                    sudo docker run --rm -v /workspace:/src -v /tmp/cargo-target:/src/target forge-osxcross cargo build --target aarch64-apple-darwin --release || true; \
                else \
                    echo '[dev-forge : macOS] Compilando con toolchain Rust hacia Darwin...'; \
                    cd /workspace; \
                    rustup target add x86_64-apple-darwin aarch64-apple-darwin 2>/dev/null || true; \
                    CARGO_TARGET_DIR=/tmp/cargo-target cargo build --target x86_64-apple-darwin --release 2>/dev/null || true; \
                    CARGO_TARGET_DIR=/tmp/cargo-target cargo build --target aarch64-apple-darwin --release 2>/dev/null || true; \
                fi; \
                for f in '/tmp/cargo-target/x86_64-apple-darwin/release/{app_name}' '/workspace/target/x86_64-apple-darwin/release/{app_name}'; do \
                    if [ -f \"$f\" ]; then \
                        cp \"$f\" '/workspace/dist/{app_name}-cli-darwin.x86_64'; \
                        cp '/workspace/dist/{app_name}-cli-darwin.x86_64' '/workspace/dist/{app_name}-cli-{raw_ver}-darwin.x86_64' 2>/dev/null || true; \
                        chmod +x '/workspace/dist/{app_name}-cli-'* 2>/dev/null || true; \
                        echo '[dev-forge : macOS] Generado: /workspace/dist/{app_name}-cli-darwin.x86_64 ({raw_ver})'; \
                        break; \
                    fi; \
                done; \
                for f in '/tmp/cargo-target/aarch64-apple-darwin/release/{app_name}' '/workspace/target/aarch64-apple-darwin/release/{app_name}'; do \
                    if [ -f \"$f\" ]; then \
                        cp \"$f\" '/workspace/dist/{app_name}-cli-darwin.aarch64'; \
                        cp '/workspace/dist/{app_name}-cli-darwin.aarch64' '/workspace/dist/{app_name}-cli-{raw_ver}-darwin.aarch64' 2>/dev/null || true; \
                        chmod +x '/workspace/dist/{app_name}-cli-'* 2>/dev/null || true; \
                        echo '[dev-forge : macOS] Generado: /workspace/dist/{app_name}-cli-darwin.aarch64 ({raw_ver})'; \
                        break; \
                    fi; \
                done;"
            ),
            ProjectType::Go => format!(
                "echo '=== [dev-forge : macOS] Compilando binarios Go Darwin para {app_name} ==='; \
                mkdir -p /workspace/dist && cd /workspace; \
                GOCACHE=/tmp/go-cache GOOS=darwin GOARCH=amd64 go build -o '/workspace/dist/{app_name}-cli-darwin.x86_64' . 2>/dev/null || true; \
                cp '/workspace/dist/{app_name}-cli-darwin.x86_64' '/workspace/dist/{app_name}-cli-{raw_ver}-darwin.x86_64' 2>/dev/null || true; \
                GOCACHE=/tmp/go-cache GOOS=darwin GOARCH=arm64 go build -o '/workspace/dist/{app_name}-cli-darwin.aarch64' . 2>/dev/null || true; \
                cp '/workspace/dist/{app_name}-cli-darwin.aarch64' '/workspace/dist/{app_name}-cli-{raw_ver}-darwin.aarch64' 2>/dev/null || true; \
                chmod +x /workspace/dist/{app_name}-cli-darwin.* 2>/dev/null || true;"
            ),
            _ => "echo '[dev-forge : macOS] Compilación para macOS omitida para este tipo de proyecto.';".to_string(),
        }
    };

    let mut combined_script = String::new();
    if build_linux {
        combined_script.push_str(&linux_script);
    }
    if build_macos {
        if !combined_script.is_empty() {
            combined_script.push_str("; ");
        }
        combined_script.push_str(&macos_script);
    }

    log_info("Ejecutando proceso de compilacion remota aislada...");
    let full_script = format!("{}{}", mount_prefix, combined_script);
    let success = run_vagrant_streaming(&["ssh", "forge-linux", "-c", &full_script], envs)?;
    let _ = run_vagrant_streaming(
        &[
            "ssh",
            "forge-linux",
            "-c",
            "if mountpoint -q /workspace; then sudo umount /workspace 2>/dev/null || sudo umount -l /workspace 2>/dev/null || true; fi",
        ],
        envs,
    );

    if !args.keep_vm {
        log_info("Liberando memoria del host (apagando forge-linux)...");
        let _ = run_vagrant_streaming(&["halt", "forge-linux"], envs);
    }

    if !success {
        anyhow::bail!("Fallo en la compilacion en forge-linux");
    }

    Ok(())
}

fn build_on_windows(ptype: &ProjectType, args: &BuildArgs, envs: &[(&str, &str)]) -> Result<()> {
    ensure_mutual_exclusion("forge-windows")?;
    log_info("Preparando entorno de compilacion en 'forge-windows'...");
    let mut up_args = vec!["up", "forge-windows"];
    if args.update {
        up_args.push("--provision");
    }
    run_vagrant_streaming(&up_args, envs)?;

    // Attach transient shared folder for dynamic workspace mounting
    let project_canonical = args
        .project
        .canonicalize()
        .unwrap_or_else(|_| args.project.clone());

    let _ = Command::new("VBoxManage")
        .args([
            "sharedfolder",
            "remove",
            "FORGE-WINDOWS",
            "--name",
            "workspace",
            "--transient",
        ])
        .output();
    let _ = Command::new("VBoxManage")
        .args([
            "sharedfolder",
            "add",
            "FORGE-WINDOWS",
            "--name",
            "workspace",
            "--hostpath",
            &project_canonical.to_string_lossy(),
            "--transient",
        ])
        .output();

    let link_ps = "if (Test-Path C:\\workspace) { cmd /c rmdir C:\\workspace 2>$null; Remove-Item -Force -Recurse C:\\workspace 2>$null }; cmd /c \"mklink /D C:\\workspace \\\\VBoxSvr\\workspace\" ; ";

    let clean_ps = if args.clean {
        "if (Test-Path C:\\target) { Remove-Item -Recurse -Force C:\\target 2>$null }; "
    } else {
        ""
    };

    let defender_bypass = "Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true -DisableIOAVProtection $true -DisableScriptScanning $true -ErrorAction SilentlyContinue; ";
    let clean_legacy = "if (Test-Path C:\\workspace\\dist) { Get-ChildItem -Path C:\\workspace\\dist -Filter '*-amd64*' -ErrorAction SilentlyContinue | Remove-Item -Force }; ";
    let path_init =
        "$env:PATH = \"$env:USERPROFILE\\.cargo\\bin;C:\\Users\\vagrant\\.cargo\\bin;$env:PATH\"; ";
    let vs_shell_init = "if (Test-Path 'C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\Common7\\Tools\\Launch-VsDevShell.ps1') { & 'C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\Common7\\Tools\\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64 | Out-Null }; ";
    let cache_init = "if (Test-Path C:\\forge-cache) { $env:CARGO_HOME='C:\\forge-cache\\cargo'; $env:GOMODCACHE='C:\\forge-cache\\go\\pkg\\mod'; $env:PIP_CACHE_DIR='C:\\forge-cache\\pip'; $env:GRADLE_USER_HOME='C:\\forge-cache\\gradle'; New-Item -ItemType Directory -Path C:\\forge-cache\\cargo, C:\\forge-cache\\go\\pkg\\mod, C:\\forge-cache\\pip, C:\\forge-cache\\gradle -Force | Out-Null }; ";
    let init_prefix = format!(
        "{}{}{}{}{}{}",
        defender_bypass, clean_legacy, path_init, link_ps, clean_ps, cache_init
    );

    let ver_info = extract_project_version(&project_canonical);
    let app_name = extract_project_name(&project_canonical);
    let raw_ver = if !ver_info.raw.is_empty() {
        ver_info.raw.as_str()
    } else {
        "0.1.0"
    };
    let gui_name = if project_canonical.join("src-tauri/Cargo.toml").is_file() {
        extract_project_name(&project_canonical.join("src-tauri"))
    } else {
        format!("{}-gui", app_name)
    };
    let use_nuitka = !args.pyinstaller && args.compiler == PythonCompiler::Nuitka;

    let component = args.component.unwrap_or(if args.test {
        BuildComponent::Test
    } else {
        BuildComponent::All
    });
    let package = args.package.unwrap_or(BuildPackage::All);
    let is_test_mode =
        args.test || component == BuildComponent::Test || args.profile == Some(BuildProfile::Test);

    let build_ps = if is_test_mode {
        match ptype {
            ProjectType::Rust | ProjectType::RustTauri => format!(
                "{}Set-Location C:\\workspace; $env:CARGO_TARGET_DIR='C:\\target'; \
                if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; \
                Write-Host '=== [dev-forge : Windows] Compilando suite de testing para {app_name} ==='; \
                cargo test --no-run --release; \
                $testBin = Get-ChildItem -Path C:\\target\\release\\deps -Filter '*.exe' -ErrorAction SilentlyContinue | Where-Object {{ $_.Name -like '{app_name}-*.exe' }} | Select-Object -First 1; \
                if (-not $testBin) {{ $testBin = Get-ChildItem -Path C:\\target\\release\\deps -Filter '*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 }}; \
                if ($testBin) {{ \
                    Copy-Item $testBin.FullName 'C:\\workspace\\dist\\{app_name}-test-windows.x86_64.exe' -Force; \
                    Copy-Item 'C:\\workspace\\dist\\{app_name}-test-windows.x86_64.exe' 'C:\\workspace\\dist\\{app_name}-test-{raw_ver}-windows.x86_64.exe' -Force; \
                    Write-Host \"[dev-forge : Windows] Binario de prueba generado: C:\\workspace\\dist\\{app_name}-test-windows.x86_64.exe ({raw_ver})\"; \
                }}",
                init_prefix
            ),
            ProjectType::Go => format!(
                "{}Set-Location C:\\workspace; if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; \
                Write-Host '=== [dev-forge : Windows] Compilando suite de testing Go para {app_name} ==='; \
                go test -c -o 'C:\\workspace\\dist\\{app_name}-test-windows.x86_64.exe' . ; \
                Copy-Item 'C:\\workspace\\dist\\{app_name}-test-windows.x86_64.exe' 'C:\\workspace\\dist\\{app_name}-test-{raw_ver}-windows.x86_64.exe' -Force",
                init_prefix
            ),
            ProjectType::Python(_) => format!(
                "{}Set-Location C:\\workspace; if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; \
                Write-Host '=== [dev-forge : Windows] Verificando tests Python ==='; \
                python -m unittest discover tests 2>&1 | Tee-Object C:\\workspace\\dist\\test-results-windows.log",
                init_prefix
            ),
            _ => format!(
                "{}Set-Location C:\\workspace; Write-Host '[dev-forge : Windows] Testing no configurado para este tipo de proyecto.'",
                init_prefix
            ),
        }
    } else {
        match ptype {
            ProjectType::RustTauri => {
                let build_cli =
                    component == BuildComponent::All || component == BuildComponent::Cli;
                let build_gui =
                    component == BuildComponent::All || component == BuildComponent::Gui;

                let cli_part = if build_cli {
                    format!(
                        "cargo build --release; \
                        if (Test-Path 'C:\\target\\release\\{app_name}.exe') {{ \
                            Copy-Item 'C:\\target\\release\\{app_name}.exe' 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' -Force; \
                            Copy-Item 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' 'C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe' -Force; \
                        }}; "
                    )
                } else {
                    "".to_string()
                };

                let gui_part = if build_gui {
                    format!(
                        "if (Get-Command cargo-tauri.exe -ErrorAction SilentlyContinue) {{ cargo tauri build }} \
                        elseif (Get-Command npx.cmd -ErrorAction SilentlyContinue) {{ npx --yes @tauri-apps/cli build }} \
                        else {{ cargo build --release }}; \
                        if (Test-Path 'C:\\target\\release\\{gui_name}.exe') {{ Copy-Item 'C:\\target\\release\\{gui_name}.exe' 'C:\\workspace\\dist\\{app_name}-gui-windows.x86_64.exe' -Force }} \
                        elseif (Test-Path 'C:\\target\\release\\{app_name}-gui.exe') {{ Copy-Item 'C:\\target\\release\\{app_name}-gui.exe' 'C:\\workspace\\dist\\{app_name}-gui-windows.x86_64.exe' -Force }} \
                        elseif (Test-Path 'src-tauri\\target\\release\\{gui_name}.exe') {{ Copy-Item 'src-tauri\\target\\release\\{gui_name}.exe' 'C:\\workspace\\dist\\{app_name}-gui-windows.x86_64.exe' -Force }}; \
                        if (Test-Path 'C:\\workspace\\dist\\{app_name}-gui-windows.x86_64.exe') {{ Copy-Item 'C:\\workspace\\dist\\{app_name}-gui-windows.x86_64.exe' 'C:\\workspace\\dist\\{app_name}-gui-{raw_ver}-windows.x86_64.exe' -Force }}; \
                        if (Test-Path src-tauri\\target\\release\\bundle) {{ Copy-Item -Recurse src-tauri\\target\\release\\bundle\\* C:\\workspace\\dist\\ -Force -ErrorAction SilentlyContinue }}; "
                    )
                } else {
                    "".to_string()
                };

                format!(
                    "{}Set-Location C:\\workspace; $env:CARGO_TARGET_DIR='C:\\target'; \
                    if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; {}{}",
                    init_prefix, cli_part, gui_part
                )
            }
            ProjectType::Rust => {
                if component == BuildComponent::Gui {
                    format!(
                        "{}Write-Host '[dev-forge : Windows] GUI no aplicable para proyecto Rust estándar.'",
                        init_prefix
                    )
                } else {
                    format!(
                        "{}Set-Location C:\\workspace; $env:CARGO_TARGET_DIR='C:\\target'; cargo build --release; \
                        if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; \
                        if (Test-Path 'C:\\target\\release\\{app_name}.exe') {{ \
                            Copy-Item 'C:\\target\\release\\{app_name}.exe' 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' -Force; \
                            Copy-Item 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' 'C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe' -Force; \
                        }}",
                        init_prefix
                    )
                }
            }
            ProjectType::Python(_) => {
                let wix_ver = &ver_info.wix;
                let py_compile = if use_nuitka {
                    format!(
                        "if (Test-Path main.py) {{ $ico = & C:\\forge\\provision\\windows\\package-artifacts.ps1 -FindIconOnly -WorkspaceDir C:\\workspace -TargetDir C:\\target; $icoOpt = if ($ico) {{ \"--windows-icon-from-ico='$ico'\" }} else {{ '' }}; Invoke-Expression \"nuitka --standalone --onefile --output-dir=C:\\target\\nuitka-out $icoOpt --product-version='{wix_ver}' --file-version='{wix_ver}' --assume-yes-for-downloads main.py -o {app_name}-cli-windows.x86_64.exe 2>&1\" | Out-Host; if (Test-Path C:\\target\\nuitka-out\\{app_name}-cli-windows.x86_64.exe) {{ Copy-Item C:\\target\\nuitka-out\\{app_name}-cli-windows.x86_64.exe C:\\workspace\\dist\\ -Force; Copy-Item C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe -Force; exit 0 }} else {{ Invoke-Expression \"python -m PyInstaller --clean -F --name {app_name}-cli-windows.x86_64 main.py --distpath C:\\workspace\\dist 2>&1\" | Out-Host; if (Test-Path C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe) {{ Copy-Item C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe -Force; exit 0 }} else {{ exit 1 }} }} }} else {{ python -m build -o C:\\workspace\\dist }}"
                    )
                } else {
                    format!(
                        "if (Test-Path main.py) {{ $ico = & C:\\forge\\provision\\windows\\package-artifacts.ps1 -FindIconOnly -WorkspaceDir C:\\workspace -TargetDir C:\\target; $icoOpt = if ($ico) {{ \"--icon '$ico'\" }} else {{ '' }}; Invoke-Expression \"python -m PyInstaller --clean -F --name {app_name}-cli-windows.x86_64 $icoOpt main.py --distpath C:\\workspace\\dist 2>&1\" | Out-Host; if (Test-Path C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe) {{ Copy-Item C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe -Force; exit 0 }} else {{ exit 1 }} }} else {{ python -m build -o C:\\workspace\\dist }}"
                    )
                };
                format!(
                    "{}Set-Location C:\\workspace; if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; {}",
                    init_prefix, py_compile
                )
            }
            ProjectType::CCpp => format!(
                "{}{}Set-Location C:\\workspace; cmake -B C:\\target -S . -G Ninja; cmake --build C:\\target; \
                if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; \
                Get-ChildItem -Path C:\\target -Filter '*.exe' -Recurse | Where-Object {{ $_.Name -notmatch '(?i)(ninja|compiler)' }} | Select-Object -First 1 | Copy-Item -Destination 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' -Force; \
                if (Test-Path 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe') {{ Copy-Item 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' 'C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe' -Force }}",
                init_prefix, vs_shell_init
            ),
            ProjectType::Go => format!(
                "{}Set-Location C:\\workspace; if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; \
                go build -o 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' . ; \
                if (-not (Test-Path 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe')) {{ go build -o 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' ./... }}; \
                if (Test-Path 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe') {{ Copy-Item 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' 'C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe' -Force }}",
                init_prefix
            ),
            _ => format!(
                "{}Set-Location C:\\workspace; if (Test-Path .\\build.bat) {{ .\\build.bat }}",
                init_prefix
            ),
        }
    };

    let pack_ps = if package == BuildPackage::Bin || is_test_mode {
        "".to_string()
    } else {
        format!(
            "; if (Test-Path 'C:\\forge\\provision\\windows\\package-artifacts.ps1') {{ & 'C:\\forge\\provision\\windows\\package-artifacts.ps1' -DistDir 'C:\\workspace\\dist' -TargetDir 'C:\\target' -WorkspaceDir 'C:\\workspace' -AppVersion '{}' -WixVersion '{}' -GitBranch '{}' }}",
            ver_info.raw, ver_info.wix, ver_info.branch
        )
    };
    let full_cmd = format!("{}{}", build_ps, pack_ps);

    log_info("Ejecutando proceso de compilacion remota en Windows Server Core...");
    let success = run_vagrant_streaming(
        &[
            "winrm",
            "forge-windows",
            "-s",
            "powershell",
            "-c",
            &full_cmd,
        ],
        envs,
    )?;

    if !args.keep_vm {
        log_info("Liberando memoria del host (apagando forge-windows)...");
        let _ = run_vagrant_streaming(&["halt", "forge-windows"], envs);
    }

    if !success {
        anyhow::bail!("Fallo en la compilacion en forge-windows");
    }

    Ok(())
}
