"""Cache management and cleaning utilities for dev-forge."""

import shutil
from pathlib import Path
from dev_forge.banner import log_ok, log_warn
from dev_forge.config import get_user_config_dir


def get_dir_size(path: Path) -> int:
    """Calculate total byte size of a directory recursively."""
    total = 0
    if not path.is_dir():
        return 0
    try:
        for entry in path.rglob("*"):
            if entry.is_file():
                try:
                    total += entry.stat().st_size
                except OSError:
                    pass
    except Exception:
        pass
    return total


def clean_cache(subsystem: str | None = None) -> None:
    """Clean persistent compiler cache directory."""
    base_cache = get_user_config_dir() / "cache"
    if not base_cache.exists():
        log_warn("No existe directorio de caché en ~/.dev-forge/cache (nada que limpiar).")
        return

    target_dir = base_cache / subsystem if subsystem else base_cache
    if not target_dir.exists():
        label = subsystem or "todos"
        print(f"El subsistema de caché '{label}' no existe o ya está vacío.")
        return

    total_bytes = get_dir_size(target_dir)
    size_mb = total_bytes / (1024**2)

    try:
        shutil.rmtree(target_dir, ignore_errors=True)
        target_dir.mkdir(parents=True, exist_ok=True)
        if subsystem:
            log_ok(f"Caché del subsistema '{subsystem}' purgada con éxito ({size_mb:.2f} MB liberados)")
        else:
            log_ok(f"Caché persistente global purgada con éxito ({size_mb:.2f} MB liberados)")
    except Exception as e:
        log_warn(f"Error al limpiar caché: {e}")
