use clap::{CommandFactory, Parser};
use colored::Colorize;

mod box_mgr;
mod cache;
mod cli;
mod config;
mod doctor;
mod hardware;
mod ide;
mod keyboard;
mod menu;
mod project;
mod terminal;
mod vagrant;

use cli::{Cli, Commands};
use terminal::{log_err, log_info, log_ok, print_banner};

fn main() {
    terminal::init_terminal();
    let cli = Cli::parse();

    // Do not print banner when generating shell completions to keep output pure
    if !matches!(cli.command, Commands::Completions { .. }) {
        print_banner();
    }

    if let Err(err) = run(cli) {
        log_err(&format!("{:#}", err));
        std::process::exit(1);
    }
}

fn run(cli: Cli) -> anyhow::Result<()> {
    match cli.command {
        Commands::Tune => {
            log_info("Detectando recursos del host y evaluando dimensionamiento...");
            let profile = hardware::HostProfile::detect();

            println!("{}", "RECURSOS DEL HOST DETECTADOS:".bold());
            println!("  - Sistema Operativo: {}", profile.os.cyan());
            println!("  - Procesador:        {}", profile.cpu_model.cyan());
            println!(
                "  - Núcleos Físicos:   {} (SMT / HyperThreading: {})",
                profile.physical_cores.to_string().cyan(),
                if profile.smt_active {
                    "ON".cyan()
                } else {
                    "OFF".cyan()
                }
            );
            println!(
                "  - Memoria RAM Total: {} GB",
                profile.total_ram_gb.to_string().cyan()
            );
            println!("  - Teclado Detectado: {}", profile.keyboard.cyan());
            println!("  - Carpeta Almacén:   {}", profile.vbox_folder.cyan());
            println!();

            println!(
                "{}",
                "DIMENSIONAMIENTO ADAPTATIVO APLICADO (Directivas dev-forge):".bold()
            );
            println!(
                "  - vCPUs por VM:      {} vCPUs (50% de cores físicos, ejecución 100%)",
                profile.linux_cpus.to_string().green()
            );
            println!(
                "  - RAM por VM:        {} MB (~{} GB) (33% RAM host)",
                profile.linux_mem_mb.to_string().green(),
                profile.linux_mem_mb / 1024
            );
            println!(
                "  - forge-linux:       {} vCPUs / {} MB (KVM paravirt + virtio-net)",
                profile.linux_cpus.to_string().green(),
                profile.linux_mem_mb.to_string().green()
            );
            println!(
                "  - forge-windows:     {} vCPUs / {} MB (Hyper-V paravirt + virtio-net)",
                profile.windows_cpus.to_string().green(),
                profile.windows_mem_mb.to_string().green()
            );
            println!();

            config::save_host_profile(&profile)?;
            log_ok(&format!(
                "Perfil guardado con éxito en: {}",
                config::get_toml_path().display().to_string().bold()
            ));
            log_ok(&format!(
                "Perfil .env sincronizado en:   {}",
                config::get_env_path().display().to_string().bold()
            ));

            if let Ok(bin_path) = config::install_local_bin() {
                log_ok(&format!(
                    "Acceso global configurado en: {}",
                    bin_path.display().to_string().bold()
                ));
            }

            log_ok("El entorno dev-forge está listo para compilar con rendimiento óptimo.");
        }
        Commands::InstallBin => {
            let bin_path = config::install_local_bin()?;
            log_ok(&format!(
                "dev-forge instalado con éxito para acceso global en: {}",
                bin_path.display().to_string().bold()
            ));
        }
        Commands::Status => {
            vagrant::cmd_status()?;
        }
        Commands::Up { machine, provision } => {
            vagrant::cmd_up(&machine, provision)?;
        }
        Commands::Halt { machine, force } => {
            vagrant::cmd_halt(machine.as_deref(), force)?;
        }
        Commands::Provision { machine } => {
            vagrant::cmd_provision(machine.as_deref())?;
        }
        Commands::Ssh { machine, command } => {
            vagrant::cmd_ssh(&machine, command.as_deref())?;
        }
        Commands::Build(mut build_args) => {
            vagrant::cmd_build(&mut build_args)?;
        }
        Commands::TestVm { machine } => {
            vagrant::cmd_test_vm(&machine)?;
        }
        Commands::Doctor => {
            doctor::run_doctor()?;
        }
        Commands::CleanCache { subsystem } => {
            cache::clean_cache(subsystem.as_deref())?;
        }
        Commands::Ide(args) => {
            ide::run_ide(&args)?;
        }
        Commands::Runner(runner_args) => {
            vagrant::cmd_runner(&runner_args)?;
        }
        Commands::Box { action } => {
            vagrant::cmd_box(&action)?;
        }
        Commands::Completions { shell } => {
            let mut cmd = Cli::command();
            clap_complete::generate(shell, &mut cmd, "dev-forge", &mut std::io::stdout());
        }
    }

    Ok(())
}
