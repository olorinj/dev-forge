use crate::cli::{BuildArgs, BuildComponent, BuildPackage, BuildProfile, TargetPlatform};
use colored::Colorize;
use std::io::{self, Write};

/// Prompts an interactive terminal menu allowing the user to select
/// Component, Target OS, Packaging format, and Build Profile.
pub fn prompt_menu(args: &mut BuildArgs) -> io::Result<()> {
    // 0. Project Selection if None or not provided
    if args.project.is_none() {
        let cwd = std::env::current_dir().unwrap_or_else(|_| std::path::PathBuf::from("."));
        let detected_here = crate::project::detect_project_type(&cwd);
        if detected_here != crate::project::ProjectType::Generic {
            args.project = Some(cwd);
        } else {
            let recents = crate::config::load_recent_projects();
            if !recents.is_empty() {
                println!(
                    "\n{}",
                    "? [0/4] Seleccione el proyecto a compilar:".yellow().bold()
                );
                let mut opt_idx = 1;
                for r in &recents {
                    let default_tag = if opt_idx == 1 {
                        " [Último usado]".dimmed()
                    } else {
                        "".dimmed()
                    };
                    println!(
                        "  [{}] {} {}",
                        opt_idx,
                        r.display().to_string().bold(),
                        default_tag
                    );
                    opt_idx += 1;
                }
                println!("  [{}] Introducir ruta manual...", opt_idx);
                print!(
                    "{}",
                    format!("Opción [1-{}] (Intro para opción 1): ", opt_idx).bold()
                );
                io::stdout().flush()?;

                let mut input = String::new();
                io::stdin().read_line(&mut input)?;
                let trimmed = input.trim();
                let chosen_num: usize = trimmed.parse().unwrap_or(1);
                if chosen_num >= 1 && chosen_num <= recents.len() {
                    args.project = Some(recents[chosen_num - 1].clone());
                } else {
                    print!("{}", "Introduzca la ruta del proyecto: ".bold());
                    io::stdout().flush()?;
                    let mut manual_input = String::new();
                    io::stdin().read_line(&mut manual_input)?;
                    args.project = Some(crate::config::expand_path(manual_input.trim()));
                }
            } else {
                print!(
                    "{}",
                    "? Introduzca la ruta del proyecto a compilar: "
                        .yellow()
                        .bold()
                );
                io::stdout().flush()?;
                let mut manual_input = String::new();
                io::stdin().read_line(&mut manual_input)?;
                args.project = Some(crate::config::expand_path(manual_input.trim()));
            }
        }
    }

    let proj_display = args
        .project
        .as_ref()
        .map(|p| p.display().to_string())
        .unwrap_or_else(|| ".".to_string());

    println!(
        "\n{}",
        "================================================================".cyan()
    );
    println!(
        "{}",
        "       dev-forge : Menú de Compilación Interactivo"
            .cyan()
            .bold()
    );
    println!(
        "{}",
        "================================================================".cyan()
    );
    println!("Proyecto a procesar: {}", proj_display.bold());

    // 1. Component Selection
    if args.component.is_none() && !args.test {
        println!(
            "\n{}",
            "? [1/4] Seleccione el tipo de artefacto a compilar:"
                .yellow()
                .bold()
        );
        println!(
            "  [1] Todos los componentes (CLI + GUI) {}",
            "[Predeterminado]".dimmed()
        );
        println!("  [2] Solo ejecutable CLI");
        println!("  [3] Solo aplicación GUI (Desktop)");
        println!("  [4] Solo ejecutables de Testing / Pruebas (Test runners)");
        print!("{}", "Opción [1-4] (Intro para opción 1): ".bold());
        io::stdout().flush()?;

        let mut input = String::new();
        io::stdin().read_line(&mut input)?;
        match input.trim() {
            "2" => args.component = Some(BuildComponent::Cli),
            "3" => args.component = Some(BuildComponent::Gui),
            "4" => {
                args.component = Some(BuildComponent::Test);
                args.test = true;
            }
            _ => args.component = Some(BuildComponent::All),
        }
    }

    // 2. Target OS Platform Selection
    if args.target.is_none() {
        println!(
            "\n{}",
            "? [2/4] Seleccione el Sistema Operativo destino:"
                .yellow()
                .bold()
        );
        println!(
            "  [1] Todos los sistemas (Linux, Windows, macOS) {}",
            "[Predeterminado]".dimmed()
        );
        println!("  [2] Solo Linux");
        println!("  [3] Solo Windows");
        println!("  [4] Solo macOS");
        print!("{}", "Opción [1-4] (Intro para opción 1): ".bold());
        io::stdout().flush()?;

        let mut input = String::new();
        io::stdin().read_line(&mut input)?;
        match input.trim() {
            "2" => args.target = Some(TargetPlatform::Linux),
            "3" => args.target = Some(TargetPlatform::Windows),
            "4" => args.target = Some(TargetPlatform::Macos),
            _ => args.target = Some(TargetPlatform::All),
        }
    }

    // 3. Packaging format
    if args.package.is_none() {
        println!(
            "\n{}",
            "? [3/4] Seleccione el formato de salida / empaquetado:"
                .yellow()
                .bold()
        );
        println!("  [1] Binarios directos + Paquetes/Instaladores (AppImage, deb, rpm, MSI, Inno, DMG) {}", "[Predeterminado]".dimmed());
        println!("  [2] Solo binarios directos (rápido, sin generadores de instaladores)");
        println!("  [3] Solo paquetes e instaladores");
        print!("{}", "Opción [1-3] (Intro para opción 1): ".bold());
        io::stdout().flush()?;

        let mut input = String::new();
        io::stdin().read_line(&mut input)?;
        match input.trim() {
            "2" => args.package = Some(BuildPackage::Bin),
            "3" => args.package = Some(BuildPackage::Bundle),
            _ => args.package = Some(BuildPackage::All),
        }
    }

    // 4. Build Profile
    if args.profile.is_none() {
        println!(
            "\n{}",
            "? [4/4] Seleccione el modo de compilación:".yellow().bold()
        );
        println!(
            "  [1] Release (Producción, optimizado) {}",
            "[Predeterminado]".dimmed()
        );
        println!("  [2] Testing / Debug (Rápido, con símbolos y aserciones)");
        print!("{}", "Opción [1-2] (Intro para opción 1): ".bold());
        io::stdout().flush()?;

        let mut input = String::new();
        io::stdin().read_line(&mut input)?;
        match input.trim() {
            "2" => args.profile = Some(BuildProfile::Test),
            _ => args.profile = Some(BuildProfile::Release),
        }
    }

    println!(
        "{}\n",
        "----------------------------------------------------------------".dimmed()
    );
    Ok(())
}
