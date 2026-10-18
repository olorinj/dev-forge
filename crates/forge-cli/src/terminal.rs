use colored::Colorize;

/// Initialize Windows console to process ANSI escape codes.
#[cfg(windows)]
pub fn init_terminal() {
    use windows_sys::Win32::System::Console::*;
    unsafe {
        let handle = GetStdHandle(STD_OUTPUT_HANDLE);
        let mut mode: u32 = 0;
        if GetConsoleMode(handle, &mut mode) != 0 {
            SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        }
    }
}

#[cfg(not(windows))]
pub fn init_terminal() {
    // No-op on POSIX systems (Linux / macOS)
}

/// Prints the 7-bit ASCII banner guaranteeing identical rendering on all OSes.
pub fn print_banner() {
    println!(
        "{}",
        "  ================================================================"
            .cyan()
            .bold()
    );
    println!(
        "{}",
        "     ____  _______     __     _____ ___  ____   ____ _____ "
            .cyan()
            .bold()
    );
    println!(
        "{}",
        "    |  _ \\| ____\\ \\   / /    |  ___/ _ \\|  _ \\ / ___| ____|"
            .cyan()
            .bold()
    );
    println!(
        "{}",
        "    | | | |  _|  \\ \\ / /_____| |_ | | | | |_) | |  _|  _|  "
            .cyan()
            .bold()
    );
    println!(
        "{}",
        "    | |_| | |___  \\ V /|_____|  _|| |_| |  _ <| |_| | |___ "
            .cyan()
            .bold()
    );
    println!(
        "{}",
        "    |____/|_____|  \\_/       |_|   \\___/|_| \\_\\\\____|_____|"
            .cyan()
            .bold()
    );
    println!(
        "{}",
        "  ================================================================"
            .cyan()
            .bold()
    );
    println!("       Universal Multi-Language Offline Build Forge\n");
}

pub fn log_info(msg: &str) {
    println!("{} {}", "[dev-forge]".cyan(), msg);
}

pub fn log_ok(msg: &str) {
    println!("{} {}", "[dev-forge : OK]".green(), msg);
}

pub fn log_warn(msg: &str) {
    println!("{} {}", "[dev-forge : AVISO]".yellow(), msg);
}

pub fn log_err(msg: &str) {
    eprintln!("{} {}", "[dev-forge : ERROR]".red(), msg);
}
