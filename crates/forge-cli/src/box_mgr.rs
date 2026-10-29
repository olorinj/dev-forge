use crate::terminal::{log_err, log_info, log_ok, log_warn};
use crate::vagrant::get_forge_dir;
use anyhow::Result;
use colored::Colorize;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub fn resolve_target_org(explicit_user: Option<&str>) -> Result<String> {
    if let Some(u) = explicit_user {
        if !u.trim().is_empty() {
            return Ok(u.trim().to_string());
        }
    }
    if let Ok(env_org) = std::env::var("DEVFORGE_BOX_ORG") {
        if !env_org.trim().is_empty() {
            return Ok(env_org.trim().to_string());
        }
    }
    if let Ok(env_user) = std::env::var("VAGRANT_CLOUD_USER") {
        if !env_user.trim().is_empty() {
            return Ok(env_user.trim().to_string());
        }
    }
    anyhow::bail!(
        "No se ha especificado el usuario u organización de Vagrant Cloud.\n\
        Proporciónalo mediante el argumento '--user <organizacion>', o definiendo la variable de entorno DEVFORGE_BOX_ORG o VAGRANT_CLOUD_USER."
    )
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
    pub user_arg: Option<String>,
    pub dry_run: bool,
    pub release: bool,
    pub auto_yes: bool,
    pub custom_desc: Option<String>,
    pub box_dir: PathBuf,
}

pub fn execute_publish(opts: PublishOptions) -> Result<()> {
    let org = resolve_target_org(opts.user_arg.as_deref())?;

    println!();
    log_info("================================================================================");
    log_info("          PLAN DE PUBLICACIÓN EN VAGRANT CLOUD (app.vagrantup.com)");
    log_info("================================================================================");
    println!("{:<14} : v{}", "Versión".bold(), opts.version.cyan().bold());
    println!("{:<14} : {}", "Organización".bold(), org.yellow().bold());
    println!(
        "{:<14} : {}",
        "Estado".bold(),
        if opts.release {
            "Release (Pública activa)".green().bold()
        } else {
            "Draft (Borrador)".yellow().bold()
        }
    );
    println!(
        "{:<14} : {}",
        "Simulación".bold(),
        if opts.dry_run {
            "SÍ (--dry-run activo)".magenta().bold()
        } else {
            "NO (Subida real)".cyan().bold()
        }
    );
    log_info("--------------------------------------------------------------------------------");

    // Verificación de credenciales
    if !opts.dry_run {
        log_info("Comprobando credenciales en Vagrant Cloud...");
        let whoami = Command::new("vagrant")
            .args(["cloud", "auth", "whoami"])
            .output()
            .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
            .unwrap_or_default();

        let has_env_token = std::env::var("VAGRANT_CLOUD_TOKEN")
            .map(|t| !t.trim().is_empty())
            .unwrap_or(false);

        if !has_env_token && whoami.contains("You are not logged in") {
            log_err("No has iniciado sesión en Vagrant Cloud.");
            println!();
            println!("Por favor, autentícate ejecutando:");
            println!("    {}", "vagrant cloud auth login".cyan().bold());
            println!(
                "o define la variable de entorno {} antes de continuar.",
                "VAGRANT_CLOUD_TOKEN".yellow().bold()
            );
            println!();
            anyhow::bail!("Falta autenticación de Vagrant Cloud");
        }
        log_ok("Autenticación verificada con éxito.");
    } else {
        log_warn("[DRY-RUN] Omitiendo validación estricta de sesión de red.");
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

    let mut files_to_publish = Vec::new();

    for t in &targets {
        let box_name = format!("dev-forge-{}-v{}.box", t, opts.version);
        let box_path = opts.box_dir.join(&box_name);
        let tag = format!("{}/dev-forge-{}", org, t);

        if box_path.is_file() {
            let metadata = fs::metadata(&box_path)?;
            let size_mb = metadata.len() as f64 / (1024.0 * 1024.0);
            let sha = compute_file_sha256(&box_path).unwrap_or_else(|_| "N/A".to_string());

            println!(
                "  ✔ [{}] {} ({:.2} MB)",
                t.to_uppercase().green().bold(),
                tag.cyan().bold(),
                size_mb
            );
            println!("      Archivo : {}", box_path.display());
            println!("      SHA-256 : {}", sha);
            files_to_publish.push((t.to_string(), tag, box_path, sha));
        } else {
            println!("  ✘ [{}] {}", t.to_uppercase().red().bold(), tag.red());
            println!(
                "      Error: No se encontró el archivo: {}",
                box_path.display().to_string().red()
            );
            anyhow::bail!(
                "Faltan archivos .box requeridos para la publicación en: {}",
                opts.box_dir.display()
            );
        }
    }

    log_info("================================================================================");
    println!();

    if !opts.auto_yes && !opts.dry_run {
        println!(
            "{}",
            "AVISO: La subida de boxes transferirá varios gigabytes hacia Vagrant Cloud."
                .yellow()
                .bold()
        );
        print!(
            "¿Deseas proceder con la publicación oficial de la versión v{}? (s/N): ",
            opts.version
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

    for (target_name, tag, box_path, _) in files_to_publish {
        let default_desc = match target_name.as_str() {
            "linux" => "DevForge Linux Native Build Box (Debian 12 + Rust/Go/Node/Java/Docker/VDI). Pre-baked toolchains, zero auto-updates.",
            "windows" => "DevForge Windows Native Build Box (Windows Server 2022 Core + MSVC/WiX/Inno/Python3.14/uv/Poetry). Pre-baked toolchains.",
            "runner" => "DevForge CI/CD Runner Box (Debian 12 + Docker Engine + GitLab Runner CLI). Entorno local aislado para pipelines.",
            _ => "DevForge Custom Build Box",
        };

        let desc = opts.custom_desc.as_deref().unwrap_or(default_desc);
        let version_desc = format!(
            "DevForge {} Box Release v{}: Pre-baked standalone toolchains, zero auto-updates.",
            target_name, opts.version
        );

        let mut args: Vec<String> = vec![
            "cloud".to_string(),
            "publish".to_string(),
            tag.clone(),
            opts.version.clone(),
            "virtualbox".to_string(),
            box_path.to_string_lossy().to_string(),
            "--description".to_string(),
            desc.to_string(),
            "--version-description".to_string(),
            version_desc,
        ];

        if opts.release {
            args.push("--release".to_string());
        }
        if opts.auto_yes {
            args.push("--force".to_string());
        }

        if opts.dry_run {
            log_ok(&format!(
                "[DRY-RUN] Simulación de subida exitosa para: {}",
                tag.cyan().bold()
            ));
            log_info(&format!("Comando a ejecutar: vagrant {}", args.join(" ")));
        } else {
            log_info(&format!(
                "Subiendo {} a Vagrant Cloud (esto puede tardar varios minutos)...",
                tag.cyan().bold()
            ));
            let status = Command::new("vagrant")
                .args(&args)
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .status()?;

            if !status.success() {
                anyhow::bail!("Fallo en la publicación de la box {}", tag);
            }
            log_ok(&format!(
                "Box '{}' publicada con éxito en Vagrant Cloud.",
                tag.green().bold()
            ));
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_resolve_target_org_explicit() {
        let org = resolve_target_org(Some("mi-org")).unwrap();
        assert_eq!(org, "mi-org");
    }

    #[test]
    fn test_resolve_target_org_env() {
        std::env::set_var("DEVFORGE_BOX_ORG", "test-corp");
        let org = resolve_target_org(None).unwrap();
        assert_eq!(org, "test-corp");
        std::env::remove_var("DEVFORGE_BOX_ORG");
    }

    #[test]
    fn test_resolve_target_org_fails_if_empty() {
        std::env::remove_var("DEVFORGE_BOX_ORG");
        std::env::remove_var("VAGRANT_CLOUD_USER");
        assert!(resolve_target_org(None).is_err());
    }
}
