use crate::hardware::HostProfile;
use anyhow::{Context, Result};
use std::path::PathBuf;

pub fn get_user_config_dir() -> PathBuf {
    if let Ok(dir) = std::env::var("FORGE_USER_CONFIG_DIR") {
        return PathBuf::from(dir);
    }
    if let Some(user_dirs) = directories::UserDirs::new() {
        return user_dirs.home_dir().join(".dev-forge");
    }
    PathBuf::from(".dev-forge")
}

pub fn get_toml_path() -> PathBuf {
    get_user_config_dir().join("config.toml")
}

pub fn get_env_path() -> PathBuf {
    get_user_config_dir().join("forge-host.env")
}

pub fn save_host_profile(profile: &HostProfile) -> Result<()> {
    let config_dir = get_user_config_dir();
    std::fs::create_dir_all(&config_dir)
        .with_context(|| format!("Failed to create config directory at {:?}", config_dir))?;

    // 1. Save Master TOML: ~/.dev-forge/config.toml
    let toml_str =
        toml::to_string_pretty(profile).context("Failed to serialize host profile to TOML")?;
    let toml_path = get_toml_path();
    std::fs::write(&toml_path, toml_str)
        .with_context(|| format!("Failed to write config.toml at {:?}", toml_path))?;

    // Save forge-root.path for global invocation reliability
    let forge_dir = crate::vagrant::get_forge_dir();
    if forge_dir != std::path::Path::new(".") {
        let _ = std::fs::write(
            config_dir.join("forge-root.path"),
            forge_dir.display().to_string(),
        );
    }

    // 2. Synchronize forge-host.env for 100% Vagrantfile compatibility
    let env_content = format!(
        r#"# =============================================================================
# dev-forge : Perfil de Recursos Dimensionados del Host
# Generado automaticamente por: dev-forge tune (Rust Native Orchestrator)
# =============================================================================
FORGE_HOST_PROFILE_VERSION="1.0"
FORGE_HOST_OS="{os}"
FORGE_HOST_CPU_MODEL="{cpu_model}"
FORGE_HOST_PHYSICAL_CORES={phys_cores}
FORGE_HOST_TOTAL_RAM_GB={total_ram}
FORGE_HOST_KEYBOARD="{keyboard}"

# Asignacion de Recursos para Maquinas Virtuales
FORGE_LINUX_CPUS={linux_cpus}
FORGE_LINUX_MEM={linux_mem}
FORGE_WIN_CPUS={win_cpus}
FORGE_WIN_MEM={win_mem}

# Almacenamiento de Discos Virtuales en el Host
FORGE_VBOX_FOLDER="{vbox_folder}"
"#,
        os = profile.os,
        cpu_model = profile.cpu_model,
        phys_cores = profile.physical_cores,
        total_ram = profile.total_ram_gb,
        keyboard = profile.keyboard,
        linux_cpus = profile.linux_cpus,
        linux_mem = profile.linux_mem_mb,
        win_cpus = profile.windows_cpus,
        win_mem = profile.windows_mem_mb,
        vbox_folder = profile.vbox_folder
    );

    let env_path = get_env_path();
    std::fs::write(&env_path, env_content)
        .with_context(|| format!("Failed to write forge-host.env at {:?}", env_path))?;

    Ok(())
}

pub fn load_host_profile() -> Result<HostProfile> {
    let toml_path = get_toml_path();
    let env_path = get_env_path();

    if toml_path.is_file() {
        if let Ok(content) = std::fs::read_to_string(&toml_path) {
            if let Ok(profile) = toml::from_str::<HostProfile>(&content) {
                export_profile_env(&profile);
                return Ok(profile);
            }
            if let Some(profile) = parse_structured_toml(&content) {
                export_profile_env(&profile);
                return Ok(profile);
            }
        }
    }

    if env_path.is_file() {
        if let Ok(profile) = parse_env_file(&env_path) {
            export_profile_env(&profile);
            return Ok(profile);
        }
    }

    // Fallback: check workspace config/forge-host.env
    let ws_env = PathBuf::from("config/forge-host.env");
    if ws_env.is_file() {
        let profile = parse_env_file(&ws_env)?;
        export_profile_env(&profile);
        return Ok(profile);
    }

    anyhow::bail!(
        "El entorno no ha sido dimensionado para este equipo anfitrion.\n\
         Es obligatorio ejecutar primero: dev-forge tune"
    );
}

#[derive(serde::Deserialize)]
struct StructuredToml {
    host: Option<StructuredHost>,
    virtualization: Option<StructuredVirt>,
}

#[derive(serde::Deserialize)]
struct StructuredHost {
    os: Option<String>,
    cpu_model: Option<String>,
    physical_cores: Option<usize>,
    logical_cores: Option<usize>,
    total_ram_mb: Option<u64>,
    total_ram_gb: Option<u64>,
    keyboard: Option<String>,
    vbox_folder: Option<String>,
}

#[derive(serde::Deserialize)]
struct StructuredVirt {
    linux: Option<VmConfig>,
    windows: Option<VmConfig>,
}

#[derive(serde::Deserialize)]
struct VmConfig {
    memory_mb: Option<u64>,
    cpus: Option<usize>,
}

fn parse_structured_toml(content: &str) -> Option<HostProfile> {
    let s: StructuredToml = toml::from_str(content).ok()?;
    let h = s.host.unwrap_or(StructuredHost {
        os: None,
        cpu_model: None,
        physical_cores: None,
        logical_cores: None,
        total_ram_mb: None,
        total_ram_gb: None,
        keyboard: None,
        vbox_folder: None,
    });
    let v_linux = s.virtualization.as_ref().and_then(|v| v.linux.as_ref());
    let v_win = s.virtualization.as_ref().and_then(|v| v.windows.as_ref());

    let physical_cores = h.physical_cores.unwrap_or(4);
    let logical_cores = h.logical_cores.unwrap_or(physical_cores);
    let total_ram_gb = h.total_ram_gb.unwrap_or_else(|| {
        h.total_ram_mb
            .map(|mb| (mb as f64 / 1024.0).round() as u64)
            .unwrap_or(16)
    });

    Some(HostProfile {
        os: h.os.unwrap_or_else(|| "Linux".to_string()),
        cpu_model: h
            .cpu_model
            .unwrap_or_else(|| "Unknown Processor".to_string()),
        physical_cores,
        logical_cores,
        smt_active: logical_cores > physical_cores,
        total_ram_gb,
        keyboard: h.keyboard.unwrap_or_else(|| "es".to_string()),
        vbox_folder: h
            .vbox_folder
            .unwrap_or_else(crate::hardware::detect_optimal_vbox_folder),
        linux_cpus: v_linux.and_then(|l| l.cpus).unwrap_or(2),
        linux_mem_mb: v_linux.and_then(|l| l.memory_mb).unwrap_or(4096),
        windows_cpus: v_win.and_then(|w| w.cpus).unwrap_or(2),
        windows_mem_mb: v_win.and_then(|w| w.memory_mb).unwrap_or(4096),
    })
}

fn parse_env_file(path: &std::path::Path) -> Result<HostProfile> {
    let content =
        std::fs::read_to_string(path).with_context(|| format!("Failed to read {:?}", path))?;

    let mut os = "Linux".to_string();
    let mut cpu_model = "Unknown Processor".to_string();
    let mut physical_cores = 2;
    let mut total_ram_gb = 16;
    let mut keyboard = "es".to_string();
    let mut vbox_folder = "/mnt/data/virtualbox".to_string();
    let mut linux_cpus = 2;
    let mut linux_mem_mb = 5120;
    let mut windows_cpus = 2;
    let mut windows_mem_mb = 5120;

    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') || !line.contains('=') {
            continue;
        }
        let mut parts = line.splitn(2, '=');
        let k = parts.next().unwrap_or("").trim();
        let v = parts
            .next()
            .unwrap_or("")
            .trim()
            .trim_matches('"')
            .trim_matches('\'');

        match k {
            "FORGE_HOST_OS" => os = v.to_string(),
            "FORGE_HOST_CPU_MODEL" => cpu_model = v.to_string(),
            "FORGE_HOST_PHYSICAL_CORES" => physical_cores = v.parse().unwrap_or(2),
            "FORGE_HOST_TOTAL_RAM_GB" => total_ram_gb = v.parse().unwrap_or(16),
            "FORGE_HOST_KEYBOARD" => keyboard = v.to_string(),
            "FORGE_VBOX_FOLDER" => vbox_folder = v.to_string(),
            "FORGE_LINUX_CPUS" => linux_cpus = v.parse().unwrap_or(2),
            "FORGE_LINUX_MEM" => linux_mem_mb = v.parse().unwrap_or(5120),
            "FORGE_WIN_CPUS" => windows_cpus = v.parse().unwrap_or(2),
            "FORGE_WIN_MEM" => windows_mem_mb = v.parse().unwrap_or(5120),
            _ => {}
        }
    }

    Ok(HostProfile {
        os,
        cpu_model,
        physical_cores,
        logical_cores: physical_cores * 2,
        smt_active: true,
        total_ram_gb,
        keyboard,
        vbox_folder,
        linux_cpus,
        linux_mem_mb,
        windows_cpus,
        windows_mem_mb,
    })
}

pub fn export_profile_env(profile: &HostProfile) {
    std::env::set_var("FORGE_HOST_OS", &profile.os);
    std::env::set_var("FORGE_HOST_CPU_MODEL", &profile.cpu_model);
    std::env::set_var(
        "FORGE_HOST_PHYSICAL_CORES",
        profile.physical_cores.to_string(),
    );
    std::env::set_var("FORGE_HOST_TOTAL_RAM_GB", profile.total_ram_gb.to_string());
    std::env::set_var("FORGE_HOST_KEYBOARD", &profile.keyboard);
    std::env::set_var("FORGE_VBOX_FOLDER", &profile.vbox_folder);
    std::env::set_var("FORGE_LINUX_CPUS", profile.linux_cpus.to_string());
    std::env::set_var("FORGE_LINUX_MEM", profile.linux_mem_mb.to_string());
    std::env::set_var("FORGE_WIN_CPUS", profile.windows_cpus.to_string());
    std::env::set_var("FORGE_WIN_MEM", profile.windows_mem_mb.to_string());
}

pub fn get_recent_projects_path() -> PathBuf {
    get_user_config_dir().join("recent_projects.json")
}

pub fn load_recent_projects() -> Vec<PathBuf> {
    let p = get_recent_projects_path();
    let mut projects = Vec::new();
    if let Ok(content) = std::fs::read_to_string(&p) {
        for line in content.lines() {
            let trimmed = line
                .trim()
                .trim_matches(|c| c == '[' || c == ']' || c == ',');
            let trimmed = trimmed.trim();
            if trimmed.starts_with('"') && trimmed.ends_with('"') && trimmed.len() >= 2 {
                let unquoted = &trimmed[1..trimmed.len() - 1];
                let unescaped = unquoted.replace("\\\\", "\\").replace("\\\"", "\"");
                if !unescaped.is_empty() {
                    let pb = PathBuf::from(unescaped);
                    if pb.exists() && !projects.contains(&pb) {
                        projects.push(pb);
                    }
                }
            }
        }
    }
    projects
}

pub fn save_recent_project(path: &std::path::Path) {
    let canonical = match path.canonicalize() {
        Ok(c) => c,
        Err(_) => path.to_path_buf(),
    };
    let mut recents = load_recent_projects();
    recents.retain(|p| p != &canonical);
    recents.insert(0, canonical);
    recents.truncate(5);

    let mut json = String::from("[\n");
    for (i, p) in recents.iter().enumerate() {
        let s = p.display().to_string();
        let escaped = s.replace('\\', "\\\\").replace('"', "\\\"");
        json.push_str(&format!("  \"{}\"", escaped));
        if i + 1 < recents.len() {
            json.push(',');
        }
        json.push('\n');
    }
    json.push_str("]\n");

    let _ = std::fs::create_dir_all(get_user_config_dir());
    let _ = std::fs::write(get_recent_projects_path(), json);
}

pub fn expand_path(raw: &str) -> PathBuf {
    let trimmed = raw.trim();
    if trimmed.starts_with("~/") || trimmed == "~" {
        if let Some(user_dirs) = directories::UserDirs::new() {
            let home = user_dirs.home_dir();
            if trimmed == "~" {
                return home.to_path_buf();
            } else {
                return home.join(&trimmed[2..]);
            }
        }
    }
    PathBuf::from(trimmed)
}

pub fn install_local_bin() -> Result<PathBuf> {
    let local_bin = if let Some(user_dirs) = directories::UserDirs::new() {
        user_dirs.home_dir().join(".local").join("bin")
    } else {
        PathBuf::from("/usr/local/bin")
    };
    std::fs::create_dir_all(&local_bin)?;

    let target_symlink = local_bin.join("dev-forge");
    let current_exe = std::env::current_exe()?;
    let canonical_exe = current_exe.canonicalize().unwrap_or(current_exe);

    #[cfg(unix)]
    {
        use std::os::unix::fs::symlink;
        if target_symlink.is_file() || target_symlink.is_symlink() {
            let _ = std::fs::remove_file(&target_symlink);
        }
        symlink(&canonical_exe, &target_symlink)
            .with_context(|| format!("No se pudo crear symlink en {:?}", target_symlink))?;
    }

    #[cfg(windows)]
    {
        std::fs::copy(&canonical_exe, &target_symlink)?;
    }

    Ok(target_symlink)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_expand_path_relative() {
        let p = expand_path("some/path/project");
        assert_eq!(p, PathBuf::from("some/path/project"));
    }

    #[test]
    fn test_expand_path_home() {
        if let Some(user_dirs) = directories::UserDirs::new() {
            let home = user_dirs.home_dir();
            assert_eq!(expand_path("~"), home.to_path_buf());
            assert_eq!(expand_path("~/workspace"), home.join("workspace"));
        }
    }
}
