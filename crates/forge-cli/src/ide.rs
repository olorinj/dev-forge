use crate::cli::{IdeArgs, IdeProfile};
use crate::terminal::{log_info, log_ok, log_warn};
use crate::vagrant::{get_forge_dir, run_vagrant_streaming};
use anyhow::{Context, Result};
use colored::Colorize;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn run_ide(args: &IdeArgs) -> Result<()> {
    let machine = &args.machine;
    log_info(&format!(
        "Iniciando sesión de desarrollo remoto en '{}' con perfil '{}'...",
        machine.cyan().bold(),
        args.profile.to_string().green().bold()
    ));

    // 1. Asegurar que la VM está encendida
    log_info(&format!("Verificando estado de '{}'...", machine));
    let forge_dir = get_forge_dir();
    let up_success = run_vagrant_streaming(&["up", machine], &[])?;
    if !up_success {
        anyhow::bail!("No se pudo iniciar la VM '{}'", machine);
    }

    // 2. Extraer configuración SSH de Vagrant
    log_info("Extrayendo configuración SSH de la máquina virtual...");
    let ssh_out = Command::new("vagrant")
        .current_dir(&forge_dir)
        .args(["ssh-config", machine])
        .output()
        .with_context(|| "Fallo al ejecutar 'vagrant ssh-config'")?;

    if !ssh_out.status.success() {
        let err_msg = String::from_utf8_lossy(&ssh_out.stderr);
        anyhow::bail!("Fallo al obtener ssh-config: {}", err_msg);
    }

    let config_raw = String::from_utf8_lossy(&ssh_out.stdout);
    let (hostname, port, user, key_path) = parse_ssh_config(&config_raw)?;

    // 3. Inyectar o actualizar bloque en ~/.ssh/config de forma idempotente
    let host_alias = format!("dev-forge-{}", machine.replace("forge-", ""));
    update_ssh_config(&host_alias, &hostname, &port, &user, &key_path)?;

    // 4. Si se especificó proyecto o directorio actual, inyectar perfil .vscode
    let workspace_path = args.project.clone().unwrap_or_else(|| PathBuf::from("."));
    if workspace_path.is_dir() {
        inject_vscode_profile(&workspace_path, args.profile)?;
    }

    // 5. Lanzar VS Code Remote-SSH o informar
    let remote_uri = format!("vscode-remote://ssh-remote+{}/workspace", host_alias);
    if args.no_launch {
        log_ok(&format!(
            "Configuración SSH registrada como '{}'. Listo para conectar.",
            host_alias.bold()
        ));
        log_info(&format!("URI remota: {}", remote_uri.cyan()));
        return Ok(());
    }

    log_info(&format!(
        "Lanzando VS Code conectando a '{}' (/workspace)...",
        host_alias.cyan()
    ));
    match Command::new("code")
        .args(["--folder-uri", &remote_uri])
        .spawn()
    {
        Ok(_) => {
            log_ok("Sesión de VS Code Remote lanzada exitosamente.");
        }
        Err(_) => {
            log_warn("El comando 'code' no se encuentra en el PATH del sistema host.");
            log_info("Para conectar interactivamente desde VS Code:");
            log_info("  1. Pulsa F1 o Ctrl+Shift+P y escribe 'Remote-SSH: Connect to Host...'");
            log_info(&format!("  2. Selecciona '{}'", host_alias.bold()));
            log_info("  3. Abre la carpeta '/workspace'");
        }
    }

    Ok(())
}

fn parse_ssh_config(raw: &str) -> Result<(String, String, String, String)> {
    let mut hostname = "127.0.0.1".to_string();
    let mut port = "2222".to_string();
    let mut user = "vagrant".to_string();
    let mut key_path = String::new();

    for line in raw.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 2 {
            match parts[0].to_lowercase().as_str() {
                "hostname" => hostname = parts[1].to_string(),
                "port" => port = parts[1].to_string(),
                "user" => user = parts[1].to_string(),
                "identityfile" => key_path = parts[1].trim_matches('"').to_string(),
                _ => {}
            }
        }
    }

    if key_path.is_empty() {
        anyhow::bail!("No se pudo localizar IdentityFile en la salida de 'vagrant ssh-config'");
    }

    Ok((hostname, port, user, key_path))
}

fn update_ssh_config(
    alias: &str,
    hostname: &str,
    port: &str,
    user: &str,
    key_path: &str,
) -> Result<()> {
    let home = std::env::var("HOME").or_else(|_| std::env::var("USERPROFILE"))?;
    let ssh_dir = Path::new(&home).join(".ssh");
    fs::create_dir_all(&ssh_dir)?;

    let config_path = ssh_dir.join("config");
    let existing = if config_path.is_file() {
        fs::read_to_string(&config_path).unwrap_or_default()
    } else {
        String::new()
    };

    let start_tag = format!("# --- dev-forge : {} [auto-generated] ---", alias);
    let end_tag = format!("# --- end dev-forge : {} ---", alias);

    let block = format!(
        "{}\nHost {}\n    HostName {}\n    User {}\n    Port {}\n    IdentityFile {}\n    IdentitiesOnly yes\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null\n    LogLevel ERROR\n{}\n",
        start_tag, alias, hostname, user, port, key_path, end_tag
    );

    let new_content = if existing.contains(&start_tag) && existing.contains(&end_tag) {
        let before = existing.split(&start_tag).next().unwrap_or("");
        let after = existing.split(&end_tag).nth(1).unwrap_or("");
        format!(
            "{}{}{}",
            before.trim_end(),
            if before.is_empty() { "" } else { "\n\n" },
            block
        ) + after.trim_start()
    } else {
        let mut res = existing.trim_end().to_string();
        if !res.is_empty() {
            res.push_str("\n\n");
        }
        res.push_str(&block);
        res
    };

    let mut file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&config_path)?;
    file.write_all(new_content.as_bytes())?;

    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&config_path, fs::Permissions::from_mode(0o600));
    }

    log_ok(&format!(
        "Host SSH '{}' registrado en {}",
        alias.bold(),
        config_path.display()
    ));

    Ok(())
}

fn inject_vscode_profile(workspace: &Path, profile: IdeProfile) -> Result<()> {
    let vscode_dir = workspace.join(".vscode");
    fs::create_dir_all(&vscode_dir)?;

    let (extensions, settings) = get_profile_data(profile);

    let ext_file = vscode_dir.join("extensions.json");
    if !ext_file.exists() {
        let json_ext = format!(
            "{{\n  \"recommendations\": [\n{}\n  ]\n}}\n",
            extensions
                .iter()
                .map(|e| format!("    \"{}\"", e))
                .collect::<Vec<_>>()
                .join(",\n")
        );
        fs::write(&ext_file, json_ext)?;
    }

    let set_file = vscode_dir.join("settings.json");
    if !set_file.exists() {
        let json_set = format!(
            "{{\n{}\n}}\n",
            settings
                .iter()
                .map(|(k, v)| format!("  \"{}\": {}", k, v))
                .collect::<Vec<_>>()
                .join(",\n")
        );
        fs::write(&set_file, json_set)?;
    }

    log_ok(&format!(
        "Perfil '{}' configurado en {}",
        profile.to_string().cyan(),
        vscode_dir.display()
    ));

    Ok(())
}

fn get_profile_data(profile: IdeProfile) -> (Vec<&'static str>, Vec<(&'static str, &'static str)>) {
    let mut exts = Vec::new();
    let mut settings = Vec::new();

    match profile {
        IdeProfile::Rust => {
            exts.extend_from_slice(&[
                "rust-lang.rust-analyzer",
                "tamasfe.even-better-toml",
                "vadimcn.vscode-lldb",
                "tauri-apps.tauri-vscode",
            ]);
            settings.push(("rust-analyzer.check.command", "\"clippy\""));
        }
        IdeProfile::Python => {
            exts.extend_from_slice(&[
                "ms-python.python",
                "charliermarsh.ruff",
                "ms-python.black-formatter",
                "ms-python.flake8",
            ]);
            settings.push(("python.formatting.provider", "\"black\""));
        }
        IdeProfile::Cpp => {
            exts.extend_from_slice(&["ms-vscode.cpptools", "twxs.cmake", "vadimcn.vscode-lldb"]);
        }
        IdeProfile::Web => {
            exts.extend_from_slice(&[
                "dbaeumer.vscode-eslint",
                "esbenp.prettier-vscode",
                "bradlc.vscode-tailwindcss",
            ]);
        }
        IdeProfile::Full => {
            exts.extend_from_slice(&[
                "rust-lang.rust-analyzer",
                "tamasfe.even-better-toml",
                "vadimcn.vscode-lldb",
                "tauri-apps.tauri-vscode",
                "ms-python.python",
                "charliermarsh.ruff",
                "ms-python.black-formatter",
                "ms-vscode.cpptools",
                "twxs.cmake",
            ]);
            settings.push(("rust-analyzer.check.command", "\"clippy\""));
            settings.push(("python.formatting.provider", "\"black\""));
        }
    }

    (exts, settings)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_ssh_config() {
        let sample = "Host forge-linux\n  HostName 127.0.0.1\n  User vagrant\n  Port 2200\n  IdentityFile \"/home/user/.vagrant.d/insecure_private_key\"\n";
        let (host, port, user, key) = parse_ssh_config(sample).unwrap();
        assert_eq!(host, "127.0.0.1");
        assert_eq!(port, "2200");
        assert_eq!(user, "vagrant");
        assert_eq!(key, "/home/user/.vagrant.d/insecure_private_key");
    }
}
