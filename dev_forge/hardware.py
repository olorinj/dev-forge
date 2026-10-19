"""Cross-platform hardware detection for dev-forge."""

import os
import platform
import subprocess
import sys
from dataclasses import dataclass


@dataclass
class HardwareProfile:
    physical_cores: int
    logical_cores: int
    total_ram_mb: int
    available_ram_mb: int
    keyboard_layout: str
    is_ssd: bool
    platform_name: str


def get_total_ram_mb() -> int:
    """Detect total system physical RAM in Megabytes."""
    if sys.platform == "win32":
        try:
            import ctypes

            class MemoryStatusEx(ctypes.Structure):
                _fields_ = [
                    ("dwLength", ctypes.c_ulong),
                    ("dwMemoryLoad", ctypes.c_ulong),
                    ("ullTotalPhys", ctypes.c_ulonglong),
                    ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong),
                    ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong),
                    ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("sullAvailExtendedVirtual", ctypes.c_ulonglong),
                ]

            stat = MemoryStatusEx()
            stat.dwLength = ctypes.sizeof(MemoryStatusEx)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(stat)):
                return int(stat.ullTotalPhys / (1024 * 1024))
        except Exception:
            pass
        return 8192

    elif sys.platform == "darwin":
        try:
            out = subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True)
            return int(int(out.strip()) / (1024 * 1024))
        except Exception:
            return 8192

    else:
        # Linux
        try:
            with open("/proc/meminfo", "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        parts = line.split()
                        return int(int(parts[1]) / 1024)
        except Exception:
            pass
        try:
            pages = os.sysconf("SC_PHYS_PAGES")
            page_size = os.sysconf("SC_PAGE_SIZE")
            return int((pages * page_size) / (1024 * 1024))
        except Exception:
            return 8192


def get_keyboard_layout() -> str:
    """Detect host primary keyboard layout."""
    if sys.platform == "win32":
        try:
            cmd = "powershell -NoProfile -Command \"(Get-WinUserLanguageList)[0].LanguageTag\""
            out = subprocess.check_output(cmd, shell=True, text=True).strip().lower()
            if "es" in out:
                return "es"
            if "en" in out:
                return "us"
            return out.split("-")[0] if out else "es"
        except Exception:
            return "es"
    elif sys.platform == "darwin":
        return "es"
    else:
        # Linux
        for cmd in [
            ["localectl", "status"],
            ["setxkbmap", "-query"],
        ]:
            try:
                out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
                for line in out.splitlines():
                    if "X11 Layout:" in line or "layout:" in line:
                        layout = line.split(":")[-1].strip().split(",")[0]
                        if layout:
                            return layout
            except Exception:
                continue
        # Fallback to LANG/LC_ALL
        lang = os.environ.get("LANG", os.environ.get("LC_ALL", "")).lower()
        if "es" in lang:
            return "es"
        if "en" in lang:
            return "us"
        return "es"


def detect_hardware() -> HardwareProfile:
    """Analyze host hardware to determine optimal VM resource limits."""
    logical_cores = os.cpu_count() or 4
    # Estimate physical cores: logical // 2 or at least 1
    physical_cores = max(1, logical_cores // 2 if logical_cores > 2 else logical_cores)

    total_ram = get_total_ram_mb()
    layout = get_keyboard_layout()
    plat = platform.system().lower()

    return HardwareProfile(
        physical_cores=physical_cores,
        logical_cores=logical_cores,
        total_ram_mb=total_ram,
        available_ram_mb=total_ram,
        keyboard_layout=layout,
        is_ssd=True,
        platform_name=plat,
    )
