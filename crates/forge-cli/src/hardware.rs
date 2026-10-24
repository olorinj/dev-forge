use std::path::Path;
use std::process::Command;
use sysinfo::{Disks, System};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct HostProfile {
    pub os: String,
    pub cpu_model: String,
    pub physical_cores: usize,
    pub logical_cores: usize,
    pub smt_active: bool,
    pub total_ram_gb: u64,
    pub keyboard: String,
    pub vbox_folder: String,

    pub linux_cpus: usize,
    pub linux_mem_mb: u64,
    pub windows_cpus: usize,
    pub windows_mem_mb: u64,
}

impl HostProfile {
    pub fn detect() -> Self {
        let mut sys = System::new_all();
        sys.refresh_all();

        let os = if cfg!(target_os = "windows") {
            "Windows".to_string()
        } else if cfg!(target_os = "macos") {
            "macOS".to_string()
        } else {
            "Linux".to_string()
        };

        let cpu_model = sys
            .cpus()
            .first()
            .map(|c| c.brand().trim().to_string())
            .unwrap_or_else(|| "Unknown Processor".to_string());

        let physical_cores = sys.physical_core_count().unwrap_or(2).max(1);
        let logical_cores = sys.cpus().len().max(physical_cores);
        let smt_active = logical_cores > physical_cores;

        let total_bytes = sys.total_memory();
        let total_ram_gb = ((total_bytes as f64) / (1024.0 * 1024.0 * 1024.0)).round() as u64;

        // Directive 1: 50% physical cores (minimum 2)
        let calc_vcpus = compute_vcpus(physical_cores);

        // Directive 2: Adaptive RAM scale (~33% host RAM, minimum 4096 MB)
        let calc_ram_mb = compute_vm_ram(total_ram_gb);

        let keyboard = crate::keyboard::detect_host_keyboard();
        let vbox_folder = detect_optimal_vbox_folder();

        // Configure VirtualBox default machine folder if vboxmanage is present
        apply_vbox_machinefolder(&vbox_folder);

        Self {
            os,
            cpu_model,
            physical_cores,
            logical_cores,
            smt_active,
            total_ram_gb,
            keyboard,
            vbox_folder,
            linux_cpus: calc_vcpus,
            linux_mem_mb: calc_ram_mb,
            windows_cpus: calc_vcpus,
            windows_mem_mb: calc_ram_mb,
        }
    }
}

pub fn detect_optimal_vbox_folder() -> String {
    // Check for explicit NVMe dedicated partition on Linux
    if cfg!(target_os = "linux") && Path::new("/mnt/data").is_dir() {
        let vdir = Path::new("/mnt/data/virtualbox");
        if std::fs::create_dir_all(vdir).is_ok() {
            return vdir.to_string_lossy().to_string();
        }
    }

    let disks = Disks::new_with_refreshed_list();
    let min_free_bytes: u64 = 40 * 1024 * 1024 * 1024; // 40 GB

    let mut best_mount: Option<String> = None;
    let mut max_free: u64 = 0;
    let sys_mounts = [
        "/bin", "/boot", "/dev", "/etc", "/lib", "/proc", "/root", "/run", "/sbin", "/sys", "/usr",
        "/var",
    ];

    for disk in disks.list() {
        let mount_str = disk.mount_point().to_string_lossy().to_string();
        if sys_mounts
            .iter()
            .any(|&s| mount_str == s || mount_str.starts_with(&format!("{}/", s)))
        {
            continue;
        }
        let available = disk.available_space();
        if available > min_free_bytes && available > max_free {
            max_free = available;
            best_mount = Some(mount_str);
        }
    }

    if let Some(mount) = best_mount {
        if mount != "/" {
            let target = Path::new(&mount).join(if cfg!(target_os = "windows") {
                "VirtualBox VMs"
            } else {
                "virtualbox"
            });
            if std::fs::create_dir_all(&target).is_ok() {
                return target.to_string_lossy().to_string();
            }
        }
    }

    // Default home fallback
    if let Some(home) = directories::UserDirs::new() {
        let target = home.home_dir().join(if cfg!(target_os = "windows") {
            "VirtualBox VMs"
        } else {
            "virtualbox"
        });
        let _ = std::fs::create_dir_all(&target);
        return target.to_string_lossy().to_string();
    }

    if cfg!(target_os = "windows") {
        "C:\\VirtualBox VMs".to_string()
    } else {
        "/tmp/virtualbox".to_string()
    }
}

fn apply_vbox_machinefolder(folder: &str) {
    #[cfg(unix)]
    let _ = Command::new("timeout")
        .args(["2", "VBoxManage", "setproperty", "machinefolder", folder])
        .output();

    #[cfg(not(unix))]
    let _ = Command::new("VBoxManage")
        .args(["setproperty", "machinefolder", folder])
        .output();
}

pub fn compute_vcpus(physical_cores: usize) -> usize {
    std::cmp::max(2, physical_cores / 2)
}

pub fn compute_vm_ram(total_ram_gb: u64) -> u64 {
    match total_ram_gb {
        0..=8 => 3072,
        9..=20 => 4096,   // 16 GB host -> 4096 MB (safe headroom for host)
        21..=40 => 8192,  // 32 GB host -> 8192 MB
        41..=80 => 16384, // 64 GB host -> 16384 MB
        _ => (total_ram_gb * 1024) / 3,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compute_vcpus() {
        assert_eq!(compute_vcpus(1), 2); // Minimum 2 vCPUs
        assert_eq!(compute_vcpus(2), 2);
        assert_eq!(compute_vcpus(4), 2);
        assert_eq!(compute_vcpus(8), 4);
        assert_eq!(compute_vcpus(16), 8);
        assert_eq!(compute_vcpus(32), 16);
    }

    #[test]
    fn test_compute_vm_ram() {
        assert_eq!(compute_vm_ram(4), 3072);
        assert_eq!(compute_vm_ram(8), 3072);
        assert_eq!(compute_vm_ram(16), 4096);
        assert_eq!(compute_vm_ram(32), 8192);
        assert_eq!(compute_vm_ram(64), 16384);
        assert_eq!(compute_vm_ram(128), (128 * 1024) / 3);
    }
}
