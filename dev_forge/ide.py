"""VS Code Remote-SSH configuration and programming profiles orchestrator."""

import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional, Tuple
from dev_forge.banner import log_err, log_info, log_ok, log_warn
from dev_forge.vagrant import get_forge_dir, run_vagrant_streaming


def cmd_ide(
    machine: str = "forge-linux",
    profile: str = "full",
    project: Optional[Path] = None,
    no_launch: bool = False,
) -> None:
    """Configure SSH and optionally launch VS Code Remote-SSH into VM."""
    log_info(f"Iniciando sesión de desarrollo remoto en '{machine}' con perfil '{profile}'...")

    # 1. Asegurar que la VM está encendida
    log_info(f"Verificando estado de '{machine}'...")
    up_success = run_vagrant_streaming(["up", machine])
    if not up_success:
        log_err(f"No se pudo iniciar la VM '{machine}'")
        sys.exit(1)

    # 2. Extraer configuración SSH de Vagrant
    log_info("Extrayendo configuración SSH de la máquina virtual...")
    res = subprocess.run(
        ["vagrant", "ssh-config", machine],
        cwd=get_forge_dir(),
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode != 0:
        log_err(f"Fallo al obtener ssh-config: {res.stderr}")
        sys.exit(1)

    hostname, port, user, key_path = parse_ssh_config(res.stdout)

    # 3. Inyectar o actualizar bloque en ~/.ssh/config
    alias_clean = machine.replace("forge-", "")
    host_alias = f"dev-forge-{alias_clean}"
    update_ssh_config(host_alias, hostname, port, user, key_path)

    # 4. Inyectar perfil .vscode en proyecto si existe
    target_project = project or Path.cwd()
    if target_project.is_dir():
        inject_vscode_profile(target_project, profile)

    remote_uri = f"vscode-remote://ssh-remote+{host_alias}/workspace"

    if no_launch:
        log_ok(f"Configuración SSH registrada como '{host_alias}'. Listo para conectar.")
        log_info(f"URI remota: {remote_uri}")
        return

    log_info(f"Lanzando VS Code conectando a '{host_alias}' (/workspace)...")
    code_bin = shutil.which("code")
    if code_bin:
        subprocess.Popen([code_bin, "--folder-uri", remote_uri])
        log_ok("Sesión de VS Code Remote lanzada exitosamente.")
    else:
        log_warn("El comando 'code' no se encuentra en el PATH del sistema host.")
        log_info("Para conectar interactivamente desde VS Code:")
        log_info("  1. Pulsa F1 o Ctrl+Shift+P y escribe 'Remote-SSH: Connect to Host...'")
        log_info(f"  2. Selecciona '{host_alias}'")
        log_info("  3. Abre la carpeta '/workspace'")


def parse_ssh_config(raw: str) -> Tuple[str, str, str, str]:
    """Parse output from vagrant ssh-config."""
    hostname = "127.0.0.1"
    port = "2222"
    user = "vagrant"
    key_path = ""

    for line in raw.splitlines():
        parts = line.strip().split(maxsplit=1)
        if len(parts) == 2:
            key, val = parts[0].lower(), parts[1].strip('"')
            if key == "hostname":
                hostname = val
            elif key == "port":
                port = val
            elif key == "user":
                user = val
            elif key == "identityfile":
                key_path = val

    return hostname, port, user, key_path


def update_ssh_config(
    alias: str,
    hostname: str,
    port: str,
    user: str,
    key_path: str,
) -> None:
    """Idempotently add or update host block in ~/.ssh/config."""
    home = Path(os.environ.get("HOME") or os.environ.get("USERPROFILE") or ".")
    ssh_dir = home / ".ssh"
    ssh_dir.mkdir(parents=True, exist_ok=True)

    config_path = ssh_dir / "config"
    existing = config_path.read_text(encoding="utf-8") if config_path.is_file() else ""

    start_tag = f"# --- dev-forge : {alias} [auto-generated] ---"
    end_tag = f"# --- end dev-forge : {alias} ---"

    block = (
        f"{start_tag}\n"
        f"Host {alias}\n"
        f"    HostName {hostname}\n"
        f"    User {user}\n"
        f"    Port {port}\n"
        f"    IdentityFile {key_path}\n"
        f"    IdentitiesOnly yes\n"
        f"    StrictHostKeyChecking no\n"
        f"    UserKnownHostsFile /dev/null\n"
        f"    LogLevel ERROR\n"
        f"{end_tag}\n"
    )

    if start_tag in existing and end_tag in existing:
        before = existing.split(start_tag)[0].rstrip()
        after = existing.split(end_tag)[1].lstrip()
        prefix = f"{before}\n\n" if before else ""
        new_content = f"{prefix}{block}{after}"
    else:
        new_content = f"{existing.rstrip()}\n\n{block}" if existing.strip() else block

    config_path.write_text(new_content, encoding="utf-8")
    try:
        os.chmod(config_path, 0o600)
    except Exception:
        pass

    log_ok(f"Host SSH '{alias}' registrado en {config_path}")


def inject_vscode_profile(workspace: Path, profile: str) -> None:
    """Inject extensions.json and settings.json into .vscode directory."""
    import json
    vscode_dir = workspace / ".vscode"
    vscode_dir.mkdir(parents=True, exist_ok=True)

    ext_map = {
        "rust": [
            "rust-lang.rust-analyzer",
            "tamasfe.even-better-toml",
            "vadimcn.vscode-lldb",
            "tauri-apps.tauri-vscode",
        ],
        "python": [
            "ms-python.python",
            "charliermarsh.ruff",
            "ms-python.black-formatter",
            "ms-python.flake8",
        ],
        "cpp": [
            "ms-vscode.cpptools",
            "twxs.cmake",
            "vadimcn.vscode-lldb",
        ],
        "web": [
            "dbaeumer.vscode-eslint",
            "esbenp.prettier-vscode",
            "bradlc.vscode-tailwindcss",
        ],
        "full": [
            "rust-lang.rust-analyzer",
            "tamasfe.even-better-toml",
            "vadimcn.vscode-lldb",
            "tauri-apps.tauri-vscode",
            "ms-python.python",
            "charliermarsh.ruff",
            "ms-python.black-formatter",
            "ms-vscode.cpptools",
            "twxs.cmake",
        ],
    }

    ext_file = vscode_dir / "extensions.json"
    if not ext_file.exists():
        exts = ext_map.get(profile, ext_map["full"])
        ext_file.write_text(json.dumps({"recommendations": exts}, indent=2) + "\n", encoding="utf-8")

    set_file = vscode_dir / "settings.json"
    if not set_file.exists():
        settings = {}
        if profile in ("rust", "full"):
            settings["rust-analyzer.check.command"] = "clippy"
        if profile in ("python", "full"):
            settings["python.formatting.provider"] = "black"
        set_file.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")

    log_ok(f"Perfil '{profile}' configurado en {vscode_dir}")

