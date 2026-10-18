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
    if toml_path.is_file() {
        let content = std::fs::read_to_string(&toml_path)
            .with_context(|| format!("Failed to read {:?}", toml_path))?;
        let profile: HostProfile = toml::from_str(&content)
            .with_context(|| format!("Failed to parse TOML from {:?}", toml_path))?;
        export_profile_env(&profile);
        return Ok(profile);
    }

    let env_path = get_env_path();
    if env_path.is_file() {
        let profile = parse_env_file(&env_path)?;
        export_profile_env(&profile);
        return Ok(profile);
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
