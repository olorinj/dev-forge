"""VirtualBox and Vagrant lifecycle management and execution runner."""

import os
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional
from dev_forge.banner import log_err, log_info, log_ok, log_warn
from dev_forge.detector import (
    ProjectType,
    ProjectTypeKind,
    PythonManager,
    extract_project_name,
    extract_project_version,
)
from dev_forge.hardware import detect_hardware


def is_dev_forge_root(p: Path) -> bool:
    return (p / "Vagrantfile").is_file() and (
        (p / "provision" / "ansible" / "linux.yml").is_file()
        or (p / "provision" / "ansible").is_dir()
        or (p / "provision" / "linux").is_dir()
    )


def get_forge_dir() -> Path:
    """Return the absolute path to the dev-forge workspace directory."""
    # 1. Explicit FORGE_DIR
    if "FORGE_DIR" in os.environ:
        p = Path(os.environ["FORGE_DIR"]).resolve()
        if is_dev_forge_root(p):
            return p

    # 2. Package root parent
    pkg_root = Path(__file__).resolve().parent.parent
    if is_dev_forge_root(pkg_root):
        return pkg_root

    # 3. Persisted forge root in ~/.dev-forge/forge-root.path
    cfg_root_file = Path.home() / ".dev-forge" / "forge-root.path"
    if cfg_root_file.is_file():
        p = Path(cfg_root_file.read_text(encoding="utf-8").strip()).resolve()
        if is_dev_forge_root(p):
            return p

    # 4. Current dir only if verified
    cwd = Path.cwd().resolve()
    if is_dev_forge_root(cwd):
        return cwd

    return pkg_root


def run_vagrant_streaming(args: List[str], envs: Optional[Dict[str, str]] = None) -> bool:
    """Execute a vagrant command streaming output directly to the terminal."""
    forge_dir = get_forge_dir()
    env = os.environ.copy()
    env["VAGRANT_CWD"] = str(forge_dir)
    env["VAGRANT_DOTFILE_PATH"] = str(forge_dir / ".vagrant")
    if envs:
        env.update(envs)

    cmd = ["vagrant"] + args
    try:
        proc = subprocess.Popen(
            cmd,
            cwd=forge_dir,
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
    project_path: Path | None = None,
    target: str | None = None,
    clean: bool = False,
    keep_vm: bool = False,
    update: bool = False,
    compiler: str = "nuitka",
    pyinstaller: bool = False,
    component: str | None = None,
    package: str | None = None,
    profile: str | None = None,
    test: bool = False,
    interactive: bool = False,
) -> None:
    """Compile a project inside the isolated VM environment."""
    from dev_forge.config import expand_path, load_host_profile, save_recent_project
    from dev_forge.menu import prompt_menu

    load_host_profile()

    class BuildOptions:
        def __init__(self):
            self.project = project_path
            self.target = target
            self.component = component
            self.package = package
            self.profile = profile
            self.test = test

    opts = BuildOptions()
    is_interactive = (
        interactive
        or opts.project is None
        or (target is None and component is None and package is None and not test)
    )
    if is_interactive:
        prompt_menu(opts)

    raw_project = opts.project or Path.cwd()
    expanded = expand_path(raw_project)
    if not expanded.exists():
        log_err(f"Ruta de proyecto inválida o no encontrada: {expanded}")
        sys.exit(1)

    project_canonical = expanded.resolve()
    save_recent_project(project_canonical)

    target_res = opts.target or "all"
    component_res = opts.component or ("test" if opts.test else "all")
    package_res = opts.package or "all"
    profile_res = opts.profile or ("test" if opts.test or component_res == "test" else "release")
    is_test_mode = opts.test or component_res == "test" or profile_res == "test"

    dist_dir = project_canonical / "dist"
    dist_dir.mkdir(parents=True, exist_ok=True)

    ptype = detect_project_type(project_canonical)
    ver_info = extract_project_version(project_canonical)

    log_info(f"Proyecto a compilar:  {project_canonical}")
    log_info(f"Tipo detectado:       {ptype}")
    log_info(f"Versión detectada:    {ver_info.display} (WiX: {ver_info.wix})")
    log_info(f"Destino solicitado:   {target_res}")
    log_info(f"Componente / Tipo:    {component_res}")
    log_info(f"Formato / Empaque:    {package_res}")
    log_info(f"Modo / Perfil:        {profile_res}")

    envs = {"FORGE_WORKSPACE": str(project_canonical)}

    if target_res == "linux":
        build_on_linux(
            ptype,
            project_canonical,
            clean,
            keep_vm,
            update,
            envs,
            compiler=compiler,
            pyinstaller=pyinstaller,
            ver_info=ver_info,
            build_linux=True,
            build_macos=False,
            component=component_res,
            package=package_res,
            is_test_mode=is_test_mode,
        )
    elif target_res == "macos":
        build_on_linux(
            ptype,
            project_canonical,
            clean,
            keep_vm,
            update,
            envs,
            compiler=compiler,
            pyinstaller=pyinstaller,
            ver_info=ver_info,
            build_linux=False,
            build_macos=True,
            component=component_res,
            package=package_res,
            is_test_mode=is_test_mode,
        )
    elif target_res == "windows":
        build_on_windows(
            ptype,
            project_canonical,
            clean,
            keep_vm,
            update,
            envs,
            compiler=compiler,
            pyinstaller=pyinstaller,
            ver_info=ver_info,
            component=component_res,
            package=package_res,
            is_test_mode=is_test_mode,
        )
    elif target_res == "all":
        build_on_linux(
            ptype,
            project_canonical,
            clean,
            keep_vm,
            update,
            envs,
            compiler=compiler,
            pyinstaller=pyinstaller,
            ver_info=ver_info,
            build_linux=True,
            build_macos=True,
            component=component_res,
            package=package_res,
            is_test_mode=is_test_mode,
        )
        build_on_windows(
            ptype,
            project_canonical,
            clean,
            keep_vm,
            update,
            envs,
            compiler=compiler,
            pyinstaller=pyinstaller,
            ver_info=ver_info,
            component=component_res,
            package=package_res,
            is_test_mode=is_test_mode,
        )
    else:
        log_err(f"Destino no soportado: {target_res}")
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
    build_linux: bool = True,
    build_macos: bool = False,
    component: str = "all",
    package: str = "all",
    is_test_mode: bool = False,
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
        "sudo sed -i '/tmpfs \\/tmp tmpfs/d' /etc/fstab 2>/dev/null || true; if mountpoint -q /tmp; then sudo umount -l /tmp 2>/dev/null || true; fi; "
        "sudo sed -i 's|:/root/\\.cargo/bin||g' /etc/profile.d/*.sh /etc/profile 2>/dev/null || true; "
        "sudo mkdir -p /workspace && sudo mount -t vboxsf -o uid=1000,gid=1000,dmode=775,fmode=775 workspace /workspace 2>/dev/null || true; "
        "sudo systemctl daemon-reload 2>/dev/null || true; "
        "sudo chmod 666 /dev/fuse 2>/dev/null || true; "
        "export APPIMAGE_EXTRACT_AND_RUN=1; export NO_STRIP=1; "
        "source /etc/profile 2>/dev/null || true; export PATH=$(echo \"/home/vagrant/.cargo/bin:/usr/local/bin:/home/vagrant/.local/bin:$PATH\" | tr ':' '\\n' | grep -v '^/root' | awk '!seen[$0]++' | paste -sd ':' -); "
        "if [ -d /forge-cache ]; then export CARGO_HOME=/forge-cache/cargo GOMODCACHE=/forge-cache/go/pkg/mod PIP_CACHE_DIR=/forge-cache/pip GRADLE_USER_HOME=/forge-cache/gradle; "
        "mkdir -p /forge-cache/cargo /forge-cache/go/pkg/mod /forge-cache/pip /forge-cache/gradle; fi; "
    )

    clean_cmd = (
        "rm -rf /tmp/cargo-target/* /tmp/go-cache/* /tmp/build/* 2>/dev/null || true; "
        if clean
        else ""
    )

    app_name = extract_project_name(project_path)
    if (project_path / "src-tauri" / "Cargo.toml").is_file():
        gui_name = extract_project_name(project_path / "src-tauri")
    else:
        gui_name = f"{app_name}-gui"

    use_nuitka = not pyinstaller and compiler == "nuitka"
    wix_ver = ver_info.wix if ver_info else "1.0.0"
    raw_ver = ver_info.raw if ver_info and ver_info.raw else "0.1.0"

    if is_test_mode:
        if ptype.kind in (ProjectTypeKind.RUST, ProjectTypeKind.RUST_TAURI):
            linux_script = (
                f"{clean_cmd}mkdir -p /workspace/dist; "
                f"echo '=== [dev-forge : Linux] Compilando suite de testing para {app_name} ==='; "
                f"cd /workspace && CARGO_TARGET_DIR=/tmp/cargo-target cargo test --no-run --release; "
                f"for tb in $(find /tmp/cargo-target/release/deps/ -maxdepth 1 -type f -executable ! -name '*.so' ! -name '*.d' 2>/dev/null); do "
                f"  tb_base=$(basename \"$tb\"); "
                f"  if [[ \"$tb_base\" =~ ^{app_name}- ]] || [[ \"$tb_base\" == \"{app_name}\" ]]; then "
                f"    cp \"$tb\" '/workspace/dist/{app_name}-test-linux.x86_64'; "
                f"    cp '/workspace/dist/{app_name}-test-linux.x86_64' '/workspace/dist/{app_name}-test-{raw_ver}-linux.x86_64' 2>/dev/null || true; "
                f"    chmod +x '/workspace/dist/{app_name}-test-'* 2>/dev/null || true; "
                f"    echo '[dev-forge : Linux] Binario de prueba generado: /workspace/dist/{app_name}-test-linux.x86_64 ({raw_ver})'; "
                f"    break; "
                f"  fi; "
                f"done; "
                f"if [ ! -f '/workspace/dist/{app_name}-test-linux.x86_64' ]; then "
                f"  first_test=$(find /tmp/cargo-target/release/deps/ -maxdepth 1 -type f -executable ! -name '*.so' ! -name '*.d' 2>/dev/null | head -n 1); "
                f"  if [ -n \"$first_test\" ]; then "
                f"    cp \"$first_test\" '/workspace/dist/{app_name}-test-linux.x86_64'; "
                f"    cp '/workspace/dist/{app_name}-test-linux.x86_64' '/workspace/dist/{app_name}-test-{raw_ver}-linux.x86_64' 2>/dev/null || true; "
                f"    chmod +x '/workspace/dist/{app_name}-test-'* 2>/dev/null || true; "
                f"    echo '[dev-forge : Linux] Binario de prueba generado: /workspace/dist/{app_name}-test-linux.x86_64 ({raw_ver})'; "
                f"  fi; "
                f"fi;"
            )
        elif ptype.kind == ProjectTypeKind.GO:
            linux_script = (
                f"{clean_cmd}mkdir -p /workspace/dist && cd /workspace; "
                f"echo '=== [dev-forge : Linux] Compilando suite de testing Go para {app_name} ==='; "
                f"GOCACHE=/tmp/go-cache go test -c -o '/workspace/dist/{app_name}-test-linux.x86_64' . 2>/dev/null || true; "
                f"cp '/workspace/dist/{app_name}-test-linux.x86_64' '/workspace/dist/{app_name}-test-{raw_ver}-linux.x86_64' 2>/dev/null || true; "
                f"chmod +x '/workspace/dist/{app_name}-test-'* 2>/dev/null || true;"
            )
        elif ptype.kind == ProjectTypeKind.PYTHON:
            linux_script = (
                f"{clean_cmd}mkdir -p /workspace/dist && cd /workspace; "
                f"echo '=== [dev-forge : Linux] Verificando tests Python ==='; "
                f"if command -v pytest >/dev/null 2>&1; then "
                f"  pytest -q 2>&1 | tee /workspace/dist/test-results-linux.log || true; "
                f"else "
                f"  python3 -m unittest discover tests 2>&1 | tee /workspace/dist/test-results-linux.log || true; "
                f"fi;"
            )
        elif ptype.kind == ProjectTypeKind.CCPP:
            linux_script = (
                f"{clean_cmd}mkdir -p /workspace/dist /tmp/build && cd /workspace && cmake -B /tmp/build -S . -G Ninja -DBUILD_TESTING=ON && cmake --build /tmp/build && "
                f"find /tmp/build -maxdepth 2 -type f -executable \\( -name '*test*' -o -name '*_test' \\) -exec cp {{}} '/workspace/dist/{app_name}-test-linux.x86_64' \\; 2>/dev/null || true; "
                f"cp '/workspace/dist/{app_name}-test-linux.x86_64' '/workspace/dist/{app_name}-test-{raw_ver}-linux.x86_64' 2>/dev/null || true; "
                f"chmod +x '/workspace/dist/{app_name}-test-'* 2>/dev/null || true;"
            )
        elif ptype.kind == ProjectTypeKind.JAVA:
            linux_script = (
                f"{clean_cmd}mkdir -p /workspace/dist && cd /workspace; "
                f"echo '=== [dev-forge : Linux] Compilando tests Java ==='; "
                f"(gradle testClasses || ./gradlew testClasses || mvn test-compile || true);"
            )
        else:
            linux_script = f"{clean_cmd}echo '[dev-forge : Linux] Testing no configurado para este tipo de proyecto.';"
    else:
        build_cli = component in ("all", "cli")
        build_gui = component in ("all", "gui")
        copy_bundles = package in ("all", "bundle")
        is_single = package == "single"
        tauri_no_bundle_opt = " --no-bundle" if package in ("single", "bin") else ""

        if ptype.kind == ProjectTypeKind.RUST_TAURI:
            cp_cli_canonical = "" if is_single else f"  cp '/tmp/cargo-target/release/{app_name}' '/workspace/dist/{app_name}-cli-linux.x86_64'; "
            cli_step = (
                f"echo '=== [dev-forge : Linux] Compilando CLI {app_name} ==='; "
                f"cd /workspace && CARGO_TARGET_DIR=/tmp/cargo-target cargo build --release; "
                f"if [ -f '/tmp/cargo-target/release/{app_name}' ]; then "
                f"{cp_cli_canonical}"
                f"  cp '/tmp/cargo-target/release/{app_name}' '/workspace/dist/{app_name}-cli-{raw_ver}-linux.x86_64' 2>/dev/null || true; "
                f"  chmod +x '/workspace/dist/{app_name}-cli-'* 2>/dev/null || true; "
                f"fi; "
                if build_cli
                else ""
            )
            cp_gui_canonical = "" if is_single else f"    cp \"$gb\" '/workspace/dist/{app_name}-gui-linux.x86_64'; "
            gui_step = (
                f"echo '=== [dev-forge : Linux] Compilando GUI {gui_name} y Bundles ==='; "
                f"if ! command -v cargo-tauri >/dev/null 2>&1; then "
                f"  if command -v cargo-binstall >/dev/null 2>&1; then "
                f"    cargo-binstall --no-confirm tauri-cli 2>/dev/null || true; "
                f"  elif command -v npm >/dev/null 2>&1; then "
                f"    sudo npm install -g @tauri-apps/cli 2>/dev/null || true; "
                f"  fi "
                f"fi; "
                f"cd /workspace && (if command -v cargo-tauri >/dev/null 2>&1; then cargo tauri build{tauri_no_bundle_opt}; else npx --yes @tauri-apps/cli build{tauri_no_bundle_opt}; fi); "
                f"for gb in '/tmp/cargo-target/release/{gui_name}' '/tmp/cargo-target/release/{app_name}-gui' 'src-tauri/target/release/{gui_name}' 'target/release/{gui_name}'; do "
                f"  if [ -f \"$gb\" ]; then "
                f"{cp_gui_canonical}"
                f"    cp \"$gb\" '/workspace/dist/{app_name}-gui-{raw_ver}-linux.x86_64' 2>/dev/null || true; "
                f"    chmod +x '/workspace/dist/{app_name}-gui-'* 2>/dev/null || true; "
                f"    break; "
                f"  fi; "
                f"done; "
                if build_gui
                else ""
            )
            bundle_step = (
                f"find /tmp/cargo-target/release/bundle/ src-tauri/target/release/bundle/ target/release/bundle/ -type f \\( -name '*.deb' -o -name '*.rpm' -o -name '*.AppImage' \\) -exec cp {{}} /workspace/dist/ \\; 2>/dev/null || true"
                if build_gui and copy_bundles
                else ""
            )
            linux_script = f"{clean_cmd}export APPIMAGE_EXTRACT_AND_RUN=1; export NO_STRIP=1; mkdir -p /workspace/dist; {cli_step}{gui_step}{bundle_step}"
        elif ptype.kind == ProjectTypeKind.RUST:
            if component == "gui":
                linux_script = f"{clean_cmd}echo '[dev-forge : Linux] GUI no aplicable para proyecto Rust estándar.';"
            else:
                cp_rust_canonical = "" if is_single else f"  cp '/tmp/cargo-target/release/{app_name}' '/workspace/dist/{app_name}-cli-linux.x86_64'; "
                linux_script = (
                    f"{clean_cmd}mkdir -p /workspace/dist && cd /workspace && CARGO_TARGET_DIR=/tmp/cargo-target cargo build --release && "
                    f"if [ -f '/tmp/cargo-target/release/{app_name}' ]; then "
                    f"{cp_rust_canonical}"
                    f"  cp '/tmp/cargo-target/release/{app_name}' '/workspace/dist/{app_name}-cli-{raw_ver}-linux.x86_64' 2>/dev/null || true; "
                    f"  chmod +x '/workspace/dist/{app_name}-cli-'* 2>/dev/null || true; "
                    f"fi"
                )
        elif ptype.kind == ProjectTypeKind.PYTHON:
            if (project_path / "main.py").is_file():
                if use_nuitka:
                    py_standalone = (
                        f"if command -v nuitka >/dev/null 2>&1; then "
                        f"nuitka --standalone --onefile --output-dir=/tmp/nuitka-out --product-version={wix_ver} "
                        f"--assume-yes-for-downloads main.py -o {app_name}-cli-linux.x86_64 && mkdir -p /workspace/dist && "
                        f"cp /tmp/nuitka-out/{app_name}-cli-linux.x86_64 /workspace/dist/ && cp /workspace/dist/{app_name}-cli-linux.x86_64 /workspace/dist/{app_name}-cli-{raw_ver}-linux.x86_64; else "
                        f"pyinstaller --clean -F --name {app_name}-cli-linux.x86_64 main.py --distpath /workspace/dist/ && cp /workspace/dist/{app_name}-cli-linux.x86_64 /workspace/dist/{app_name}-cli-{raw_ver}-linux.x86_64; fi"
                    )
                else:
                    py_standalone = f"pyinstaller --clean -F --name {app_name}-cli-linux.x86_64 main.py --distpath /workspace/dist/ && cp /workspace/dist/{app_name}-cli-linux.x86_64 /workspace/dist/{app_name}-cli-{raw_ver}-linux.x86_64"
                linux_script = f"{clean_cmd}cd /workspace && {py_standalone}"
            else:
                linux_script = f"{clean_cmd}cd /workspace && python3 -m build -o /workspace/dist/ 2>/dev/null || python3 -m pip wheel . -w /workspace/dist/"
        elif ptype.kind == ProjectTypeKind.JAVA:
            linux_script = (
                f"{clean_cmd}cd /workspace && chmod +x ./gradlew 2>/dev/null || true; "
                f"(if [ -f ./gradlew ]; then ./gradlew build; elif [ -f pom.xml ]; then mvn package; else gradle build; fi) && "
                f"find build/libs/ target/ -name '*.jar' ! -name '*-plain.jar' -exec cp {{}} /workspace/dist/ \\; 2>/dev/null || true"
            )
        elif ptype.kind == ProjectTypeKind.GO:
            linux_script = (
                f"{clean_cmd}mkdir -p /workspace/dist && cd /workspace && (GOCACHE=/tmp/go-cache go build -o '/workspace/dist/{app_name}-cli-linux.x86_64' . 2>/dev/null || "
                f"GOCACHE=/tmp/go-cache go build -o '/workspace/dist/{app_name}-cli-linux.x86_64' ./...) && cp '/workspace/dist/{app_name}-cli-linux.x86_64' '/workspace/dist/{app_name}-cli-{raw_ver}-linux.x86_64' 2>/dev/null || true; chmod +x '/workspace/dist/{app_name}-cli-'* 2>/dev/null || true"
            )
        elif ptype.kind == ProjectTypeKind.NODE:
            linux_script = (
                f"{clean_cmd}cd /workspace && (npm run build || yarn build || pnpm build) && "
                f"cp -r dist/* build/* /workspace/dist/ 2>/dev/null || true"
            )
        elif ptype.kind == ProjectTypeKind.CCPP:
            linux_script = (
                f"{clean_cmd}rm -rf /tmp/build && mkdir -p /tmp/build /workspace/dist && cd /workspace && cmake -B /tmp/build -S . -G Ninja && "
                f"cmake --build /tmp/build && find /tmp/build -maxdepth 2 -type f -executable ! -name '*.ninja*' ! -name '*.cmake' "
                f"-exec cp {{}} '/workspace/dist/{app_name}-cli-linux.x86_64' \\; 2>/dev/null || true; cp '/workspace/dist/{app_name}-cli-linux.x86_64' '/workspace/dist/{app_name}-cli-{raw_ver}-linux.x86_64' 2>/dev/null || true; chmod +x '/workspace/dist/{app_name}-cli-'* 2>/dev/null || true"
            )
        else:
            linux_script = (
                f"{clean_cmd}cd /workspace && if [ -f ./build.sh ]; then bash ./build.sh; elif [ -f ./Makefile ]; then make; fi"
            )

    if is_test_mode:
        if ptype.kind in (ProjectTypeKind.RUST, ProjectTypeKind.RUST_TAURI):
            macos_script = (
                f"echo '=== [dev-forge : macOS] Compilando suite de testing macOS para {app_name} ==='; "
                f"mkdir -p /workspace/dist; "
                f"cd /workspace; "
                f"rustup target add x86_64-apple-darwin aarch64-apple-darwin 2>/dev/null || true; "
                f"CARGO_TARGET_DIR=/tmp/cargo-target cargo test --target x86_64-apple-darwin --no-run --release 2>/dev/null || true; "
                f"for tb in $(find /tmp/cargo-target/x86_64-apple-darwin/release/deps/ -maxdepth 1 -type f -executable ! -name '*.so' ! -name '*.d' 2>/dev/null); do "
                f"  tb_base=$(basename \"$tb\"); "
                f"  if [[ \"$tb_base\" =~ ^{app_name}- ]] || [[ \"$tb_base\" == \"{app_name}\" ]]; then "
                f"    cp \"$tb\" '/workspace/dist/{app_name}-test-darwin.x86_64'; "
                f"    cp '/workspace/dist/{app_name}-test-darwin.x86_64' '/workspace/dist/{app_name}-test-{raw_ver}-darwin.x86_64' 2>/dev/null || true; "
                f"    chmod +x '/workspace/dist/{app_name}-test-'* 2>/dev/null || true; "
                f"    echo '[dev-forge : macOS] Binario de prueba generado: /workspace/dist/{app_name}-test-darwin.x86_64 ({raw_ver})'; "
                f"    break; "
                f"  fi; "
                f"done;"
            )
        elif ptype.kind == ProjectTypeKind.GO:
            macos_script = (
                f"mkdir -p /workspace/dist && cd /workspace; "
                f"echo '=== [dev-forge : macOS] Compilando suite de testing Go para Darwin ==='; "
                f"GOCACHE=/tmp/go-cache GOOS=darwin GOARCH=amd64 go test -c -o '/workspace/dist/{app_name}-test-darwin.x86_64' . 2>/dev/null || true; "
                f"cp '/workspace/dist/{app_name}-test-darwin.x86_64' '/workspace/dist/{app_name}-test-{raw_ver}-darwin.x86_64' 2>/dev/null || true; "
                f"chmod +x '/workspace/dist/{app_name}-test-'* 2>/dev/null || true;"
            )
        else:
            macos_script = "echo '[dev-forge : macOS] Compilación de test para macOS omitida para este proyecto.';"
    elif component == "gui":
        macos_script = (
            "echo '[dev-forge : macOS : AVISO] Los paquetes GUI nativos de macOS (.app/.dmg) requieren frameworks "
            "de Cocoa/WebKit y un entorno de compilación macOS nativo. Compilación GUI omitida.';"
        )
    elif ptype.kind in (ProjectTypeKind.RUST, ProjectTypeKind.RUST_TAURI):
        tauri_macos_note = (
            "echo '[dev-forge : macOS : INFO] Binarios CLI Mach-O compilados para macOS. "
            "Los instaladores GUI nativos (.dmg/.app) requieren un entorno macOS nativo con Cocoa/WebKit.'; "
            if ptype.kind == ProjectTypeKind.RUST_TAURI
            else ""
        )
        macos_script = (
            f"echo '=== [dev-forge : macOS] Compilando binarios Darwin Mach-O para {app_name} ==='; "
            f"mkdir -p /workspace/dist; "
            f"if [ -f /workspace/build/Dockerfile.osxcross ]; then "
            f"  OSXCROSS_DOCKER='/workspace/build/Dockerfile.osxcross'; "
            f"elif [ -f /workspace/Dockerfile.osxcross ]; then "
            f"  OSXCROSS_DOCKER='/workspace/Dockerfile.osxcross'; "
            f"else "
            f"  OSXCROSS_DOCKER=''; "
            f"fi; "
            f"if [ -n \"$OSXCROSS_DOCKER\" ]; then "
            f"  echo '[dev-forge : macOS] Compilando mediante contenedor osxcross ('\"$OSXCROSS_DOCKER\"')...'; "
            f"  cd /workspace; "
            f"  sudo docker build -t forge-osxcross -f \"$OSXCROSS_DOCKER\" . && "
            f"  sudo docker run --rm -v /workspace:/src -v /tmp/cargo-target:/src/target forge-osxcross cargo build --target x86_64-apple-darwin --release || true; "
            f"  sudo docker run --rm -v /workspace:/src -v /tmp/cargo-target:/src/target forge-osxcross cargo build --target aarch64-apple-darwin --release || true; "
            f"else "
            f"  echo '[dev-forge : macOS] Compilando con toolchain Rust hacia Darwin...'; "
            f"  cd /workspace; "
            f"  rustup target add x86_64-apple-darwin aarch64-apple-darwin 2>/dev/null || true; "
            f"  CARGO_TARGET_DIR=/tmp/cargo-target cargo build --target x86_64-apple-darwin --release 2>/dev/null || true; "
            f"  CARGO_TARGET_DIR=/tmp/cargo-target cargo build --target aarch64-apple-darwin --release 2>/dev/null || true; "
            f"fi; "
            f"for f in '/tmp/cargo-target/x86_64-apple-darwin/release/{app_name}' '/workspace/target/x86_64-apple-darwin/release/{app_name}'; do "
            f"  if [ -f \"$f\" ]; then "
            f"    cp \"$f\" '/workspace/dist/{app_name}-cli-darwin.x86_64'; "
            f"    cp '/workspace/dist/{app_name}-cli-darwin.x86_64' '/workspace/dist/{app_name}-cli-{raw_ver}-darwin.x86_64' 2>/dev/null || true; "
            f"    chmod +x '/workspace/dist/{app_name}-cli-'* 2>/dev/null || true; "
            f"    echo '[dev-forge : macOS] Generado: /workspace/dist/{app_name}-cli-darwin.x86_64 ({raw_ver})'; "
            f"    break; "
            f"  fi; "
            f"done; "
            f"for f in '/tmp/cargo-target/aarch64-apple-darwin/release/{app_name}' '/workspace/target/aarch64-apple-darwin/release/{app_name}'; do "
            f"  if [ -f \"$f\" ]; then "
            f"    cp \"$f\" '/workspace/dist/{app_name}-cli-darwin.aarch64'; "
            f"    cp '/workspace/dist/{app_name}-cli-darwin.aarch64' '/workspace/dist/{app_name}-cli-{raw_ver}-darwin.aarch64' 2>/dev/null || true; "
            f"    chmod +x '/workspace/dist/{app_name}-cli-'* 2>/dev/null || true; "
            f"    echo '[dev-forge : macOS] Generado: /workspace/dist/{app_name}-cli-darwin.aarch64 ({raw_ver})'; "
            f"    break; "
            f"  fi; "
            f"done; "
            f"{tauri_macos_note}"
        )
    elif ptype.kind == ProjectTypeKind.GO:
        macos_script = (
            f"echo '=== [dev-forge : macOS] Compilando binarios Go Darwin para {app_name} ==='; "
            f"mkdir -p /workspace/dist && cd /workspace; "
            f"GOCACHE=/tmp/go-cache GOOS=darwin GOARCH=amd64 go build -o '/workspace/dist/{app_name}-cli-darwin.x86_64' . 2>/dev/null || true; "
            f"cp '/workspace/dist/{app_name}-cli-darwin.x86_64' '/workspace/dist/{app_name}-cli-{raw_ver}-darwin.x86_64' 2>/dev/null || true; "
            f"GOCACHE=/tmp/go-cache GOOS=darwin GOARCH=arm64 go build -o '/workspace/dist/{app_name}-cli-darwin.aarch64' . 2>/dev/null || true; "
            f"cp '/workspace/dist/{app_name}-cli-darwin.aarch64' '/workspace/dist/{app_name}-cli-{raw_ver}-darwin.aarch64' 2>/dev/null || true; "
            f"chmod +x /workspace/dist/{app_name}-cli-darwin.* 2>/dev/null || true;"
        )
    else:
        macos_script = "echo '[dev-forge : macOS] Compilación para macOS omitida para este tipo de proyecto.';"

    combined_script = ""
    if build_linux:
        combined_script += linux_script
    if build_macos:
        if combined_script:
            combined_script += "; "
        combined_script += macos_script

    log_info("Ejecutando proceso de compilación remota aislada...")
    full_cmd = f"{mount_prefix}{combined_script}"
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
    component: str = "all",
    package: str = "all",
    is_test_mode: bool = False,
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

    defender_bypass = (
        "Set-MpPreference -DisableRealtimeMonitoring $true -DisableBehaviorMonitoring $true -DisableIOAVProtection $true "
        "-DisableScriptScanning $true -ErrorAction SilentlyContinue; "
    )
    clean_legacy = (
        "if (Test-Path C:\\workspace\\dist) { "
        "Get-ChildItem -Path C:\\workspace\\dist -Filter '*-amd64*' -ErrorAction SilentlyContinue | Remove-Item -Force }; "
    )
    path_init = "$env:PATH = \"$env:USERPROFILE\\.cargo\\bin;C:\\Users\\vagrant\\.cargo\\bin;$env:PATH\"; "

    vs_shell_init = (
        "if (Test-Path 'C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\Common7\\Tools\\Launch-VsDevShell.ps1') { "
        "& 'C:\\Program Files (x86)\\Microsoft Visual Studio\\2022\\BuildTools\\Common7\\Tools\\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64 | Out-Null }; "
    )

    cache_init = (
        "if (Test-Path C:\\forge-cache) { "
        "$env:CARGO_HOME='C:\\forge-cache\\cargo'; $env:GOMODCACHE='C:\\forge-cache\\go\\pkg\\mod'; $env:PIP_CACHE_DIR='C:\\forge-cache\\pip'; $env:GRADLE_USER_HOME='C:\\forge-cache\\gradle'; "
        "New-Item -ItemType Directory -Path C:\\forge-cache\\cargo, C:\\forge-cache\\go\\pkg\\mod, C:\\forge-cache\\pip, C:\\forge-cache\\gradle -Force | Out-Null }; "
    )

    init_prefix = f"{defender_bypass}{clean_legacy}{path_init}{link_ps}{clean_ps}{cache_init}"

    app_name = extract_project_name(project_path)
    if (project_path / "src-tauri" / "Cargo.toml").is_file():
        gui_name = extract_project_name(project_path / "src-tauri")
    else:
        gui_name = f"{app_name}-gui"

    use_nuitka = not pyinstaller and compiler == "nuitka"
    wix_ver = ver_info.wix if ver_info else "1.0.0"
    raw_ver = ver_info.raw if ver_info else "0.1.0"
    branch = ver_info.branch if ver_info else ""

    if is_test_mode:
        if ptype.kind in (ProjectTypeKind.RUST, ProjectTypeKind.RUST_TAURI):
            build_ps = (
                f"{init_prefix}Set-Location C:\\workspace; $env:CARGO_TARGET_DIR='C:\\target'; "
                f"if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; "
                f"Write-Host '=== [dev-forge : Windows] Compilando suite de testing para {app_name} ==='; "
                f"cargo test --no-run --release; "
                f"$testBin = Get-ChildItem -Path C:\\target\\release\\deps -Filter '*.exe' -ErrorAction SilentlyContinue | Where-Object {{ $_.Name -like '{app_name}-*.exe' }} | Select-Object -First 1; "
                f"if (-not $testBin) {{ $testBin = Get-ChildItem -Path C:\\target\\release\\deps -Filter '*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1 }}; "
                f"if ($testBin) {{ "
                f"  Copy-Item $testBin.FullName 'C:\\workspace\\dist\\{app_name}-test-windows.x86_64.exe' -Force; "
                f"  Copy-Item 'C:\\workspace\\dist\\{app_name}-test-windows.x86_64.exe' 'C:\\workspace\\dist\\{app_name}-test-{raw_ver}-windows.x86_64.exe' -Force; "
                f"  Write-Host \"[dev-forge : Windows] Binario de prueba generado: C:\\workspace\\dist\\{app_name}-test-windows.x86_64.exe ({raw_ver})\"; "
                f"}}"
            )
        elif ptype.kind == ProjectTypeKind.GO:
            build_ps = (
                f"{init_prefix}Set-Location C:\\workspace; if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; "
                f"Write-Host '=== [dev-forge : Windows] Compilando suite de testing Go para {app_name} ==='; "
                f"go test -c -o 'C:\\workspace\\dist\\{app_name}-test-windows.x86_64.exe' . ; "
                f"Copy-Item 'C:\\workspace\\dist\\{app_name}-test-windows.x86_64.exe' 'C:\\workspace\\dist\\{app_name}-test-{raw_ver}-windows.x86_64.exe' -Force"
            )
        elif ptype.kind == ProjectTypeKind.PYTHON:
            build_ps = (
                f"{init_prefix}Set-Location C:\\workspace; if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; "
                f"Write-Host '=== [dev-forge : Windows] Verificando tests Python ==='; "
                f"python -m unittest discover tests 2>&1 | Tee-Object C:\\workspace\\dist\\test-results-windows.log"
            )
        else:
            build_ps = f"{init_prefix}Set-Location C:\\workspace; Write-Host '[dev-forge : Windows] Testing no configurado para este tipo de proyecto.'"
    else:
        build_cli = component in ("all", "cli")
        build_gui = component in ("all", "gui")

        if ptype.kind == ProjectTypeKind.RUST_TAURI:
            is_single = package == "single"
            tauri_no_bundle_opt = " --no-bundle" if package in ("single", "bin") else ""
            copy_bundles_ps = (
                "@('src-tauri\\target\\release\\bundle', 'target\\release\\bundle', 'C:\\target\\release\\bundle') | ForEach-Object { if (Test-Path $_) { Copy-Item -Recurse \"$_\\*\" C:\\workspace\\dist\\ -Force -ErrorAction SilentlyContinue } }; "
                if package in ("all", "bundle")
                else ""
            )
            cp_cli_canonical = "" if is_single else f"  Copy-Item 'C:\\target\\release\\{app_name}.exe' 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' -Force; "
            cli_part = (
                f"cargo build --release; "
                f"if (Test-Path 'C:\\target\\release\\{app_name}.exe') {{ "
                f"{cp_cli_canonical}"
                f"  Copy-Item 'C:\\target\\release\\{app_name}.exe' 'C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe' -Force; "
                f"}}; "
                if build_cli
                else ""
            )
            cp_gui_canonical = "" if is_single else f"Copy-Item $guiSource 'C:\\workspace\\dist\\{app_name}-gui-windows.x86_64.exe' -Force; "
            gui_part = (
                f"$frontendDir = $null; "
                f"if (Test-Path 'C:\\workspace\\ui\\package.json') {{ $frontendDir = 'C:\\workspace\\ui' }} "
                f"elseif (Test-Path 'C:\\workspace\\frontend\\package.json') {{ $frontendDir = 'C:\\workspace\\frontend' }} "
                f"elseif (Test-Path 'C:\\workspace\\package.json') {{ $frontendDir = 'C:\\workspace' }}; "
                f"if ($frontendDir) {{ "
                f"  Write-Host '[dev-forge : Windows] Compilando frontend web para la aplicacion GUI...' -ForegroundColor Cyan; "
                f"  $localUi = \"$env:TEMP\\build_ui\"; "
                f"  if (Test-Path $localUi) {{ Remove-Item -Recurse -Force $localUi 2>$null }}; "
                f"  Copy-Item -Path $frontendDir -Destination $localUi -Recurse -Force; "
                f"  Push-Location $localUi; "
                f"  if (Get-Command npm.cmd -ErrorAction SilentlyContinue) {{ npm run build 2>&1 | Out-Host }} "
                f"  elseif (Get-Command npm -ErrorAction SilentlyContinue) {{ npm run build 2>&1 | Out-Host }}; "
                f"  Pop-Location; "
                f"  if (Test-Path \"$localUi\\dist\") {{ "
                f"    if (-not (Test-Path \"$frontendDir\\dist\")) {{ New-Item -ItemType Directory -Path \"$frontendDir\\dist\" -Force | Out-Null }}; "
                f"    Copy-Item -Path \"$localUi\\dist\\*\" -Destination \"$frontendDir\\dist\" -Recurse -Force; "
                f"  }}; "
                f"}}; "
                f"$env:DISABLE_WINRES = '1'; "
                f"$env:NO_STRIP = 'true'; "
                f"$tauriBuildSuccess = $false; "
                f"if (Get-Command cargo-tauri.exe -ErrorAction SilentlyContinue) {{ "
                f"  Write-Host '[dev-forge : Windows] Ejecutando cargo-tauri build...' -ForegroundColor Cyan; "
                f"  cargo tauri build{tauri_no_bundle_opt} 2>&1 | Out-Host; "
                f"  if ($LASTEXITCODE -eq 0) {{ $tauriBuildSuccess = $true }}; "
                f"}}; "
                f"if (-not $tauriBuildSuccess) {{ "
                f"  if (Test-Path 'C:\\workspace\\src-tauri\\Cargo.toml') {{ "
                f"    Write-Host '[dev-forge : Windows] Compilando crate GUI en src-tauri mediante Cargo...' -ForegroundColor Cyan; "
                f"    cargo build --release --manifest-path 'C:\\workspace\\src-tauri\\Cargo.toml' 2>&1 | Out-Host; "
                f"  }} else {{ "
                f"    cargo build --release 2>&1 | Out-Host; "
                f"  }}; "
                f"}}; "
                f"$cliExePath = 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe'; "
                f"$cliHash = if (Test-Path $cliExePath) {{ (Get-FileHash $cliExePath -Algorithm SHA256).Hash }} else {{ '' }}; "
                f"$guiSource = $null; "
                f"if (Test-Path 'C:\\target\\release\\{gui_name}.exe') {{ "
                f"  $h = (Get-FileHash 'C:\\target\\release\\{gui_name}.exe' -Algorithm SHA256).Hash; "
                f"  if ($h -ne $cliHash) {{ $guiSource = 'C:\\target\\release\\{gui_name}.exe' }}; "
                f"}}; "
                f"if (-not $guiSource -and (Test-Path 'src-tauri\\target\\release\\{gui_name}.exe')) {{ "
                f"  $h = (Get-FileHash 'src-tauri\\target\\release\\{gui_name}.exe' -Algorithm SHA256).Hash; "
                f"  if ($h -ne $cliHash) {{ $guiSource = 'src-tauri\\target\\release\\{gui_name}.exe' }}; "
                f"}}; "
                f"if (-not $guiSource) {{ "
                f"  $candidates = Get-ChildItem -Path @('C:\\target\\release', 'src-tauri\\target\\release') -Filter '*.exe' -Recurse -ErrorAction SilentlyContinue | Where-Object {{ "
                f"    $_.FullName -notmatch '[\\\\/](deps|build|incremental|examples)[\\\\/]' -and "
                f"    $_.Name -notmatch '(?i)(cargo|rustc|-cli-|^vc_)' -and "
                f"    $_.Name -ne '{app_name}.exe' -and "
                f"    $_.Name -ne '{app_name}-cli-windows.x86_64.exe' "
                f"  }}; "
                f"  foreach ($cand in $candidates) {{ "
                f"    $candHash = (Get-FileHash $cand.FullName -Algorithm SHA256).Hash; "
                f"    if ($candHash -ne $cliHash) {{ "
                f"      $guiSource = $cand.FullName; "
                f"      break; "
                f"    }}; "
                f"  }}; "
                f"}}; "
                f"if (-not $guiSource) {{ "
                f"  Write-Error '[dev-forge : Windows : ERROR FATAL] No se pudo generar ni validar el binario GUI de Tauri en src-tauri. Se rechaza usar el binario CLI como sustituto.'; "
                f"  exit 1; "
                f"}}; "
                f"{cp_gui_canonical}"
                f"Copy-Item $guiSource 'C:\\workspace\\dist\\{app_name}-gui-{raw_ver}-windows.x86_64.exe' -Force; "
                f"{copy_bundles_ps}"
                if build_gui
                else ""
            )
            build_ps = f"{init_prefix}Set-Location C:\\workspace; $env:CARGO_TARGET_DIR='C:\\target'; if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; {cli_part}{gui_part}"
        elif ptype.kind == ProjectTypeKind.RUST:
            if component == "gui":
                build_ps = f"{init_prefix}Write-Host '[dev-forge : Windows] GUI no aplicable para proyecto Rust estándar.'"
            else:
                cp_rust_canonical = "" if package == "single" else f"  Copy-Item 'C:\\target\\release\\{app_name}.exe' 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' -Force; "
                build_ps = (
                    f"{init_prefix}Set-Location C:\\workspace; $env:CARGO_TARGET_DIR='C:\\target'; cargo build --release; "
                    f"if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; "
                    f"if (Test-Path 'C:\\target\\release\\{app_name}.exe') {{ "
                    f"{cp_rust_canonical}"
                    f"  Copy-Item 'C:\\target\\release\\{app_name}.exe' 'C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe' -Force; "
                    f"}}"
                )
        elif ptype.kind == ProjectTypeKind.PYTHON:
            if use_nuitka:
                py_cmd = (
                    f"if (Test-Path main.py) {{ "
                    f"$ico = & C:\\forge\\provision\\windows\\package-artifacts.ps1 -FindIconOnly -WorkspaceDir C:\\workspace -TargetDir C:\\target; "
                    f"$icoOpt = if ($ico) {{ \"--windows-icon-from-ico='$ico'\" }} else {{ '' }}; "
                    f"Invoke-Expression \"nuitka --standalone --onefile --output-dir=C:\\target\\nuitka-out $icoOpt --product-version='{wix_ver}' --file-version='{wix_ver}' --assume-yes-for-downloads main.py -o {app_name}-cli-windows.x86_64.exe 2>&1\" | Out-Host; "
                    f"if (Test-Path C:\\target\\nuitka-out\\{app_name}-cli-windows.x86_64.exe) {{ "
                    f"  Copy-Item C:\\target\\nuitka-out\\{app_name}-cli-windows.x86_64.exe C:\\workspace\\dist\\ -Force; "
                    f"  Copy-Item C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe -Force; exit 0 "
                    f"}} else {{ "
                    f"Invoke-Expression \"python -m PyInstaller --clean -F --name {app_name}-cli-windows.x86_64 main.py --distpath C:\\workspace\\dist 2>&1\" | Out-Host; "
                    f"if (Test-Path C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe) {{ "
                    f"  Copy-Item C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe -Force; exit 0 "
                    f"}} else {{ exit 1 }} }} }} else {{ python -m build -o C:\\workspace\\dist }}"
                )
            else:
                py_cmd = (
                    f"if (Test-Path main.py) {{ "
                    f"$ico = & C:\\forge\\provision\\windows\\package-artifacts.ps1 -FindIconOnly -WorkspaceDir C:\\workspace -TargetDir C:\\target; "
                    f"$icoOpt = if ($ico) {{ \"--icon '$ico'\" }} else {{ '' }}; "
                    f"Invoke-Expression \"python -m PyInstaller --clean -F --name {app_name}-cli-windows.x86_64 $icoOpt main.py --distpath C:\\workspace\\dist 2>&1\" | Out-Host; "
                    f"if (Test-Path C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe) {{ "
                    f"  Copy-Item C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe -Force; exit 0 "
                    f"}} else {{ exit 1 }} }} else {{ python -m build -o C:\\workspace\\dist }}"
                )
            build_ps = f"{init_prefix}Set-Location C:\\workspace; if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; {py_cmd}"
        elif ptype.kind == ProjectTypeKind.CCPP:
            build_ps = (
                f"{init_prefix}{vs_shell_init}Set-Location C:\\workspace; cmake -B C:\\target -S . -G Ninja; cmake --build C:\\target; "
                f"if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; "
                f"Get-ChildItem -Path C:\\target -Filter '*.exe' -Recurse | Where-Object {{ $_.Name -notmatch '(?i)(ninja|compiler)' }} | Select-Object -First 1 | Copy-Item -Destination 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' -Force; "
                f"if (Test-Path 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe') {{ Copy-Item 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' 'C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe' -Force }}"
            )
        elif ptype.kind == ProjectTypeKind.GO:
            build_ps = (
                f"{init_prefix}Set-Location C:\\workspace; "
                f"if (-not (Test-Path C:\\workspace\\dist)) {{ New-Item -ItemType Directory -Path C:\\workspace\\dist -Force | Out-Null }}; "
                f"go build -o 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' . ; "
                f"if (-not (Test-Path 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe')) {{ go build -o 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' ./... }}; "
                f"if (Test-Path 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe') {{ Copy-Item 'C:\\workspace\\dist\\{app_name}-cli-windows.x86_64.exe' 'C:\\workspace\\dist\\{app_name}-cli-{raw_ver}-windows.x86_64.exe' -Force }}"
            )
        else:
            build_ps = (
                f"{init_prefix}Set-Location C:\\workspace; if (Test-Path .\\build.bat) {{ .\\build.bat }}"
            )

    pack_ps = (
        ""
        if (package == "bin" or is_test_mode)
        else (
            f"; if (Test-Path 'C:\\forge\\provision\\windows\\package-artifacts.ps1') {{ "
            f"& 'C:\\forge\\provision\\windows\\package-artifacts.ps1' -DistDir 'C:\\workspace\\dist' -TargetDir 'C:\\target' -WorkspaceDir 'C:\\workspace' "
            f"-AppVersion '{raw_ver}' -WixVersion '{wix_ver}' -GitBranch '{branch}' }}"
        )
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


def cmd_runner(args) -> None:
    """Manage isolated CI/CD runner VM."""
    action = args.runner_action
    if action == "up":
        log_info("Iniciando maquina virtual aislada 'forge-runner'...")
        cmd_up("forge-runner", provision=args.provision)
    elif action == "halt":
        log_info("Deteniendo maquina virtual 'forge-runner'...")
        cmd_halt("forge-runner", force=args.force)
    elif action == "status":
        run_vagrant_command(["status", "forge-runner"])
    elif action == "ssh":
        cmd_ssh("forge-runner", command=args.command)
    elif action == "register":
        log_info(f"Registrando runner contra {args.url}...")
        reg_cmd = f"sudo register-runner '{args.token}' '{args.url}'"
        cmd_ssh("forge-runner", command=reg_cmd)
    elif action == "start-gitlab":
        log_info("Iniciando contenedor local de GitLab CE en 'forge-runner'...")
        cmd_ssh("forge-runner", command="sudo start-gitlab-server")
        log_ok("GitLab CE iniciado en http://localhost:8080 (puerto guest: 80).")


def cmd_box(args) -> None:
    """Manage and package pre-baked VirtualBox custom boxes (VDI format)."""
    action = args.box_action
    forge_dir = get_forge_dir()

    if action == "package":
        machine = args.machine
        version = args.version
        out_dir = args.out_dir
        log_info(f"Iniciando empaquetado VDI para '{machine}' (v{version})...")
        script_path = forge_dir / "scripts" / "package-box-vdi.sh"
        cmd = ["bash", str(script_path), machine, version]
        if out_dir:
            cmd.append(str(out_dir))
        proc = subprocess.run(cmd, cwd=forge_dir)
        if proc.returncode != 0:
            log_err("Fallo en el proceso de empaquetado de box.")
            sys.exit(1)

    elif action == "install":
        machine = args.machine
        actual_machine = "forge-linux" if machine in ("linux", "forge-linux") else ("forge-windows" if machine in ("windows", "forge-windows") else ("forge-runner" if machine in ("runner", "forge-runner") else machine))
        box_file = args.box_file
        if not box_file:
            candidates = [
                Path.home() / ".dev-forge" / "boxes",
                forge_dir / "dist" / "boxes",
            ]
            found = None
            for d in candidates:
                if d.is_dir():
                    for f in d.glob(f"dev-forge-{actual_machine}*.box"):
                        found = f
                        break
                if found:
                    break
            if not found:
                log_err(f"No se encontró ningún archivo .box para '{actual_machine}'. Genera uno primero con: dev-forge box package {actual_machine}")
                sys.exit(1)
            box_file = found

        box_tag = f"olorinj/{actual_machine}"
        log_info(f"Registrando box local '{box_tag}' desde: {box_file}...")
        success = run_vagrant_streaming(["box", "add", box_tag, str(box_file), "--force"])
        if success:
            log_ok(f"Box '{box_tag}' instalada localmente con éxito en Vagrant.")
        else:
            log_err("Fallo al registrar la box en Vagrant.")
            sys.exit(1)

    elif action == "list":
        log_info("Consultando boxes de DevForge instaladas en Vagrant...")
        run_vagrant_streaming(["box", "list"])
