use crate::cli::{BuildArgs, BuildComponent, BuildPackage, BuildProfile, TargetPlatform};
use colored::Colorize;
use std::io::{self, Write};

/// Prompts an interactive terminal menu allowing the user to select
/// Component, Target OS, Packaging format, and Build Profile.
pub fn prompt_menu(args: &mut BuildArgs) -> io::Result<()> {
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
    println!(
        "Proyecto a procesar: {}",
        args.project.display().to_string().bold()
    );

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
