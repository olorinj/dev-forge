use colored::Colorize;
use std::path::Path;

pub fn clean_cache(subsystem: Option<&str>) -> anyhow::Result<()> {
    let base_cache = crate::config::get_user_config_dir().join("cache");
    if !base_cache.exists() {
        println!(
            "{}",
            "No existe directorio de caché en ~/.dev-forge/cache (nada que limpiar).".yellow()
        );
        return Ok(());
    }

    let target_dir = match subsystem {
        Some(s) => base_cache.join(s),
        None => base_cache.clone(),
    };

    if !target_dir.exists() {
        println!(
            "El subsistema de caché '{}' no existe o ya está vacío.",
            subsystem.unwrap_or("todos")
        );
        return Ok(());
    }

    let total_bytes = get_dir_size(&target_dir);
    let mb = (total_bytes as f64) / (1024.0 * 1024.0);

    if let Some(s) = subsystem {
        let _ = std::fs::remove_dir_all(&target_dir);
        let _ = std::fs::create_dir_all(&target_dir);
        println!(
            "  ✔ {} Caché del subsistema '{}' purgada con éxito ({:.2} MB liberados)",
            "PASS:".green(),
            s.cyan(),
            mb
        );
    } else {
        let _ = std::fs::remove_dir_all(&target_dir);
        let _ = std::fs::create_dir_all(&target_dir);
        println!(
            "  ✔ {} Caché persistente global purgada con éxito ({:.2} MB liberados)",
            "PASS:".green(),
            mb
        );
    }

    Ok(())
}

pub fn get_dir_size(path: &Path) -> u64 {
    let mut total = 0;
    if let Ok(entries) = std::fs::read_dir(path) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_file() {
                total += entry.metadata().map(|m| m.len()).unwrap_or(0);
            } else if p.is_dir() {
                total += get_dir_size(&p);
            }
        }
    }
    total
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_dir_size_empty() {
        let temp = tempfile::tempdir().unwrap();
        assert_eq!(get_dir_size(temp.path()), 0);
    }

    #[test]
    fn test_get_dir_size_with_files() {
        let temp = tempfile::tempdir().unwrap();
        std::fs::write(temp.path().join("a.txt"), b"12345").unwrap();
        std::fs::write(temp.path().join("b.txt"), b"67890").unwrap();
        assert_eq!(get_dir_size(temp.path()), 10);
    }
}
