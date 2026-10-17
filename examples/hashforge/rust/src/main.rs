mod hash;
mod ui;

use hash::{hash_file, hash_string, HashResult};
use std::env;
use std::process;

fn print_help() {
    println!("HashForge v0.1.0 - Calculador Criptográfico Multiplataforma (dev-forge)");
    println!("\nUSO:");
    println!("  hashforge [OPCIONES]");
    println!("\nOPCIONES:");
    println!("  -s, --string <TEXTO>    Calcula los hashes SHA-256 y MD5 del texto");
    println!("  -f, --file <RUTA>       Calcula los hashes SHA-256 y MD5 del fichero");
    println!("  -j, --json              Formatea la salida en JSON");
    println!("  -g, --gui               Inicia la interfaz gráfica de usuario");
    println!("  -h, --help              Muestra esta ayuda");
    println!("\nEJEMPLOS:");
    println!("  hashforge -s \"dev-forge test\"");
    println!("  hashforge -f Cargo.toml --json");
}

fn print_result(res: &HashResult, json: bool, source_label: &str) {
    if json {
        println!(
            "{{\"source\": \"{}\", \"sha256\": \"{}\", \"md5\": \"{}\"}}",
            source_label, res.sha256, res.md5
        );
    } else {
        println!("==================================================");
        println!("  HashForge v0.1.0 - Resultados de Hashing");
        println!("==================================================");
        println!("  Fuente:  {}", source_label);
        println!("  SHA-256: {}", res.sha256);
        println!("  MD5:     {}", res.md5);
        println!("==================================================");
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();

    let mut string_input: Option<String> = None;
    let mut file_input: Option<String> = None;
    let mut force_gui = false;
    let mut json_mode = false;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-s" | "--string" => {
                if i + 1 < args.len() {
                    string_input = Some(args[i + 1].clone());
                    i += 1;
                } else {
                    eprintln!("Error: -s/--string requiere un argumento.");
                    process::exit(1);
                }
            }
            "-f" | "--file" => {
                if i + 1 < args.len() {
                    file_input = Some(args[i + 1].clone());
                    i += 1;
                } else {
                    eprintln!("Error: -f/--file requiere la ruta del archivo.");
                    process::exit(1);
                }
            }
            "-j" | "--json" => {
                json_mode = true;
            }
            "-g" | "--gui" => {
                force_gui = true;
            }
            "-h" | "--help" => {
                print_help();
                return;
            }
            _ => {
                eprintln!("Opción desconocida: {}", args[i]);
                print_help();
                process::exit(1);
            }
        }
        i += 1;
    }

    if let Some(text) = string_input {
        let res = hash_string(&text);
        print_result(&res, json_mode, &text);
        return;
    }

    if let Some(path) = file_input {
        match hash_file(&path) {
            Ok(res) => print_result(&res, json_mode, &path),
            Err(e) => {
                eprintln!("Error al leer el archivo '{}': {}", path, e);
                process::exit(1);
            }
        }
        return;
    }

    // Si se pasa flag --gui o si no se pasan argumentos
    #[cfg(feature = "gui")]
    {
        // En entornos Linux sin DISPLAY, si no se pidió --gui expresamente, mostramos ayuda
        let has_display = env::var("DISPLAY").is_ok() || env::var("WAYLAND_DISPLAY").is_ok() || cfg!(windows);

        if force_gui || has_display {
            println!("Iniciando interfaz gráfica HashForge...");
            let native_options = eframe::NativeOptions {
                viewport: eframe::egui::ViewportBuilder::default()
                    .with_inner_size([550.0, 420.0])
                    .with_min_inner_size([400.0, 300.0])
                    .with_resizable(true)
                    .with_title("HashForge - dev-forge"),
                ..Default::default()
            };

            let _ = eframe::run_native(
                "HashForge",
                native_options,
                Box::new(|_cc| Ok(Box::new(ui::app::HashForgeApp::default()))),
            );
            return;
        }
    }

    // Fallback CLI si no hay entorno gráfico disponible
    println!("Entorno headless detectado (sin servidor gráfico activo). Ejecutando demostración CLI:\n");
    let sample = "dev-forge test";
    let res = hash_string(sample);
    print_result(&res, json_mode, sample);
    println!("\nPara ver todas las opciones, ejecuta: hashforge --help");
}

