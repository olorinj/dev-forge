"""Diagnostic doctor suite for dev-forge environment and prerequisites."""

import os
import platform
import shutil
import socket
import subprocess
import sys
from pathlib import Path
from dev_forge.banner import log_err, log_info, log_ok
from dev_forge.config import get_user_config_dir
from dev_forge.hardware import detect_hardware


def run_doctor() -> None:
    """Execute complete environment diagnostic suite."""
    print("\033[1;36m=== [dev-forge doctor] Diagnóstico del Entorno Multi-Plataforma (Motor Python) ===\033[0m\n")

    pass_count = 0
    warn_count = 0
    fail_count = 0

    def pass_msg(msg: str):
        nonlocal pass_count
        pass_count += 1
        print(f"  \033[32m✔ PASS:\033[0m {msg}")

    def warn_msg(msg: str):
        nonlocal warn_count
        warn_count += 1
        print(f"  \033[33m⚠ WARN:\033[0m {msg}")

    def fail_msg(msg: str):
        nonlocal fail_count
        fail_count += 1
        print(f"  \033[31m✘ FAIL:\033[0m {msg}")

    # 1. Virtualización CPU
    print("\033[1;33m1. Diagnóstico de Procesador y Virtualización:\033[0m")
    if sys.platform.startswith("linux"):
        try:
            cpuinfo = Path("/proc/cpuinfo").read_text()
            if " vmx " in cpuinfo or "\nflags\t\t: vmx " in cpuinfo:
                pass_msg("Aceleración por hardware habilitada en CPU: Intel VT-x (VMX)")
            elif " svm " in cpuinfo or "\nflags\t\t: svm " in cpuinfo:
                pass_msg("Aceleración por hardware habilitada en CPU: AMD-V (SVM)")
            else:
                fail_msg("No se detectó virtualización por hardware en /proc/cpuinfo. Habilita VT-x/AMD-V en BIOS/UEFI.")
        except Exception:
            warn_msg("No se pudo leer /proc/cpuinfo")
    elif sys.platform == "darwin":
        try:
            out = subprocess.check_output(["sysctl", "-n", "kern.hv_support"], text=True).strip()
            if out == "1":
                pass_msg("Apple Hypervisor Framework soportado por el hardware")
            else:
                warn_msg(f"kern.hv_support retornó '{out}'")
        except Exception:
            warn_msg("No se pudo verificar kern.hv_support")
    else:
        pass_msg("Verificación de hardware de virtualización Windows asistida por Hyper-V/VBox")

    # 2. Memoria RAM
    print("\n\033[1;33m2. Diagnóstico de Memoria RAM y Recursos:\033[0m")
    hw = detect_hardware()
    ram_gb = hw.total_ram_mb / 1024.0
    if ram_gb >= 15.0:
        pass_msg(f"Memoria RAM del host: {ram_gb:.1f} GB (Óptima para compilaciones concurrentes)")
    elif ram_gb >= 7.5:
        pass_msg(f"Memoria RAM del host: {ram_gb:.1f} GB (Adecuada con exclusión mutua de VMs activa)")
    else:
        warn_msg(f"Memoria RAM del host ajustada: {ram_gb:.1f} GB (Recomendado cerrar navegadores/IDE durante el build)")

    # 3. Espacio en disco
    print("\n\033[1;33m3. Diagnóstico de Almacenamiento y Espacio Libre:\033[0m")
    try:
        user_dir = get_user_config_dir()
        disk_target = user_dir if user_dir.exists() else Path.home()
        total, used, free = shutil.disk_usage(disk_target)
        free_gb = free / (1024**3)
        total_gb = total / (1024**3)
        if free_gb >= 20.0:
            pass_msg(f"Espacio libre en disco ({disk_target}): {free_gb:.1f} GB libres de {total_gb:.1f} GB")
        elif free_gb >= 10.0:
            warn_msg(f"Espacio en disco moderado: {free_gb:.1f} GB libres (Recomendado >20 GB para imágenes y cachés)")
        else:
            fail_msg(f"Espacio en disco crítico: {free_gb:.1f} GB libres. Se requiere liberar espacio.")
    except Exception as e:
        warn_msg(f"No se pudo determinar el espacio libre en disco: {e}")

    # 4. Hipervisor & CLI
    print("\n\033[1;33m4. Diagnóstico de Hipervisor y Herramientas CLI:\033[0m")
    vbox = shutil.which("VBoxManage")
    if vbox:
        try:
            ver = subprocess.check_output([vbox, "--version"], text=True).strip()
            pass_msg(f"Oracle VirtualBox CLI (VBoxManage): v{ver}")
        except Exception:
            pass_msg(f"Oracle VirtualBox CLI encontrado en: {vbox}")
    else:
        common_paths = [Path("/usr/bin/VBoxManage"), Path("C:/Program Files/Oracle/VirtualBox/VBoxManage.exe")]
        found = next((p for p in common_paths if p.is_file()), None)
        if found:
            pass_msg(f"Oracle VirtualBox encontrado en: {found}")
        else:
            fail_msg("VBoxManage no encontrado en PATH ni en rutas estándar. Instala VirtualBox 7.x.")

    vagrant = shutil.which("vagrant") or (Path("/opt/vagrant/bin/vagrant") if Path("/opt/vagrant/bin/vagrant").is_file() else None)
    if vagrant:
        try:
            ver = subprocess.check_output([str(vagrant), "--version"], text=True).strip()
            pass_msg(f"HashiCorp Vagrant: {ver}")
        except Exception:
            pass_msg(f"HashiCorp Vagrant encontrado en: {vagrant}")
    else:
        fail_msg("Vagrant no encontrado en PATH ni en /opt/vagrant/bin. Instala Vagrant.")

    # 5. Puertos de red
    print("\n\033[1;33m5. Diagnóstico de Puertos de Red y Conectividad:\033[0m")
    running_vms = _get_running_vms()
    linux_running = any("forge-linux" in v or "FORGE-LINUX" in v for v in running_vms)
    win_running = any("forge-windows" in v or "FORGE-WINDOWS" in v for v in running_vms)

    for port, label, is_running in [(2222, "Linux SSH", linux_running), (55985, "Windows WinRM", win_running)]:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", port))
                pass_msg(f"Puerto local {port} ({label}) libre y disponible")
            except OSError:
                if is_running:
                    pass_msg(f"Puerto local {port} en uso legítimo por máquina activa ({label})")
                else:
                    warn_msg(f"Puerto local {port} ocupado por otro proceso del host. Posible colisión de puerto.")

    # 6. Módulos del SO
    print("\n\033[1;33m6. Diagnóstico Específico del Sistema Operativo:\033[0m")
    if sys.platform.startswith("linux"):
        if Path("/dev/vboxdrv").exists():
            pass_msg("Controlador de kernel VirtualBox (/dev/vboxdrv) activo")
        else:
            fail_msg("/dev/vboxdrv no existe. Ejecuta 'sudo /sbin/vboxconfig' para recompilar módulos.")

        if Path("/dev/kvm").exists():
            pass_msg("Interfaz KVM (/dev/kvm) presente para paravirtualización acelerada")
    elif sys.platform == "win32":
        pass_msg("Entorno host Windows verificado")
    elif sys.platform == "darwin":
        pass_msg("Entorno host macOS verificado")

    # 7. VMs y Caché
    print("\n\033[1;33m7. Estado de Máquinas Virtuales y Caché Persistente:\033[0m")
    reg_vms = _get_registered_vms()
    if any("forge-linux" in v or "FORGE-LINUX" in v for v in reg_vms):
        pass_msg("Máquina 'forge-linux' registrada en VirtualBox")
    else:
        print("  \033[36mℹ INFO:\033[0m Máquina 'forge-linux' aún no creada (se creará en el primer build)")

    if any("forge-windows" in v or "FORGE-WINDOWS" in v for v in reg_vms):
        pass_msg("Máquina 'forge-windows' registrada en VirtualBox")
    else:
        print("  \033[36mℹ INFO:\033[0m Máquina 'forge-windows' aún no creada (se creará en el primer build)")

    cache_dir = get_user_config_dir() / "cache"
    if cache_dir.is_dir():
        from dev_forge.cache import get_dir_size
        size_mb = get_dir_size(cache_dir) / (1024**2)
        pass_msg(f"Caché persistente del host activa en {cache_dir}: {size_mb:.2f} MB")
    else:
        print(f"  \033[36mℹ INFO:\033[0m Directorio de caché {cache_dir} se inicializará automáticamente")

    # Resumen
    print("\n\033[1;36m=========================================================\033[0m")
    print(f" RESUMEN DEL DOCTOR: Superados: \033[32m{pass_count}\033[0m | Advertencias: \033[33m{warn_count}\033[0m | Fallidos: \033[31m{fail_count}\033[0m")
    print("\033[1;36m=========================================================\033[0m")

    if fail_count > 0:
        log_err("dev-forge doctor detectó problemas críticos que requieren atención.")
        sys.exit(1)


def _get_running_vms():
    try:
        out = subprocess.check_output(["VBoxManage", "list", "runningvms"], text=True, stderr=subprocess.DEVNULL)
        return out.splitlines()
    except Exception:
        return []


def _get_registered_vms():
    try:
        out = subprocess.check_output(["VBoxManage", "list", "vms"], text=True, stderr=subprocess.DEVNULL)
        return out.splitlines()
    except Exception:
        return []
