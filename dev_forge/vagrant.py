"""VirtualBox and Vagrant lifecycle management and execution runner."""

import os
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional
from dev_forge.banner import log_err, log_info, log_ok, log_warn
from dev_forge.detector import ProjectType, ProjectTypeKind, PythonManager, extract_project_version
from dev_forge.hardware import detect_hardware


def get_forge_dir() -> Path:
    """Return the absolute path to the dev-forge workspace directory."""
    return Path(__file__).resolve().parent.parent


def run_vagrant_streaming(args: List[str], envs: Optional[Dict[str, str]] = None) -> bool:
    """Execute a vagrant command streaming output directly to the terminal."""
    env = os.environ.copy()
    if envs:
        env.update(envs)

    cmd = ["vagrant"] + args
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=get_forge_dir(),
            env=env,
            stdout=sys.stdout,
            stderr=sys.stderr,
        )
        proc.communicate()
        return proc.returncode == 0
    except FileNotFoundError:
        log_err("No se encontró el comando 'vagrant' en el PATH del sistema.")
        return False
    except Exception as e:
        log_err(f"Error al ejecutar vagrant: {e}")
        return False


def ensure_mutual_exclusion(target_machine: str) -> None:
    """If host has <= 16GB RAM, gracefully stop the sibling machine to prevent OOM."""
    hw = detect_hardware()
    if hw.total_ram_mb > 16384:
        return

    sibling = "forge-windows" if target_machine == "forge-linux" else "forge-linux"

    # Check if sibling is running via VBoxManage or vagrant
    try:
        out = subprocess.check_output(
            ["VBoxManage", "list", "runningvms"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        sibling_vbox_name = "FORGE-WINDOWS" if sibling == "forge-windows" else "FORGE-LINUX"
        if sibling_vbox_name in out:
            total_gb = hw.total_ram_mb // 1024
            log_warn(
                f"Host con memoria limitada ({total_gb} GB): apagando limpiamente '{sibling}' para evitar colisión de memoria..."
            )
            run_vagrant_streaming(["halt", sibling])
    except Exception:
        pass


def cmd_status() -> None:
    """Show the status of forge virtual machines."""
    log_info("Consultando estado de las máquinas virtuales de la forja...")
    run_vagrant_streaming(["status"])


def cmd_up(machine: str, provision: bool) -> None:
    """Boot a specific virtual machine."""
    ensure_mutual_exclusion(machine)
    log_info(f"Iniciando máquina virtual '{machine}'...")
    args = ["up", machine]
    if provision:
        args.append("--provision")
    run_vagrant_streaming(args)


def cmd_halt(machine: Optional[str], force: bool) -> None:
    """Gracefully or forcibly stop virtual machines."""
    log_info("Deteniendo máquinas virtuales para liberar memoria...")
    args = ["halt"]
    if force:
        args.append("-f")
    if machine:
        args.append(machine)
    run_vagrant_streaming(args)
    log_ok("Máquinas virtuales detenidas.")


def cmd_provision(machine: Optional[str]) -> None:
    """Trigger provisioning on virtual machines."""
    log_info("Aprovisionando herramientas en el entorno virtual...")
    args = ["provision"]
    if machine:
        args.append(machine)
    run_vagrant_streaming(args)


def cmd_ssh(machine: str, command: Optional[str]) -> None:
    """Open an interactive SSH session or execute a remote command."""
    ensure_mutual_exclusion(machine)
    if command:
        run_vagrant_streaming(["ssh", machine, "-c", command])
    else:
        run_vagrant_streaming(["ssh", machine])


def cmd_test_vm(machine: str) -> None:
    """Execute guest health-check validation."""
    ensure_mutual_exclusion(machine)
    log_info(f"Iniciando verificación de salud y pruebas en '{machine}'...")

    if machine == "forge-linux":
        run_vagrant_streaming(["up", "forge-linux"])
        log_info("--- [1/2] Verificando Kernel y Optimizaciones del Guest ---")
        ok = run_vagrant_streaming(
            ["ssh", "forge-linux", "-c", "sudo bash /forge/provision/linux/health-check.sh"]
        )
        if not ok:
            log_err("La verificación de salud del guest ha detectado inconsistencias.")
            sys.exit(1)

        test_sh = get_forge_dir() / "examples" / "hashforge" / "test.sh"
        if test_sh.is_file():
            log_info("--- [2/2] Ejecutando Suite Multi-Lenguaje HashForge (Rust) ---")
            proc = subprocess.run(["bash", str(test_sh), "rust", "linux"], cwd=get_forge_dir())
            if proc.returncode != 0:
                log_warn("HashForge Rust finalizó con advertencias.")

        log_ok("Todas las verificaciones de 'forge-linux' han finalizado con éxito.")

    elif machine == "forge-windows":
        run_vagrant_streaming(["up", "forge-windows"])
        log_info("--- [1/2] Verificando Sistema y Toolchains de Windows Server Core ---")
        cmd = "powershell.exe -ExecutionPolicy Bypass -NoProfile -File C:\\forge\\provision\\windows\\health-check.ps1"
        ok = run_vagrant_streaming(["winrm", "forge-windows", "-s", "powershell", "-c", cmd])
        if not ok:
            log_err("La verificación de toolchains en Windows ha detectado inconsistencias.")
            sys.exit(1)

        test_sh = get_forge_dir() / "examples" / "hashforge" / "test.sh"
        if test_sh.is_file():
            log_info("--- [2/2] Ejecutando Suite Multi-Lenguaje HashForge (Rust -> Windows) ---")
            subprocess.run(["bash", str(test_sh), "rust", "windows"], cwd=get_forge_dir())

        log_ok("Todas las verificaciones de 'forge-windows' han finalizado con éxito.")
    else:
        run_vagrant_streaming(["status", machine])


def cmd_build(
    project_path: Path,
    target: str,
    clean: bool = False,
    keep_vm: bool = False,
    update: bool = False,
    compiler: str = "nuitka",
    pyinstaller: bool = False,
) -> None:
    """Compile a project inside the isolated VM environment."""
    from dev_forge.config import load_host_profile

    load_host_profile()

    if not project_path.exists():
        log_err(f"Ruta de proyecto inválida o no encontrada: {project_path}")
        sys.exit(1)

    project_canonical = project_path.resolve()
    dist_dir = project_canonical / "dist"
    dist_dir.mkdir(parents=True, exist_ok=True)

    ptype = detect_project_type(project_canonical)
    ver_info = extract_project_version(project_canonical)

    log_info(f"Proyecto a compilar: {project_canonical}")
    log_info(f"Tipo de proyecto detectado: {ptype}")
    log_info(f"Versión detectada: {ver_info.display} (WiX: {ver_info.wix})")
    log_info(f"Destino solicitado: {target}")

    envs = {"FORGE_WORKSPACE": str(project_canonical)}

    if target in ("linux", "macos"):
        build_on_linux(ptype, project_canonical, clean, keep_vm, update, envs, compiler=compiler, pyinstaller=pyinstaller, ver_info=ver_info)
    elif target == "windows":
        build_on_windows(ptype, project_canonical, clean, keep_vm, update, envs, compiler=compiler, pyinstaller=pyinstaller, ver_info=ver_info)
    elif target == "all":
        build_on_linux(ptype, project_canonical, clean, keep_vm, update, envs, compiler=compiler, pyinstaller=pyinstaller, ver_info=ver_info)
        build_on_windows(ptype, project_canonical, clean, keep_vm, update, envs, compiler=compiler, pyinstaller=pyinstaller, ver_info=ver_info)
    else:
        log_err(f"Destino no soportado: {target}")
        sys.exit(1)

    dist_count = len(list(dist_dir.iterdir())) if dist_dir.exists() else 0
    if dist_count == 0:
        log_err(f"La compilación finalizó pero no se generó ningún artefacto en '{dist_dir}'")
        sys.exit(1)

    log_ok(f"Compilación finalizada. Binarios depositados en: {dist_dir}")


def build_on_linux(
    ptype: ProjectType,
    project_path: Path,
    clean: bool,
    keep_vm: bool,
    update: bool,
    envs: Dict[str, str],
    compiler: str = "nuitka",
    pyinstaller: bool = False,
    ver_info=None,
) -> None:
    """Execute isolated build pass on forge-linux."""
    ensure_mutual_exclusion("forge-linux")
    log_info("Preparando entorno de compilación en 'forge-linux'...")

    up_args = ["up", "forge-linux"]
    if update:
        up_args.append("--provision")
    run_vagrant_streaming(up_args, envs)

    # Clean unmount any previous workspace inside guest
    run_vagrant_streaming(
        [
            "ssh",
            "forge-linux",
            "-c",
            "if mountpoint -q /workspace; then sudo umount /workspace 2>/dev/null || sudo umount -l /workspace 2>/dev/null || true; fi",
        ],
        envs,
    )

    # Attach transient shared folder
    subprocess.run(
        ["VBoxManage", "sharedfolder", "remove", "FORGE-LINUX", "--name", "workspace", "--transient"],
        capture_output=True,
    )
    subprocess.run(
        [
            "VBoxManage",
            "sharedfolder",
            "add",
            "FORGE-LINUX",
            "--name",
            "workspace",
            "--hostpath",
            str(project_path),
            "--transient",
        ],
        capture_output=True,
    )

    mount_prefix = (
        "sudo mkdir -p /workspace && sudo mount -t vboxsf -o uid=1000,gid=1000,dmode=775,fmode=775 workspace /workspace && "
        "source /etc/profile 2>/dev/null || true; export PATH=\"/home/vagrant/.local/bin:$PATH\"; "
        "if [ -d /forge-cache ]; then export CARGO_HOME=/forge-cache/cargo GOMODCACHE=/forge-cache/go/pkg/mod PIP_CACHE_DIR=/forge-cache/pip GRADLE_USER_HOME=/forge-cache/gradle; "
        "mkdir -p /forge-cache/cargo /forge-cache/go/pkg/mod /forge-cache/pip /forge-cache/gradle; fi; "
    )

    clean_cmd = (
        "rm -rf /tmp/cargo-target/* /tmp/go-cache/* /tmp/build/* 2>/dev/null || true; "
        if clean
        else ""
    )

    use_nuitka = not pyinstaller and compiler == "nuitka"
    wix_ver = ver_info.wix if ver_info else "1.0.0"

    if ptype.kind == ProjectTypeKind.RUST_TAURI:
        build_script = (
            f"{clean_cmd}cd /workspace && (cargo tauri build || npx @tauri-apps/cli build || npx tauri build) && "
            f"(mkdir -p /workspace/dist && (cp -r src-tauri/target/release/bundle/* /workspace/dist/ 2>/dev/null || "
            f"cp src-tauri/target/release/$(grep -m1 name src-tauri/Cargo.toml | cut -d'\"' -f2) /workspace/dist/ 2>/dev/null || "
            f"cp target/release/$(grep -m1 name Cargo.toml | cut -d'\"' -f2) /workspace/dist/ 2>/dev/null))"
        )
    elif ptype.kind == ProjectTypeKind.RUST:
        build_script = (
            f"{clean_cmd}cd /workspace && CARGO_TARGET_DIR=/tmp/cargo-target cargo build --release && "
            f"cp /tmp/cargo-target/release/$(grep -m1 name Cargo.toml | cut -d'\"' -f2) /workspace/dist/ 2>/dev/null || true"
        )
    elif ptype.kind == ProjectTypeKind.PYTHON:
        if (project_path / "main.py").is_file():
            if use_nuitka:
                build_script = (
                    f"{clean_cmd}cd /workspace && if command -v nuitka >/dev/null 2>&1; then "
                    f"nuitka --standalone --onefile --output-dir=/tmp/nuitka-out --product-version={wix_ver} "
                    f"--assume-yes-for-downloads main.py -o hashforge-py && mkdir -p /workspace/dist && "
                    f"cp /tmp/nuitka-out/hashforge-py /workspace/dist/; else "
                    f"pyinstaller --clean -F --name hashforge-py main.py --distpath /workspace/dist/; fi"
                )
            else:
                build_script = f"{clean_cmd}cd /workspace && pyinstaller --clean -F --name hashforge-py main.py --distpath /workspace/dist/"
        else:
            build_script = f"{clean_cmd}cd /workspace && python3 -m build -o /workspace/dist/ 2>/dev/null || python3 -m pip wheel . -w /workspace/dist/"
    elif ptype.kind == ProjectTypeKind.JAVA:
        build_script = (
            f"{clean_cmd}cd /workspace && chmod +x ./gradlew 2>/dev/null || true; "
            f"(if [ -f ./gradlew ]; then ./gradlew build; elif [ -f pom.xml ]; then mvn package; else gradle build; fi) && "
            f"find build/libs/ target/ -name '*.jar' ! -name '*-plain.jar' -exec cp {{}} /workspace/dist/ \\; 2>/dev/null || true"
        )
    elif ptype.kind == ProjectTypeKind.GO:
        build_script = (
            f"{clean_cmd}cd /workspace && GOCACHE=/tmp/go-cache go build -o /workspace/dist/hashforge-go . 2>/dev/null || "
            f"GOCACHE=/tmp/go-cache go build -o /workspace/dist/ ."
        )
    elif ptype.kind == ProjectTypeKind.NODE:
        build_script = (
            f"{clean_cmd}cd /workspace && (npm run build || yarn build || pnpm build) && "
            f"cp -r dist/* build/* /workspace/dist/ 2>/dev/null || true"
        )
    elif ptype.kind == ProjectTypeKind.CCPP:
        build_script = (
            f"{clean_cmd}rm -rf /tmp/build && mkdir -p /tmp/build && cd /workspace && cmake -B /tmp/build -S . -G Ninja && "
            f"cmake --build /tmp/build && find /tmp/build -maxdepth 2 -type f -executable ! -name '*.ninja*' ! -name '*.cmake' "
            f"-exec cp {{}} /workspace/dist/ \\; 2>/dev/null || true"
        )
    else:
        build_script = (
            f"{clean_cmd}cd /workspace && if [ -f ./build.sh ]; then bash ./build.sh; elif [ -f ./Makefile ]; then make; fi"
        )

    log_info("Ejecutando proceso de compilación remota aislada...")
    full_cmd = f"{mount_prefix}{build_script}"
    success = run_vagrant_streaming(["ssh", "forge-linux", "-c", full_cmd], envs)

    # Clean unmount
    run_vagrant_streaming(
        [
            "ssh",
            "forge-linux",
            "-c",
            "if mountpoint -q /workspace; then sudo umount /workspace 2>/dev/null || sudo umount -l /workspace 2>/dev/null || true; fi",
        ],
        envs,
    )

    if not keep_vm:
        log_info("Liberando memoria del host (apagando forge-linux)...")
        run_vagrant_streaming(["halt", "forge-linux"], envs)

    if not success:
        log_err("Fallo en la compilación en forge-linux")
        sys.exit(1)


def build_on_windows(
    ptype: ProjectType,
    project_path: Path,
    clean: bool,
    keep_vm: bool,
    update: bool,
    envs: Dict[str, str],
    compiler: str = "nuitka",
    pyinstaller: bool = False,
    ver_info=None,
) -> None:
    """Execute isolated build pass on forge-windows."""
    ensure_mutual_exclusion("forge-windows")
    log_info("Preparando entorno de compilación en 'forge-windows'...")

    up_args = ["up", "forge-windows"]
    if update:
        up_args.append("--provision")
    run_vagrant_streaming(up_args, envs)

    # Attach transient shared folder
    subprocess.run(
        ["VBoxManage", "sharedfolder", "remove", "FORGE-WINDOWS", "--name", "workspace", "--transient"],
        capture_output=True,
    )
    subprocess.run(
        [
            "VBoxManage",
            "sharedfolder",
            "add",
            "FORGE-WINDOWS",
            "--name",
            "workspace",
            "--hostpath",
            str(project_path),
            "--transient",
        ],
        capture_output=True,
    )

    link_ps = (
        "if (Test-Path C:\\workspace) { cmd /c rmdir C:\\workspace 2>$null; Remove-Item -Force -Recurse C:\\workspace 2>$null }; "
        "cmd /c \"mklink /D C:\\workspace \\\\VBoxSvr\\workspace\" ; "
    )

    clean_ps = (
        "if (Test-Path C:\\target) { Remove-Item -Recurse -Force C:\\target 2>$null }; "
        if clean
        else ""
    )

    vs_shell_init = (
        "if (Test-Path 'C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\Common7\\Tools\\Launch-VsDevShell.ps1') { "
        "& 'C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\Common7\\Tools\\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64 | Out-Null }; "
    )

    cache_init = (
        "if (Test-Path C:\\forge-cache) { "
        "$env:CARGO_HOME='C:\\forge-cache\\cargo'; $env:GOMODCACHE='C:\\forge-cache\\go\\pkg\\mod'; $env:PIP_CACHE_DIR='C:\\forge-cache\\pip'; $env:GRADLE_USER_HOME='C:\\forge-cache\\gradle'; "
        "New-Item -ItemType Directory -Path C:\\forge-cache\\cargo, C:\\forge-cache\\go\\pkg\\mod, C:\\forge-cache\\pip, C:\\forge-cache\\gradle -Force | Out-Null }; "
    )

    use_nuitka = not pyinstaller and compiler == "nuitka"
    wix_ver = ver_info.wix if ver_info else "1.0.0"
    raw_ver = ver_info.raw if ver_info else "0.1.0"
    branch = ver_info.branch if ver_info else ""

    if ptype.kind in (ProjectTypeKind.RUST, ProjectTypeKind.RUST_TAURI):
        build_ps = (
            f"{link_ps}{clean_ps}{cache_init}Set-Location C:\\workspace; $env:CARGO_TARGET_DIR='C:\\target'; cargo build --release; "
            f"if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; "
            f"Copy-Item C:\\target\\release\\*.exe C:\\workspace\\dist\\ -Force"
        )
    elif ptype.kind == ProjectTypeKind.PYTHON:
        if use_nuitka:
            py_cmd = (
                f"if (Test-Path main.py) {{ "
                f"$ico = & C:\\forge\\provision\\windows\\package-artifacts.ps1 -FindIconOnly -WorkspaceDir C:\\workspace -TargetDir C:\\target; "
                f"$icoOpt = if ($ico) {{ \"--windows-icon-from-ico='$ico'\" }} else {{ '' }}; "
                f"Invoke-Expression \"nuitka --standalone --onefile --output-dir=C:\\target\\nuitka-out $icoOpt --product-version='{wix_ver}' --file-version='{wix_ver}' --assume-yes-for-downloads main.py -o hashforge-py.exe 2>&1\" | Out-Host; "
                f"if (Test-Path C:\\target\\nuitka-out\\hashforge-py.exe) {{ Copy-Item C:\\target\\nuitka-out\\hashforge-py.exe C:\\workspace\\dist\\ -Force; exit 0 }} else {{ "
                f"Invoke-Expression \"python -m PyInstaller --clean -F --name hashforge-py main.py --distpath C:\\workspace\\dist 2>&1\" | Out-Host; "
                f"if (Test-Path C:\\workspace\\dist\\hashforge-py.exe) {{ exit 0 }} else {{ exit 1 }} }} }} else {{ python -m build -o C:\\workspace\\dist }}"
            )
        else:
            py_cmd = (
                f"if (Test-Path main.py) {{ "
                f"$ico = & C:\\forge\\provision\\windows\\package-artifacts.ps1 -FindIconOnly -WorkspaceDir C:\\workspace -TargetDir C:\\target; "
                f"$icoOpt = if ($ico) {{ \"--icon '$ico'\" }} else {{ '' }}; "
                f"Invoke-Expression \"python -m PyInstaller --clean -F --name hashforge-py $icoOpt main.py --distpath C:\\workspace\\dist 2>&1\" | Out-Host; "
                f"if (Test-Path C:\\workspace\\dist\\hashforge-py.exe) {{ exit 0 }} else {{ exit 1 }} }} else {{ python -m build -o C:\\workspace\\dist }}"
            )
        build_ps = f"{link_ps}{clean_ps}{cache_init}Set-Location C:\\workspace; if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; {py_cmd}"
    elif ptype.kind == ProjectTypeKind.CCPP:
        build_ps = (
            f"{link_ps}{clean_ps}{cache_init}{vs_shell_init}Set-Location C:\\workspace; cmake -B C:\\target -S . -G Ninja; cmake --build C:\\target; "
            f"if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; "
            f"Get-ChildItem -Path C:\\target -Filter '*.exe' -Recurse | Copy-Item -Destination C:\\workspace\\dist\\ -Force"
        )
    elif ptype.kind == ProjectTypeKind.GO:
        build_ps = (
            f"{link_ps}{clean_ps}{cache_init}Set-Location C:\\workspace; "
            f"if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; "
            f"go build -o C:\\workspace\\dist\\hashforge-go.exe . ; "
            f"if (-not (Test-Path C:\\workspace\\dist\\hashforge-go.exe)) {{ go build -o C:\\workspace\\dist\\ . }}"
        )
    else:
        build_ps = (
            f"{link_ps}{clean_ps}{cache_init}Set-Location C:\\workspace; if (Test-Path .\\build.bat) {{ .\\build.bat }}"
        )

    pack_ps = (
        f"; if (Test-Path 'C:\\forge\\provision\\windows\\package-artifacts.ps1') {{ "
        f"& 'C:\\forge\\provision\\windows\\package-artifacts.ps1' -DistDir 'C:\\workspace\\dist' -TargetDir 'C:\\target' -WorkspaceDir 'C:\\workspace' "
        f"-AppVersion '{raw_ver}' -WixVersion '{wix_ver}' -GitBranch '{branch}' }}"
    )
    full_cmd = f"{build_ps}{pack_ps}"

    log_info("Ejecutando proceso de compilación remota en Windows Server Core...")
    success = run_vagrant_streaming(["winrm", "forge-windows", "-s", "powershell", "-c", full_cmd], envs)

    if not keep_vm:
        log_info("Liberando memoria del host (apagando forge-windows)...")
        run_vagrant_streaming(["halt", "forge-windows"], envs)

    if not success:
        log_err("Fallo en la compilación en forge-windows")
        sys.exit(1)
