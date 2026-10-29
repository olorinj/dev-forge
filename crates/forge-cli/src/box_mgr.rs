use crate::terminal::{log_info, log_ok, log_warn};
use crate::vagrant::get_forge_dir;
use anyhow::Result;
use colored::Colorize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub fn resolve_target_repo(explicit_repo: Option<&str>) -> Result<String> {
    if let Some(r) = explicit_repo {
        let trimmed = r.trim();
        if !trimmed.is_empty() {
            return Ok(trimmed.to_string());
        }
    }
    if let Ok(env_repo) = std::env::var("DEVFORGE_GITHUB_REPO") {
        let trimmed = env_repo.trim();
        if !trimmed.is_empty() {
            return Ok(trimmed.to_string());
        }
    }
    if let Ok(env_gh) = std::env::var("GITHUB_REPOSITORY") {
        let trimmed = env_gh.trim();
        if !trimmed.is_empty() {
            return Ok(trimmed.to_string());
        }
    }

    // Intentar deducir desde git remote origin en el repositorio
    let forge_dir = get_forge_dir();
    if let Ok(output) = Command::new("git")
        .args(["remote", "get-url", "origin"])
        .current_dir(&forge_dir)
        .output()
    {
        if output.status.success() {
            let remote_url = String::from_utf8_lossy(&output.stdout).trim().to_string();
            // git@github.com:owner/repo.git o https://github.com/owner/repo.git
            if let Some(idx) = remote_url.find("github.com/") {
                let path = &remote_url[idx + 11..];
                let repo = path.trim_end_matches(".git");
                if repo.contains('/') {
                    return Ok(repo.to_string());
                }
            } else if let Some(idx) = remote_url.find("github.com:") {
                let path = &remote_url[idx + 11..];
                let repo = path.trim_end_matches(".git");
                if repo.contains('/') {
                    return Ok(repo.to_string());
                }
            }
        }
    }

    Ok("olorinj/dev-forge".to_string())
}

pub fn select_best_storage_dir(custom_out: Option<PathBuf>) -> PathBuf {
    if let Some(dir) = custom_out {
        let _ = fs::create_dir_all(&dir);
        return dir;
    }

    let home_boxes = crate::config::get_user_config_dir().join("boxes");
    let repo_boxes = get_forge_dir().join("dist/boxes");

    let _ = fs::create_dir_all(&home_boxes);
    let _ = fs::create_dir_all(&repo_boxes);

    home_boxes
}

pub fn compute_file_sha256(path: &Path) -> Result<String> {
    if let Ok(output) = Command::new("sha256sum").arg(path).output() {
        if output.status.success() {
            let out_str = String::from_utf8_lossy(&output.stdout);
            if let Some(hash) = out_str.split_whitespace().next() {
                return Ok(hash.to_string());
            }
        }
    }
    anyhow::bail!(
        "No se pudo calcular la suma SHA-256 para: {}",
        path.display()
    )
}

pub fn execute_package(machine: &str, version: &str, custom_out: Option<PathBuf>) -> Result<()> {
    let forge_dir = get_forge_dir();
    let out_dir = select_best_storage_dir(custom_out);
    let _ = fs::create_dir_all(&out_dir);

    let targets = if machine == "all" {
        vec!["forge-linux", "forge-windows", "forge-runner"]
    } else {
        match machine {
            "linux" | "forge-linux" => vec!["forge-linux"],
            "windows" | "forge-windows" => vec!["forge-windows"],
            "runner" | "forge-runner" => vec!["forge-runner"],
            other => vec![other],
        }
    };

    for target in targets {
        let vbox_name = match target {
            "forge-linux" => "FORGE-LINUX",
            "forge-windows" => "FORGE-WINDOWS",
            "forge-runner" => "FORGE-RUNNER",
            other => other,
        };

        println!();
        log_info("=========================================================================");
        log_info(&format!(
            "Iniciando empaquetado VDI para: {} ({}) v{}",
            target.cyan().bold(),
            vbox_name,
            version.yellow().bold()
        ));
        log_info("=========================================================================");

        // 1. Iniciar máquina si no está corriendo para ejecutar script de preparación
        log_info(&format!("Verificando estado de {}...", target));
        let running_vms = Command::new("VBoxManage")
            .arg("list")
            .arg("runningvms")
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
            .unwrap_or_default();

        if !running_vms.contains(vbox_name) {
            log_info(&format!(
                "Levantando {} para aplicar optimizaciones...",
                target
            ));
            let status = Command::new("vagrant")
                .arg("up")
                .arg(target)
                .current_dir(&forge_dir)
                .status()?;
            if !status.success() {
                anyhow::bail!("Fallo al levantar la máquina virtual {}", target);
            }
        }

        // 2. Ejecutar script de preparación in-guest
        log_info("Ejecutando script de preparación y hardening in-guest...");
        if target == "forge-windows" {
            let status = Command::new("vagrant")
                .args([
                    "winrm",
                    target,
                    "-s",
                    "powershell",
                    "-c",
                    "powershell.exe -ExecutionPolicy Bypass -NoProfile -File C:\\forge\\scripts\\prep-guest-windows.ps1",
                ])
                .current_dir(&forge_dir)
                .status()?;
            if !status.success() {
                log_warn("Aviso: el script de preparación in-guest de Windows finalizó con advertencias.");
            }
        } else {
            let status = Command::new("vagrant")
                .args([
                    "ssh",
                    target,
                    "-c",
                    "sudo bash /forge/scripts/prep-guest-linux.sh",
                ])
                .current_dir(&forge_dir)
                .status()?;
            if !status.success() {
                log_warn(
                    "Aviso: el script de preparación in-guest de Linux finalizó con advertencias.",
                );
            }
        }

        // 3. Apagado limpio
        log_info(&format!("Apagando limpiamente {}...", target));
        let _ = Command::new("vagrant")
            .args(["halt", target])
            .current_dir(&forge_dir)
            .status();

        // Limpiar clave privada efímera local para empaquetado neutral
        let ephemeral_key = forge_dir.join(format!(
            ".vagrant/machines/{}/virtualbox/private_key",
            target
        ));
        let _ = fs::remove_file(ephemeral_key);

        // 4. Crear Vagrantfile embebido
        let box_filename = format!("dev-forge-{}-v{}.box", target, version);
        let box_filepath = out_dir.join(&box_filename);
        let box_vf_path = out_dir.join(format!("box-Vagrantfile-{}-v{}.rb", target, version));

        let vf_content = if target == "forge-windows" {
            r#"Vagrant.configure("2") do |config|
  config.vm.communicator = "winrm"
  config.winrm.username = "vagrant"
  config.winrm.password = "vagrant"
  config.vm.boot_timeout = 1800
  config.vm.provider "virtualbox" do |vb|
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.customize ["modifyvm", :id, "--audio", "none"]
    vb.customize ["modifyvm", :id, "--groups", "/DEV-FORGE"]
  end
end
"#
        } else {
            r#"Vagrant.configure("2") do |config|
  config.vm.provider "virtualbox" do |vb|
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.customize ["modifyvm", :id, "--audio", "none"]
    vb.customize ["modifyvm", :id, "--groups", "/DEV-FORGE"]
  end
end
"#
        };

        fs::write(&box_vf_path, vf_content)?;

        // 5. vagrant package
        log_info(&format!(
            "Generando box oficial mediante 'vagrant package' en: {}...",
            box_filepath.display()
        ));
        let _ = fs::remove_file(&box_filepath);
        let _ = fs::remove_file(box_filepath.with_extension("box.sha256"));

        let status = Command::new("vagrant")
            .args([
                "package",
                target,
                "--output",
                &box_filepath.to_string_lossy(),
                "--vagrantfile",
                &box_vf_path.to_string_lossy(),
            ])
            .current_dir(&forge_dir)
            .status()?;

        let _ = fs::remove_file(&box_vf_path);

        if !status.success() {
            anyhow::bail!("Error empaquetando la máquina {}", target);
        }

        // 6. Cálculo de suma SHA-256
        log_info("Calculando suma de verificación criptográfica SHA-256...");
        let hash = compute_file_sha256(&box_filepath)?;
        let sha_file = out_dir.join(format!("{}.sha256", box_filename));
        fs::write(&sha_file, format!("{}  {}\n", hash, box_filename))?;

        log_ok(&format!(
            "Box empaquetada con éxito: {} (SHA-256: {})",
            box_filename.green().bold(),
            hash.cyan()
        ));
    }

    Ok(())
}

pub fn execute_rebuild(
    machine: &str,
    version: &str,
    stage: &str,
    skip_test: bool,
    custom_out: Option<PathBuf>,
) -> Result<()> {
    let forge_dir = get_forge_dir();
    let out_dir = select_best_storage_dir(custom_out);
    let _ = fs::create_dir_all(&out_dir);

    let targets = if machine == "all" {
        vec!["forge-linux", "forge-windows", "forge-runner"]
    } else {
        match machine {
            "linux" | "forge-linux" => vec!["forge-linux"],
            "windows" | "forge-windows" => vec!["forge-windows"],
            "runner" | "forge-runner" => vec!["forge-runner"],
            other => vec![other],
        }
    };

    for target in targets {
        let is_windows = target == "forge-windows";
        let sibling = if is_windows {
            "FORGE-LINUX"
        } else {
            "FORGE-WINDOWS"
        };
        let vbox_name = match target {
            "forge-linux" => "FORGE-LINUX",
            "forge-windows" => "FORGE-WINDOWS",
            "forge-runner" => "FORGE-RUNNER",
            other => other,
        };

        println!();
        log_info("=========================================================================");
        log_info(&format!(
            "Iniciando proceso de reconstrucción para: {} (v{}) [Modo: {}]",
            target.cyan().bold(),
            version.yellow().bold(),
            stage.bold()
        ));
        log_info("=========================================================================");

        // 0. Exclusión mutua de RAM
        let running_vms = Command::new("VBoxManage")
            .args(["list", "runningvms"])
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
            .unwrap_or_default();

        if running_vms.contains(sibling) {
            let sibling_name = if is_windows {
                "forge-linux"
            } else {
                "forge-windows"
            };
            log_info(&format!(
                "Deteniendo {} para garantizar memoria suficiente para {}...",
                sibling_name, target
            ));
            let _ = Command::new("vagrant")
                .args(["halt", sibling_name])
                .current_dir(&forge_dir)
                .status();
        }

        if stage != "package-only" {
            // 1. Purga previa absoluta
            log_info("Paso 1: Purga previa absoluta del entorno...");
            let _ = Command::new("vagrant")
                .args(["destroy", target, "-f"])
                .current_dir(&forge_dir)
                .status();

            let all_vms = Command::new("VBoxManage")
                .args(["list", "vms"])
                .output()
                .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
                .unwrap_or_default();

            if all_vms.contains(vbox_name) {
                log_warn(&format!(
                    "Detectada VM {} residual en VirtualBox. Forzando desregistro...",
                    vbox_name
                ));
                let _ = Command::new("VBoxManage")
                    .args(["controlvm", vbox_name, "poweroff"])
                    .status();
                std::thread::sleep(std::time::Duration::from_secs(1));
                let _ = Command::new("VBoxManage")
                    .args(["unregistervm", vbox_name, "--delete"])
                    .status();
            }

            // Limpieza de carpetas huérfanas
            if let Ok(output) = Command::new("VBoxManage")
                .args(["list", "systemproperties"])
                .output()
            {
                let text = String::from_utf8_lossy(&output.stdout);
                for line in text.lines() {
                    if line.contains("Default machine folder") {
                        if let Some(folder) = line.split(':').nth(1) {
                            let p = PathBuf::from(folder.trim());
                            let _ = fs::remove_dir_all(p.join(vbox_name));
                            let _ = fs::remove_dir_all(p.join("DEV-FORGE").join(vbox_name));
                        }
                    }
                }
            }

            // Limpieza de metadatos locales de vagrant
            let _ = fs::remove_dir_all(forge_dir.join(format!(".vagrant/machines/{}", target)));

            // 2. Aprovisionamiento desde upstream
            log_info("Paso 2: Aprovisionamiento limpio desde imagen base upstream con Ansible...");
            let mut up_cmd = Command::new("vagrant");
            up_cmd.args(["up", target, "--provision"]);
            up_cmd.env("FORGE_FORCE_UPSTREAM_BOX", "1");
            up_cmd.current_dir(&forge_dir);
            up_cmd.stdout(Stdio::inherit());
            up_cmd.stderr(Stdio::inherit());

            let status = up_cmd.status()?;
            if !status.success() {
                anyhow::bail!("Fallo en el aprovisionamiento de {}", target);
            }

            if stage == "deploy-only" {
                log_ok(&format!(
                    "Modo 'deploy-only' finalizado. La máquina '{}' permanece levantada y lista para inspección.",
                    target
                ));
                continue;
            }
        }

        // 3. Optimización in-guest
        log_info("Paso 3: Optimización, hardening y zeroing in-guest...");
        if is_windows {
            let status = Command::new("vagrant")
                .args([
                    "winrm",
                    target,
                    "-s",
                    "powershell",
                    "-c",
                    "powershell.exe -ExecutionPolicy Bypass -NoProfile -File C:\\forge\\scripts\\prep-guest-windows.ps1",
                ])
                .current_dir(&forge_dir)
                .status()?;
            if !status.success() {
                log_warn("Aviso durante la optimización in-guest de Windows.");
            }
        } else {
            let status = Command::new("vagrant")
                .args([
                    "ssh",
                    target,
                    "-c",
                    "sudo bash /forge/scripts/prep-guest-linux.sh",
                ])
                .current_dir(&forge_dir)
                .status()?;
            if !status.success() {
                log_warn("Aviso durante la optimización in-guest de Linux.");
            }
        }

        // 4. Empaquetado
        log_info("Paso 4: Empaquetado nativo estándar de la box...");
        execute_package(target, version, Some(out_dir.clone()))?;

        // 5. Registro local en Vagrant
        let canonical_short = target.replace("forge-", "");
        let box_file = out_dir.join(format!("dev-forge-{}-v{}.box", target, version));

        log_info("Paso 5: Registro local de la box en Vagrant...");
        let status = Command::new("vagrant")
            .args([
                "box",
                "add",
                &format!("dev-forge-{}", canonical_short),
                &box_file.to_string_lossy(),
                "--force",
            ])
            .current_dir(&forge_dir)
            .status()?;

        if !status.success() {
            log_warn("No se pudo registrar la box localmente con el tag corto.");
        }

        // 6. Prueba de despliegue limpio
        if !skip_test {
            log_info("Paso 6: Prueba de despliegue limpio y verificación de conectividad...");
            let _ = Command::new("vagrant")
                .args(["destroy", target, "-f"])
                .current_dir(&forge_dir)
                .status();

            let status = Command::new("vagrant")
                .args(["up", target, "--no-provision"])
                .current_dir(&forge_dir)
                .status()?;

            if status.success() {
                log_ok(&format!(
                    "Prueba de despliegue de {} superada con éxito.",
                    target
                ));
                let _ = Command::new("vagrant")
                    .args(["halt", target])
                    .current_dir(&forge_dir)
                    .status();
            } else {
                anyhow::bail!("Fallo en la prueba de despliegue limpio para {}", target);
            }
        }

        log_ok(&format!(
            "Reconstrucción completa de '{}' (v{}) finalizada con éxito.",
            target.green().bold(),
            version
        ));
    }

    Ok(())
}

#[derive(Debug, Clone)]
pub struct PublishOptions {
    pub machine: String,
    pub version: String,
    pub repo_arg: Option<String>,
    pub split_size_mb: u64,
    pub dry_run: bool,
    pub prerelease: bool,
    pub auto_yes: bool,
    pub custom_desc: Option<String>,
    pub box_dir: PathBuf,
}

/// Divide un archivo grande en chunks binarios (.part00, .part01...) si supera split_threshold_bytes
pub fn split_file_if_needed(file_path: &Path, chunk_size_bytes: u64) -> Result<Vec<PathBuf>> {
    use std::io::{Read, Write};

    let metadata = fs::metadata(file_path)?;
    let total_len = metadata.len();

    // Si cabe en un solo chunk, no dividir
    if total_len <= chunk_size_bytes {
        return Ok(vec![file_path.to_path_buf()]);
    }

    let file_stem = file_path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let parent_dir = file_path
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .to_path_buf();

    let mut parts = Vec::new();
    let mut f = fs::File::open(file_path)?;
    let mut part_index = 0;
    let mut buffer = vec![0u8; 8 * 1024 * 1024]; // Buffer de 8MB en streaming

    log_info(&format!(
        "Dividiendo {} ({:.2} MB) en volúmenes de máx {:.2} MB...",
        file_stem.cyan(),
        total_len as f64 / (1024.0 * 1024.0),
        chunk_size_bytes as f64 / (1024.0 * 1024.0)
    ));

    loop {
        let part_filename = format!("{}.part{:02}", file_stem, part_index);
        let part_path = parent_dir.join(&part_filename);
        let mut written_for_this_part: u64 = 0;

        let mut out_file = fs::File::create(&part_path)?;

        while written_for_this_part < chunk_size_bytes {
            let to_read =
                (chunk_size_bytes - written_for_this_part).min(buffer.len() as u64) as usize;
            let n = f.read(&mut buffer[..to_read])?;
            if n == 0 {
                break;
            }
            out_file.write_all(&buffer[..n])?;
            written_for_this_part += n as u64;
        }

        if written_for_this_part > 0 {
            let part_hash = compute_file_sha256(&part_path).unwrap_or_else(|_| "N/A".to_string());
            let sha_file = parent_dir.join(format!("{}.sha256", part_filename));
            let _ = fs::write(&sha_file, format!("{}  {}\n", part_hash, part_filename));

            println!(
                "   -> Generada parte {}: {} ({:.2} MB) [SHA-256: {}]",
                part_index,
                part_filename.green(),
                written_for_this_part as f64 / (1024.0 * 1024.0),
                &part_hash[..12]
            );
            parts.push(part_path);
            part_index += 1;
        }

        if written_for_this_part == 0 || written_for_this_part < chunk_size_bytes {
            break;
        }
    }

    Ok(parts)
}

/// Concatena una lista de partes ordenadas (.part00, .part01...) en un archivo destino final
pub fn join_split_files(parts: &[PathBuf], dest_path: &Path) -> Result<()> {
    use std::io::{Read, Write};

    let mut dest_file = fs::File::create(dest_path)?;
    let mut buffer = vec![0u8; 8 * 1024 * 1024];

    for p in parts {
        let mut src_file = fs::File::open(p)?;
        loop {
            let n = src_file.read(&mut buffer)?;
            if n == 0 {
                break;
            }
            dest_file.write_all(&buffer[..n])?;
        }
    }
    dest_file.flush()?;
    Ok(())
}

pub fn execute_publish(opts: PublishOptions) -> Result<()> {
    let repo = resolve_target_repo(opts.repo_arg.as_deref())?;
    let tag = format!("v{}", opts.version);
    let chunk_limit_bytes = opts.split_size_mb * 1024 * 1024;

    println!();
    log_info("================================================================================");
    log_info("          PLAN DE PUBLICACIÓN EN GITHUB RELEASES");
    log_info("================================================================================");
    println!("{:<14} : {}", "Versión / Tag".bold(), tag.cyan().bold());
    println!("{:<14} : {}", "Repositorio".bold(), repo.yellow().bold());
    println!(
        "{:<14} : {:.2} MB (Límite por chunk para GitHub Releases)",
        "Split Limit".bold(),
        opts.split_size_mb
    );
    println!(
        "{:<14} : {}",
        "Tipo".bold(),
        if opts.prerelease {
            "Pre-release".yellow().bold()
        } else {
            "Official Release".green().bold()
        }
    );
    println!(
        "{:<14} : {}",
        "Simulación".bold(),
        if opts.dry_run {
            "SÍ (--dry-run activo)".magenta().bold()
        } else {
            "NO (Subida real a GitHub)".cyan().bold()
        }
    );
    log_info("--------------------------------------------------------------------------------");

    // Comprobar token o disponibilidad de gh CLI
    let has_gh_cli = Command::new("gh").arg("--version").output().is_ok();
    let gh_token = std::env::var("GITHUB_TOKEN")
        .or_else(|_| std::env::var("GH_TOKEN"))
        .unwrap_or_default();

    if !opts.dry_run && !has_gh_cli && gh_token.is_empty() {
        log_warn(
            "No se detectó el CLI oficial 'gh' ni la variable de entorno GITHUB_TOKEN / GH_TOKEN.",
        );
        log_info("Para realizar la subida a GitHub Releases, puedes:");
        println!("  1. Instalar y autenticar 'gh auth login'");
        println!("  2. O exportar tu token personal: export GITHUB_TOKEN=\"ghp_...\"");
        println!("  3. O ejecutar con '--dry-run' para preparar los paquetes y hashes listos para subida.");
        println!();
        anyhow::bail!("Faltan credenciales de subida a GitHub Releases");
    }

    let targets = if opts.machine == "all" {
        vec!["linux", "windows", "runner"]
    } else {
        match opts.machine.as_str() {
            "linux" | "forge-linux" => vec!["linux"],
            "windows" | "forge-windows" => vec!["windows"],
            "runner" | "forge-runner" => vec!["runner"],
            other => vec![other],
        }
    };

    let mut artifacts_to_upload: Vec<PathBuf> = Vec::new();

    for t in &targets {
        let box_name = format!("dev-forge-{}-v{}.box", t, opts.version);
        let box_path = opts.box_dir.join(&box_name);

        if !box_path.is_file() {
            println!("  ✘ [{}] {}", t.to_uppercase().red().bold(), box_name.red());
            println!(
                "      Error: No se encontró el archivo: {}",
                box_path.display().to_string().red()
            );
            anyhow::bail!(
                "Faltan archivos .box requeridos para la publicación en: {}",
                opts.box_dir.display()
            );
        }

        let metadata = fs::metadata(&box_path)?;
        let size_mb = metadata.len() as f64 / (1024.0 * 1024.0);
        let sha = compute_file_sha256(&box_path).unwrap_or_else(|_| "N/A".to_string());

        println!(
            "  ✔ [{}] {} ({:.2} MB)",
            t.to_uppercase().green().bold(),
            box_name.cyan().bold(),
            size_mb
        );
        println!("      Archivo origen : {}", box_path.display());
        println!("      SHA-256 total  : {}", sha);

        // Guardar o verificar el hash del archivo original
        let sha_file = opts.box_dir.join(format!("{}.sha256", box_name));
        let _ = fs::write(&sha_file, format!("{}  {}\n", sha, box_name));
        artifacts_to_upload.push(sha_file);

        // Si supera el límite de GitHub (ej. 1900 MB), dividir en volúmenes
        let parts = split_file_if_needed(&box_path, chunk_limit_bytes)?;
        if parts.len() == 1 {
            artifacts_to_upload.push(box_path);
        } else {
            for part in parts {
                let part_name = part.file_name().unwrap_or_default().to_string_lossy();
                let part_sha_file = opts.box_dir.join(format!("{}.sha256", part_name));
                artifacts_to_upload.push(part);
                if part_sha_file.is_file() {
                    artifacts_to_upload.push(part_sha_file);
                }
            }
        }
    }

    log_info("================================================================================");
    println!();
    println!(
        "Artefactos preparados para el release de GitHub {}:",
        tag.cyan().bold()
    );
    for a in &artifacts_to_upload {
        let size = fs::metadata(a).map(|m| m.len()).unwrap_or(0);
        println!(
            "  - {:<42} ({:.2} MB)",
            a.file_name().unwrap_or_default().to_string_lossy().green(),
            size as f64 / (1024.0 * 1024.0)
        );
    }
    println!();

    if !opts.auto_yes && !opts.dry_run {
        println!(
            "{}",
            "AVISO: Se publicarán los artefactos anteriores en GitHub Releases."
                .yellow()
                .bold()
        );
        print!(
            "¿Deseas proceder con la publicación oficial en {} ({})? (s/N): ",
            repo.bold(),
            tag.cyan()
        );
        use std::io::Write;
        let _ = std::io::stdout().flush();

        let mut input = String::new();
        std::io::stdin().read_line(&mut input)?;
        if !input.trim().eq_ignore_ascii_case("s") && !input.trim().eq_ignore_ascii_case("y") {
            log_warn("Operación cancelada por el usuario.");
            return Ok(());
        }
    }

    let default_notes = format!(
        "DevForge Pre-baked VirtualBox Boxes Release {}\n\n\
        Contiene imágenes oficiales pre-configuradas con herramientas de desarrollo nativas (Rust, Go, C/C++, Docker, etc.).\n\
        Consumo directo con Vagrant o 'dev-forge box install <linux|windows|runner> --from-github {} --version {}'",
        tag, repo, opts.version
    );
    let release_notes = opts.custom_desc.as_deref().unwrap_or(&default_notes);

    if opts.dry_run {
        log_ok(&format!(
            "[DRY-RUN] Simulación exitosa. Se habrían publicado {} artefactos en {}@{}.",
            artifacts_to_upload.len(),
            repo.cyan().bold(),
            tag.yellow().bold()
        ));
        if has_gh_cli {
            println!("Comando gh equivalente:");
            println!(
                "  gh release create {} {} --repo {} --title \"DevForge Boxes {}\" --notes \"{}\"",
                tag,
                artifacts_to_upload
                    .iter()
                    .map(|p| format!("\"{}\"", p.display()))
                    .collect::<Vec<_>>()
                    .join(" "),
                repo,
                tag,
                release_notes
            );
        }
        return Ok(());
    }

    // Ejecutar subida real
    if has_gh_cli {
        log_info(&format!(
            "Creando o actualizando Release {} en GitHub ({}) vía 'gh'...",
            tag.cyan().bold(),
            repo.yellow().bold()
        ));

        let mut gh_args: Vec<String> = vec![
            "release".to_string(),
            "create".to_string(),
            tag.clone(),
            "--repo".to_string(),
            repo.clone(),
            "--title".to_string(),
            format!("DevForge Boxes {}", tag),
            "--notes".to_string(),
            release_notes.to_string(),
        ];

        if opts.prerelease {
            gh_args.push("--prerelease".to_string());
        }

        for a in &artifacts_to_upload {
            gh_args.push(a.to_string_lossy().to_string());
        }

        let status = Command::new("gh")
            .args(&gh_args)
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status()?;

        if !status.success() {
            log_warn("El release ya podría existir. Intentando adjuntar assets con 'gh release upload'...");
            let mut upload_args: Vec<String> = vec![
                "release".to_string(),
                "upload".to_string(),
                tag.clone(),
                "--repo".to_string(),
                repo.clone(),
                "--clobber".to_string(),
            ];
            for a in &artifacts_to_upload {
                upload_args.push(a.to_string_lossy().to_string());
            }

            let upload_status = Command::new("gh")
                .args(&upload_args)
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status()?;

            if !upload_status.success() {
                anyhow::bail!("Fallo al subir los artefactos al release {} de GitHub", tag);
            }
        }

        log_ok(&format!(
            "Boxes y sumas SHA-256 publicadas con éxito en GitHub Release: https://github.com/{}/releases/tag/{}",
            repo, tag
        ));
    } else {
        log_info("Subiendo mediante API REST HTTPS de GitHub...");
        // Fallback vía curl si gh no está disponible
        let auth_header = format!("Authorization: Bearer {}", gh_token);
        log_info(&format!("Comprobando release {} en GitHub...", tag));

        let release_endpoint = format!("https://api.github.com/repos/{}/releases", repo);
        let create_payload = format!(
            r#"{{"tag_name":"{}","name":"DevForge Boxes {}","body":"{}","prerelease":{}}}"#,
            tag,
            tag,
            release_notes.replace('"', "\\\"").replace('\n', "\\n"),
            opts.prerelease
        );

        let out = Command::new("curl")
            .args([
                "-s",
                "-H",
                &auth_header,
                "-H",
                "Accept: application/vnd.github+json",
                "-H",
                "X-GitHub-Api-Version: 2022-11-28",
                &release_endpoint,
                "-d",
                &create_payload,
            ])
            .output()?;

        let resp_text = String::from_utf8_lossy(&out.stdout);
        let upload_url_base = if let Some(idx) = resp_text.find("upload_url") {
            let slice = &resp_text[idx..];
            let end = slice.find('"').unwrap_or(slice.len());
            slice[..end]
                .split(':')
                .nth(1)
                .unwrap_or("")
                .trim_matches(|c| c == '"' || c == ' ')
        } else {
            ""
        };

        if upload_url_base.is_empty() {
            log_warn(
                "No se pudo obtener el upload_url directo. Verifica permisos de tu GITHUB_TOKEN.",
            );
        } else {
            let clean_upload = upload_url_base.split('{').next().unwrap_or(upload_url_base);
            for a in &artifacts_to_upload {
                let filename = a.file_name().unwrap_or_default().to_string_lossy();
                let upload_url = format!("{}?name={}", clean_upload, filename);
                log_info(&format!("Subiendo asset: {}...", filename));
                let _ = Command::new("curl")
                    .args([
                        "-s",
                        "-X",
                        "POST",
                        "-H",
                        &auth_header,
                        "-H",
                        "Content-Type: application/octet-stream",
                        "--data-binary",
                        &format!("@{}", a.display()),
                        &upload_url,
                    ])
                    .status();
            }
        }

        log_ok(&format!(
            "Publicación completada en GitHub Release: https://github.com/{}/releases/tag/{}",
            repo, tag
        ));
    }

    Ok(())
}

/// Descarga e instala una box directamente desde un GitHub Release
pub fn execute_install_from_github(machine: &str, repo: &str, version: &str) -> Result<()> {
    let tag = if version.starts_with('v') {
        version.to_string()
    } else {
        format!("v{}", version)
    };

    let target_short = machine.replace("forge-", "");
    let base_box_name = format!("dev-forge-{}-{}.box", target_short, tag);
    let forge_dir = get_forge_dir();
    let download_dir = crate::config::get_user_config_dir().join("boxes");
    let _ = fs::create_dir_all(&download_dir);

    let final_box_path = download_dir.join(&base_box_name);

    println!();
    log_info("================================================================================");
    log_info("       INSTALACIÓN DE DEV-FORGE BOX DESDE GITHUB RELEASES");
    log_info("================================================================================");
    println!("{:<14} : {}", "Máquina".bold(), machine.cyan().bold());
    println!("{:<14} : {}", "Repositorio".bold(), repo.yellow().bold());
    println!("{:<14} : {}", "Versión".bold(), tag.bold());
    println!(
        "{:<14} : {}",
        "Destino local".bold(),
        final_box_path.display()
    );
    log_info("--------------------------------------------------------------------------------");

    // Verificar si ya existe un archivo .box completo
    if !final_box_path.is_file() {
        log_info(&format!("Comprobando assets en GitHub Release {}...", tag));
        let single_url = format!(
            "https://github.com/{}/releases/download/{}/{}",
            repo, tag, base_box_name
        );

        // Intentar descargar archivo único primero
        log_info(&format!("Descargando {}...", base_box_name));
        let status = Command::new("curl")
            .args([
                "-f",
                "-L",
                "-o",
                &final_box_path.to_string_lossy(),
                &single_url,
            ])
            .status();

        let single_download_ok = status.map(|s| s.success()).unwrap_or(false);

        if !single_download_ok {
            let _ = fs::remove_file(&final_box_path);
            log_info("El archivo no se encontró como un bloque único; comprobando volúmenes divididos (.part00, .part01...)...");

            let mut downloaded_parts = Vec::new();
            let mut part_idx = 0;

            loop {
                let part_name = format!("{}.part{:02}", base_box_name, part_idx);
                let part_url = format!(
                    "https://github.com/{}/releases/download/{}/{}",
                    repo, tag, part_name
                );
                let part_dest = download_dir.join(&part_name);

                log_info(&format!("Descargando volumen: {}...", part_name));
                let p_status = Command::new("curl")
                    .args(["-f", "-L", "-o", &part_dest.to_string_lossy(), &part_url])
                    .status();

                if let Ok(s) = p_status {
                    if s.success() {
                        downloaded_parts.push(part_dest);
                        part_idx += 1;
                        continue;
                    }
                }
                // Si el primer volumen falla, no existe
                if part_idx == 0 {
                    anyhow::bail!(
                        "No se encontró ni '{}' ni volumen '{}' en el release {} de {}",
                        base_box_name,
                        part_name,
                        tag,
                        repo
                    );
                }
                // Ya no hay más volúmenes
                break;
            }

            log_info(&format!(
                "Ensamblando {} partes descargadas en: {}...",
                downloaded_parts.len(),
                final_box_path.display()
            ));
            join_split_files(&downloaded_parts, &final_box_path)?;
            log_ok("Archivo .box ensamblado exitosamente.");

            // Limpieza de partes temporales
            for p in downloaded_parts {
                let _ = fs::remove_file(p);
            }
        }
    } else {
        log_info("El archivo .box ya existe en caché local.");
    }

    // Registro en Vagrant
    let canonical_tag = format!("olorinj/dev-forge-{}", target_short);
    log_info(&format!(
        "Registrando box en Vagrant como '{}'...",
        canonical_tag.cyan().bold()
    ));

    let vagrant_status = Command::new("vagrant")
        .args([
            "box",
            "add",
            &canonical_tag,
            &final_box_path.to_string_lossy(),
            "--force",
        ])
        .current_dir(&forge_dir)
        .status()?;

    if !vagrant_status.success() {
        anyhow::bail!("Error registrando la box en Vagrant");
    }

    log_ok(&format!(
        "Box '{}' instalada y lista para su uso.",
        canonical_tag.green().bold()
    ));
    println!();
    println!(
        "Puedes iniciarla ejecutando: {}",
        format!("vagrant up forge-{}", target_short).cyan().bold()
    );

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_resolve_target_repo_explicit() {
        let repo = resolve_target_repo(Some("mi-org/mi-repo")).unwrap();
        assert_eq!(repo, "mi-org/mi-repo");
    }

    #[test]
    fn test_resolve_target_repo_env() {
        std::env::set_var("DEVFORGE_GITHUB_REPO", "test-org/dev-forge");
        let repo = resolve_target_repo(None).unwrap();
        assert_eq!(repo, "test-org/dev-forge");
        std::env::remove_var("DEVFORGE_GITHUB_REPO");
    }

    #[test]
    fn test_split_and_join_roundtrip() {
        use std::io::Write;
        let temp_dir = tempfile::tempdir().unwrap();
        let src_file = temp_dir.path().join("test.box");

        // Crear archivo de 5 MB
        let test_data = vec![0x42u8; 5 * 1024 * 1024];
        let mut f = fs::File::create(&src_file).unwrap();
        f.write_all(&test_data).unwrap();
        f.flush().unwrap();

        // Dividir en chunks de 2 MB
        let parts = split_file_if_needed(&src_file, 2 * 1024 * 1024).unwrap();
        assert_eq!(parts.len(), 3); // 2MB + 2MB + 1MB

        // Unir
        let restored_file = temp_dir.path().join("restored.box");
        join_split_files(&parts, &restored_file).unwrap();

        let restored_data = fs::read(&restored_file).unwrap();
        assert_eq!(restored_data.len(), test_data.len());
        assert_eq!(restored_data, test_data);
    }
}
