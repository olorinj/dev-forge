use crate::cli::{BuildArgs, TargetPlatform};
use crate::project::{detect_project_type, ProjectType, PythonManager};
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

pub fn cmd_build(args: &BuildArgs) -> Result<()> {
    crate::config::load_host_profile()?;

    let project_path = args.project.canonicalize().with_context(|| {
        format!(
            "Ruta de proyecto invalida o no encontrada: {:?}",
            args.project
        )
    })?;

    let ptype = detect_project_type(&project_path);
    let dist_dir = project_path.join("dist");
    std::fs::create_dir_all(&dist_dir)
        .with_context(|| format!("No se pudo crear carpeta dist en {:?}", dist_dir))?;

    log_info(&format!(
        "Proyecto a compilar: {}",
        project_path.display().to_string().bold()
    ));
    log_info(&format!(
        "Tipo de proyecto detectado: {}",
        ptype.to_string().cyan().bold()
    ));
    log_info(&format!(
        "Destino solicitado: {}",
        args.target.to_string().green().bold()
    ));

    let project_str = project_path.to_string_lossy().to_string();
    let envs = [("FORGE_WORKSPACE", project_str.as_str())];

    match args.target {
        TargetPlatform::Linux | TargetPlatform::Macos => {
            build_on_linux(&ptype, args, &envs)?;
        }
        TargetPlatform::Windows => {
            build_on_windows(&ptype, args, &envs)?;
        }
        TargetPlatform::All => {
            build_on_linux(&ptype, args, &envs)?;
            build_on_windows(&ptype, args, &envs)?;
        }
    }

    log_ok(&format!(
        "Compilacion finalizada. Binarios depositados en: {}",
        dist_dir.display().to_string().bold()
    ));

    Ok(())
}

fn build_on_linux(ptype: &ProjectType, args: &BuildArgs, envs: &[(&str, &str)]) -> Result<()> {
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

    let mount_prefix = "sudo mkdir -p /workspace && sudo mount -t vboxsf -o uid=1000,gid=1000,dmode=775,fmode=775 workspace /workspace && source /etc/profile 2>/dev/null || true; export PATH=\"/home/vagrant/.local/bin:$PATH\"; ";

    let clean_cmd = if args.clean {
        "rm -rf /tmp/cargo-target/* /tmp/go-cache/* /tmp/build/* 2>/dev/null || true; "
    } else {
        ""
    };

    let build_script = match ptype {
        ProjectType::RustTauri => format!(
            "{}cd /workspace && cargo tauri build && cp -r src-tauri/target/release/bundle/* /workspace/dist/ 2>/dev/null || true",
            clean_cmd
        ),
        ProjectType::Rust => format!(
            "{}cd /workspace && CARGO_TARGET_DIR=/tmp/cargo-target cargo build --release && cp /tmp/cargo-target/release/$(grep -m1 name Cargo.toml | cut -d'\"' -f2) /workspace/dist/ 2>/dev/null || true",
            clean_cmd
        ),
        ProjectType::Python(details) => match details.manager {
            PythonManager::Uv => format!(
                "{}cd /workspace && if [ -f main.py ]; then pyinstaller --clean -F --name hashforge-py main.py --distpath /workspace/dist/; else uv build --out-dir /workspace/dist/; fi",
                clean_cmd
            ),
            PythonManager::Poetry => format!(
                "{}cd /workspace && if [ -f main.py ]; then pyinstaller --clean -F --name hashforge-py main.py --distpath /workspace/dist/; else poetry build && cp -r dist/* /workspace/dist/; fi",
                clean_cmd
            ),
            PythonManager::Pipenv => format!(
                "{}cd /workspace && if [ -f main.py ]; then pyinstaller --clean -F --name hashforge-py main.py --distpath /workspace/dist/; else pipenv run python3 -m build -o /workspace/dist/; fi",
                clean_cmd
            ),
            PythonManager::Pip => {
                if details.is_multipython {
                    format!("{}cd /workspace && tox", clean_cmd)
                } else {
                    format!(
                        "{}cd /workspace && if [ -f main.py ]; then pyinstaller --clean -F --name hashforge-py main.py --distpath /workspace/dist/; else python3 -m build -o /workspace/dist/ 2>/dev/null || python3 -m pip wheel . -w /workspace/dist/; fi",
                        clean_cmd
                    )
                }
            }
        },
        ProjectType::Java => format!(
            "{}cd /workspace && chmod +x ./gradlew 2>/dev/null || true; (if [ -f ./gradlew ]; then ./gradlew build; elif [ -f pom.xml ]; then mvn package; else gradle build; fi) && find build/libs/ target/ -name '*.jar' ! -name '*-plain.jar' -exec cp {{}} /workspace/dist/ \\; 2>/dev/null || true",
            clean_cmd
        ),
        ProjectType::Go => format!(
            "{}cd /workspace && GOCACHE=/tmp/go-cache go build -o /workspace/dist/hashforge-go . 2>/dev/null || GOCACHE=/tmp/go-cache go build -o /workspace/dist/ .",
            clean_cmd
        ),
        ProjectType::Node => format!(
            "{}cd /workspace && (npm run build || yarn build || pnpm build) && cp -r dist/* build/* /workspace/dist/ 2>/dev/null || true",
            clean_cmd
        ),
        ProjectType::CCpp => format!(
            "{}rm -rf /tmp/build && mkdir -p /tmp/build && cd /workspace && cmake -B /tmp/build -S . -G Ninja && cmake --build /tmp/build && find /tmp/build -maxdepth 2 -type f -executable ! -name '*.ninja*' ! -name '*.cmake' -exec cp {{}} /workspace/dist/ \\; 2>/dev/null || true",
            clean_cmd
        ),
        ProjectType::Generic => format!(
            "{}cd /workspace && if [ -f ./build.sh ]; then bash ./build.sh; elif [ -f ./Makefile ]; then make; fi",
            clean_cmd
        ),
    };

    log_info("Ejecutando proceso de compilacion remota aislada...");
    let full_script = format!("{}{}", mount_prefix, build_script);
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

    let vs_shell_init = "if (Test-Path 'C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\Common7\\Tools\\Launch-VsDevShell.ps1') { & 'C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\Common7\\Tools\\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64 | Out-Null }; ";

    let build_ps = match ptype {
        ProjectType::Rust | ProjectType::RustTauri => format!(
            "{}{}Set-Location C:\\workspace; $env:CARGO_TARGET_DIR='C:\\target'; cargo build --release; if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; Copy-Item C:\\target\\release\\*.exe C:\\workspace\\dist\\ -Force",
            link_ps, clean_ps
        ),
        ProjectType::Python(_) => format!(
            "{}{}Set-Location C:\\workspace; if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; if (Test-Path main.py) {{ python -m PyInstaller --clean -F --name hashforge-py main.py --distpath C:\\workspace\\dist 2>&1 | Out-Host; if (Test-Path C:\\workspace\\dist\\hashforge-py.exe) {{ exit 0 }} else {{ exit 1 }} }} else {{ python -m build -o C:\\workspace\\dist }}",
            link_ps, clean_ps
        ),
        ProjectType::CCpp => format!(
            "{}{}{}Set-Location C:\\workspace; cmake -B C:\\target -S . -G Ninja; cmake --build C:\\target; if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; Get-ChildItem -Path C:\\target -Filter '*.exe' -Recurse | Copy-Item -Destination C:\\workspace\\dist\\ -Force",
            link_ps, clean_ps, vs_shell_init
        ),
        ProjectType::Go => format!(
            "{}{}Set-Location C:\\workspace; if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; go build -o C:\\workspace\\dist\\hashforge-go.exe . ; if (-not (Test-Path C:\\workspace\\dist\\hashforge-go.exe)) {{ go build -o C:\\workspace\\dist\\ . }}",
            link_ps, clean_ps
        ),
        _ => format!(
            "{}{}Set-Location C:\\workspace; if (Test-Path .\\build.bat) {{ .\\build.bat }}",
            link_ps, clean_ps
        ),
    };

    let pack_ps = "; if (Test-Path 'C:\\forge\\provision\\windows\\package-artifacts.ps1') { & 'C:\\forge\\provision\\windows\\package-artifacts.ps1' -DistDir 'C:\\workspace\\dist' -TargetDir 'C:\\target' }";
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
