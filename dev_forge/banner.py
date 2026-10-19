"""Cross-platform ANSI banner and styling utilities for dev-forge."""

import os
import sys

# 7-bit ASCII banner guaranteeing exact visual representation across Win/Mac/Linux
ASCII_BANNER = r"""  ================================================================
     ____  _______     __     _____ ___  ____   ____ _____ 
    |  _ \| ____\ \   / /    |  ___/ _ \|  _ \ / ___| ____|
    | | | |  _|  \ \ / /_____| |_ | | | | |_) | |  _|  _|  
    | |_| | |___  \ V /|_____|  _|| |_| |  _ <| |_| | |___ 
    |____/|_____|  \_/       |_|   \___/|_| \_\\____|_____|
  ================================================================
       Universal Multi-Language Offline Build Forge (Python)
"""

# ANSI Color escapes
RESET = "\033[0m"
BOLD = "\033[1m"
GREEN = "\033[32m"
RED = "\033[31m"
YELLOW = "\033[33m"
CYAN = "\033[36m"


def init_terminal() -> None:
    """Initialize virtual terminal processing on Windows if supported."""
    if sys.platform == "win32":
        try:
            import ctypes
            from ctypes import wintypes

            kernel32 = ctypes.windll.kernel32
            handle = kernel32.GetStdHandle(-11)  # STD_OUTPUT_HANDLE = -11
            mode = wintypes.DWORD()
            if kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
                # ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
                kernel32.SetConsoleMode(handle, mode.value | 0x0004)
        except Exception:
            pass


def print_banner() -> None:
    """Print the stylized 7-bit ASCII banner."""
    init_terminal()
    sys.stdout.write(f"{CYAN}{BOLD}{ASCII_BANNER}{RESET}\n")
    sys.stdout.flush()


def log_info(msg: str) -> None:
    """Log an informational message."""
    sys.stdout.write(f"{CYAN}[dev-forge]{RESET} {msg}\n")
    sys.stdout.flush()


def log_ok(msg: str) -> None:
    """Log a success message."""
    sys.stdout.write(f"{GREEN}[dev-forge : OK]{RESET} {msg}\n")
    sys.stdout.flush()


def log_warn(msg: str) -> None:
    """Log a warning message to stderr."""
    sys.stderr.write(f"{YELLOW}[dev-forge : AVISO]{RESET} {msg}\n")
    sys.stderr.flush()


def log_err(msg: str) -> None:
    """Log an error message to stderr."""
    sys.stderr.write(f"{RED}[dev-forge : ERROR]{RESET} {msg}\n")
    sys.stderr.flush()
