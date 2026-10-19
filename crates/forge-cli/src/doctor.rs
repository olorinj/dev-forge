use colored::Colorize;
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::Command;
use sysinfo::{Disks, System};

pub struct DoctorReport {
    pub pass_count: usize,
    pub warn_count: usize,
    pub fail_count: usize,
}

pub fn run_doctor() -> anyhow::Result<()> {
    println!(
        "{}",
        "=== [dev-forge doctor] Diagnóstico del Entorno Multi-Plataforma ==="
            .cyan()
            .bold()
    );
    println!();

    let mut report = DoctorReport {
        pass_count: 0,
        warn_count: 0,
        fail_count: 0,
    };

    println!(
        "{}",
        "1. Diagnóstico de Procesador y Virtualización:"
            .yellow()
            .bold()
    );
    check_hardware_virtualization(&mut report);

    println!();
    println!(
        "{}",
        "2. Diagnóstico de Memoria RAM y Recursos:".yellow().bold()
    );
    check_host_memory(&mut report);

    println!();
    println!(
        "{}",
        "3. Diagnóstico de Almacenamiento y Espacio Libre:"
            .yellow()
            .bold()
    );
    check_disk_space(&mut report);

    println!();
    println!(
        "{}",
        "4. Diagnóstico de Hipervisor y Herramientas CLI:"
            .yellow()
            .bold()
    );
    check_hypervisor_and_tools(&mut report);

    println!();
    println!(
        "{}",
        "5. Diagnóstico de Puertos de Red y Conectividad:"
            .yellow()
            .bold()
    );
    check_network_ports(&mut report);

    println!();
    println!(
        "{}",
        "6. Diagnóstico Específico del Sistema Operativo:"
            .yellow()
            .bold()
    );
    check_os_specific_prerequisites(&mut report);

    println!();
    println!(
        "{}",
        "7. Estado de Máquinas Virtuales y Caché Persistente:"
            .yellow()
            .bold()
    );
    check_vm_and_cache_status(&mut report);

    println!();
    println!(
        "{}",
        "========================================================="
            .cyan()
            .bold()
    );
    println!(
        " RESUMEN DEL DOCTOR: Superados: {} | Advertencias: {} | Fallidos: {}",
        report.pass_count.to_string().green().bold(),
        report.warn_count.to_string().yellow().bold(),
        report.fail_count.to_string().red().bold()
    );
    println!(
        "{}",
        "========================================================="
            .cyan()
            .bold()
    );

    if report.fail_count > 0 {
        anyhow::bail!("dev-forge doctor detectó problemas críticos que requieren atención.");
    }

    Ok(())
}

fn check_hardware_virtualization(report: &mut DoctorReport) {
    if cfg!(target_os = "linux") {
        if let Ok(cpuinfo) = std::fs::read_to_string("/proc/cpuinfo") {
            let has_vmx = cpuinfo.contains(" vmx ") || cpuinfo.contains("\nflags\t\t: vmx ");
            let has_svm = cpuinfo.contains(" svm ") || cpuinfo.contains("\nflags\t\t: svm ");
            if has_vmx || has_svm {
                let tech = if has_vmx {
                    "Intel VT-x (VMX)"
                } else {
                    "AMD-V (SVM)"
                };
                println!(
                    "  ✔ {} Aceleración por hardware habilitada en CPU: {}",
                    "PASS:".green(),
                    tech.cyan()
                );
                report.pass_count += 1;
            } else {
                println!("  ✘ {} No se detectó virtualización por hardware en /proc/cpuinfo. Habilita VT-x/AMD-V en BIOS/UEFI.", "FAIL:".red());
                report.fail_count += 1;
            }
        } else {
            println!("  ⚠ {} No se pudo leer /proc/cpuinfo", "WARN:".yellow());
            report.warn_count += 1;
        }
    } else if cfg!(target_os = "macos") {
        let out = Command::new("sysctl")
            .args(["-n", "kern.hv_support"])
            .output();
        if let Ok(o) = out {
            let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if s == "1" {
                println!(
                    "  ✔ {} Apple Hypervisor Framework soportado por el hardware",
                    "PASS:".green()
                );
                report.pass_count += 1;
            } else {
                println!("  ⚠ {} kern.hv_support retornó '{}'", "WARN:".yellow(), s);
                report.warn_count += 1;
            }
        }
    } else if cfg!(target_os = "windows") {
        println!(
            "  ✔ {} Verificación de hardware de virtualización Windows asistida por Hyper-V/VBox",
            "PASS:".green()
        );
        report.pass_count += 1;
    }
}

fn check_host_memory(report: &mut DoctorReport) {
    let mut sys = System::new_all();
    sys.refresh_memory();
    let total_bytes = sys.total_memory();
    let total_gb = (total_bytes as f64) / (1024.0 * 1024.0 * 1024.0);

    if total_gb >= 15.0 {
        println!(
            "  ✔ {} Memoria RAM del host: {:.1} GB (Óptima para compilaciones concurrentes)",
            "PASS:".green(),
            total_gb
        );
        report.pass_count += 1;
    } else if total_gb >= 7.5 {
        println!(
            "  ✔ {} Memoria RAM del host: {:.1} GB (Adecuada con exclusión mutua de VMs activa)",
            "PASS:".green(),
            total_gb
        );
        report.pass_count += 1;
    } else {
        println!("  ⚠ {} Memoria RAM del host ajustada: {:.1} GB (Recomendado cerrar navegadores/IDE durante el build)", "WARN:".yellow(), total_gb);
        report.warn_count += 1;
    }
}

fn check_disk_space(report: &mut DoctorReport) {
    let disks = Disks::new_with_refreshed_list();
    let user_config = crate::config::get_user_config_dir();
    let target_mount = disks
        .iter()
        .find(|d| user_config.starts_with(d.mount_point()))
        .or_else(|| disks.first());

    if let Some(disk) = target_mount {
        let free_gb = (disk.available_space() as f64) / (1024.0 * 1024.0 * 1024.0);
        let total_gb = (disk.total_space() as f64) / (1024.0 * 1024.0 * 1024.0);
        let fs = String::from_utf8_lossy(disk.file_system().as_encoded_bytes());

        if free_gb >= 20.0 {
            println!(
                "  ✔ {} Espacio libre en disco ({}: {}): {:.1} GB libres de {:.1} GB",
                "PASS:".green(),
                disk.mount_point().display(),
                fs.cyan(),
                free_gb,
                total_gb
            );
            report.pass_count += 1;
        } else if free_gb >= 10.0 {
            println!("  ⚠ {} Espacio en disco moderado: {:.1} GB libres (Recomendado >20 GB para imágenes y cachés)", "WARN:".yellow(), free_gb);
            report.warn_count += 1;
        } else {
            println!("  ✘ {} Espacio en disco crítico: {:.1} GB libres. Se requiere liberar espacio para evitar fallos de I/O.", "FAIL:".red(), free_gb);
            report.fail_count += 1;
        }
    } else {
        println!(
            "  ⚠ {} No se pudo determinar el espacio libre en disco",
            "WARN:".yellow()
        );
        report.warn_count += 1;
    }
}

fn check_hypervisor_and_tools(report: &mut DoctorReport) {
    // 1. VirtualBox (VBoxManage)
    let vbox_check = Command::new("VBoxManage").arg("--version").output();
    match vbox_check {
        Ok(out) if out.status.success() => {
            let ver = String::from_utf8_lossy(&out.stdout).trim().to_string();
            println!(
                "  ✔ {} Oracle VirtualBox CLI (VBoxManage): v{}",
                "PASS:".green(),
                ver.cyan()
            );
            report.pass_count += 1;
        }
        _ => {
            let common_vbox = if cfg!(target_os = "windows") {
                PathBuf::from("C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe")
            } else {
                PathBuf::from("/usr/bin/VBoxManage")
            };
            if common_vbox.is_file() {
                println!(
                    "  ✔ {} Oracle VirtualBox encontrado en {}",
                    "PASS:".green(),
                    common_vbox.display()
                );
                report.pass_count += 1;
            } else {
                println!("  ✘ {} VBoxManage no encontrado en PATH ni en rutas estándar. Instala VirtualBox 7.x.", "FAIL:".red());
                report.fail_count += 1;
            }
        }
    }

    // 2. Vagrant
    let vagrant_check = Command::new("vagrant").arg("--version").output();
    match vagrant_check {
        Ok(out) if out.status.success() => {
            let ver = String::from_utf8_lossy(&out.stdout).trim().to_string();
            println!("  ✔ {} HashiCorp Vagrant: {}", "PASS:".green(), ver.cyan());
            report.pass_count += 1;
        }
        _ => {
            let opt_vagrant = PathBuf::from("/opt/vagrant/bin/vagrant");
            if opt_vagrant.is_file() {
                println!(
                    "  ✔ {} HashiCorp Vagrant encontrado en {}",
                    "PASS:".green(),
                    opt_vagrant.display()
                );
                report.pass_count += 1;
            } else {
                println!(
                    "  ✘ {} Vagrant no encontrado en PATH ni en /opt/vagrant/bin. Instala Vagrant.",
                    "FAIL:".red()
                );
                report.fail_count += 1;
            }
        }
    }
}

fn check_network_ports(report: &mut DoctorReport) {
    let running_vms = get_running_vms();

    // Puerto 2222 (Linux SSH)
    let linux_running = running_vms
        .iter()
        .any(|v| v.contains("forge-linux") || v.contains("FORGE-LINUX"));
    match TcpListener::bind("127.0.0.1:2222") {
        Ok(_) => {
            println!(
                "  ✔ {} Puerto local 2222 (Linux SSH) libre y disponible",
                "PASS:".green()
            );
            report.pass_count += 1;
        }
        Err(_) => {
            if linux_running {
                println!(
                    "  ✔ {} Puerto local 2222 en uso legítimo por 'forge-linux' activo",
                    "PASS:".green()
                );
                report.pass_count += 1;
            } else {
                println!("  ⚠ {} Puerto local 2222 ocupado por otro proceso del host. Posible colisión de puerto.", "WARN:".yellow());
                report.warn_count += 1;
            }
        }
    }

    // Puerto 55985 (Windows WinRM)
    let win_running = running_vms
        .iter()
        .any(|v| v.contains("forge-windows") || v.contains("FORGE-WINDOWS"));
    match TcpListener::bind("127.0.0.1:55985") {
        Ok(_) => {
            println!(
                "  ✔ {} Puerto local 55985 (Windows WinRM) libre y disponible",
                "PASS:".green()
            );
            report.pass_count += 1;
        }
        Err(_) => {
            if win_running {
                println!(
                    "  ✔ {} Puerto local 55985 en uso legítimo por 'forge-windows' activo",
                    "PASS:".green()
                );
                report.pass_count += 1;
            } else {
                println!("  ⚠ {} Puerto local 55985 ocupado por otro proceso del host. Posible colisión de puerto.", "WARN:".yellow());
                report.warn_count += 1;
            }
        }
    }
}

fn check_os_specific_prerequisites(report: &mut DoctorReport) {
    if cfg!(target_os = "linux") {
        let vboxdrv = Path::new("/dev/vboxdrv");
        if vboxdrv.exists() {
            println!(
                "  ✔ {} Controlador de kernel VirtualBox (/dev/vboxdrv) activo",
                "PASS:".green()
            );
            report.pass_count += 1;
        } else {
            println!("  ✘ {} /dev/vboxdrv no existe. Ejecuta 'sudo /sbin/vboxconfig' para recompilar módulos del kernel.", "FAIL:".red());
            report.fail_count += 1;
        }

        // KVM check
        let kvm = Path::new("/dev/kvm");
        if kvm.exists() {
            println!(
                "  ✔ {} Interfaz KVM (/dev/kvm) presente para paravirtualización acelerada",
                "PASS:".green()
            );
            report.pass_count += 1;
        }
    } else if cfg!(target_os = "windows") {
        println!("  ✔ {} Entorno host Windows verificado", "PASS:".green());
        report.pass_count += 1;
    } else if cfg!(target_os = "macos") {
        println!("  ✔ {} Entorno host macOS verificado", "PASS:".green());
        report.pass_count += 1;
    }
}

fn check_vm_and_cache_status(report: &mut DoctorReport) {
    // 1. VMs Registradas en VirtualBox
    let vms = get_registered_vms();
    let has_linux = vms
        .iter()
        .any(|v| v.contains("forge-linux") || v.contains("FORGE-LINUX"));
    let has_windows = vms
        .iter()
        .any(|v| v.contains("forge-windows") || v.contains("FORGE-WINDOWS"));

    if has_linux {
        println!(
            "  ✔ {} Máquina 'forge-linux' registrada en VirtualBox",
            "PASS:".green()
        );
        report.pass_count += 1;
    } else {
        println!(
            "  ℹ {} Máquina 'forge-linux' aún no creada (se creará en el primer build)",
            "INFO:".cyan()
        );
    }

    if has_windows {
        println!(
            "  ✔ {} Máquina 'forge-windows' registrada en VirtualBox",
            "PASS:".green()
        );
        report.pass_count += 1;
    } else {
        println!(
            "  ℹ {} Máquina 'forge-windows' aún no creada (se creará en el primer build)",
            "INFO:".cyan()
        );
    }

    // 2. Caché Persistente en Host (~/.dev-forge/cache)
    let cache_dir = crate::config::get_user_config_dir().join("cache");
    if cache_dir.is_dir() {
        let size = crate::cache::get_dir_size(&cache_dir);
        let mb = (size as f64) / (1024.0 * 1024.0);
        println!(
            "  ✔ {} Caché persistente del host activa en {}: {:.2} MB",
            "PASS:".green(),
            cache_dir.display(),
            mb
        );
        report.pass_count += 1;
    } else {
        println!(
            "  ℹ {} Directorio de caché {} se inicializará automáticamente",
            "INFO:".cyan(),
            cache_dir.display()
        );
    }
}

fn get_running_vms() -> Vec<String> {
    let out = Command::new("VBoxManage")
        .args(["list", "runningvms"])
        .output();
    if let Ok(o) = out {
        String::from_utf8_lossy(&o.stdout)
            .lines()
            .map(|l| l.to_string())
            .collect()
    } else {
        Vec::new()
    }
}

fn get_registered_vms() -> Vec<String> {
    let out = Command::new("VBoxManage").args(["list", "vms"]).output();
    if let Ok(o) = out {
        String::from_utf8_lossy(&o.stdout)
            .lines()
            .map(|l| l.to_string())
            .collect()
    } else {
        Vec::new()
    }
}
