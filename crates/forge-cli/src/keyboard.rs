use std::process::Command;

/// Detects the host keyboard layout code, normalized for VM guest injection.
pub fn detect_host_keyboard() -> String {
    #[cfg(target_os = "linux")]
    {
        if let Ok(output) = Command::new("localectl").arg("status").output() {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines() {
                    if line.contains("X11 Layout:") {
                        if let Some(val) = line.split(':').nth(1) {
                            let layout = val.trim().split(',').next().unwrap_or("").trim();
                            if !layout.is_empty() {
                                return layout.to_string();
                            }
                        }
                    }
                }
            }
        }

        if let Ok(content) = std::fs::read_to_string("/etc/default/keyboard") {
            for line in content.lines() {
                if line.starts_with("XKBLAYOUT=") {
                    let val = line
                        .trim_start_matches("XKBLAYOUT=")
                        .trim_matches('"')
                        .trim_matches('\'');
                    let layout = val.split(',').next().unwrap_or("").trim();
                    if !layout.is_empty() {
                        return layout.to_string();
                    }
                }
            }
        }
    }

    #[cfg(target_os = "macos")]
    {
        if let Ok(output) = Command::new("defaults")
            .args([
                "read",
                "~/Library/Preferences/com.apple.HIToolbox.plist",
                "AppleSelectedInputSources",
            ])
            .output()
        {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout).to_lowercase();
                if stdout.contains("spanish") || stdout.contains("español") {
                    return "es".to_string();
                } else if stdout.contains("latin") || stdout.contains("latam") {
                    return "latam".to_string();
                } else if stdout.contains("british") || stdout.contains("uk") {
                    return "gb".to_string();
                } else if stdout.contains("french") || stdout.contains("français") {
                    return "fr".to_string();
                } else if stdout.contains("german") || stdout.contains("deutsch") {
                    return "de".to_string();
                } else if stdout.contains("italian") || stdout.contains("italiano") {
                    return "it".to_string();
                } else if stdout.contains("portuguese") {
                    return "pt".to_string();
                } else if stdout.contains("u.s.") || stdout.contains("us") {
                    return "us".to_string();
                }
            }
        }
    }

    #[cfg(target_os = "windows")]
    {
        if let Ok(output) = Command::new("powershell")
            .args([
                "-NoProfile",
                "-Command",
                "(Get-WinUserLanguageList)[0].LanguageTag",
            ])
            .output()
        {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !stdout.is_empty() {
                    return stdout;
                }
            }
        }
    }

    if let Ok(lang) = std::env::var("LANG") {
        let code = lang.split('_').next().unwrap_or("").to_lowercase();
        if !code.is_empty() {
            return code;
        }
    }

    "es".to_string()
}
