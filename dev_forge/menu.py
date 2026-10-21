"""Interactive Terminal Selection Menu for dev-forge build orchestrator."""

from __future__ import annotations

import sys
from typing import Any


def prompt_menu(args: Any) -> None:
    """Prompts an interactive terminal menu allowing the user to select
    Component, Target OS, Packaging format, and Build Profile."""
    print("\n\033[1;36m================================================================\033[0m")
    print("\033[1;36m       dev-forge : Menú de Compilación Interactivo\033[0m")
    print("\033[1;36m================================================================\033[0m")
    print(f"Proyecto a procesar: \033[1m{args.project}\033[0m")

    # 1. Component Selection
    if not getattr(args, "component", None) and not getattr(args, "test", False):
        print("\n\033[1;33m? [1/4] Seleccione el tipo de artefacto a compilar:\033[0m")
        print("  [1] Todos los componentes (CLI + GUI) \033[2m[Predeterminado]\033[0m")
        print("  [2] Solo ejecutable CLI")
        print("  [3] Solo aplicación GUI (Desktop)")
        print("  [4] Solo ejecutables de Testing / Pruebas (Test runners)")
        try:
            choice = input("\033[1mOpción [1-4] (Intro para opción 1): \033[0m").strip()
        except (EOFError, KeyboardInterrupt):
            choice = "1"

        if choice == "2":
            args.component = "cli"
        elif choice == "3":
            args.component = "gui"
        elif choice == "4":
            args.component = "test"
            args.test = True
        else:
            args.component = "all"

    # 2. Target OS Selection
    if not getattr(args, "target", None):
        print("\n\033[1;33m? [2/4] Seleccione el Sistema Operativo destino:\033[0m")
        print("  [1] Todos los sistemas (Linux, Windows, macOS) \033[2m[Predeterminado]\033[0m")
        print("  [2] Solo Linux")
        print("  [3] Solo Windows")
        print("  [4] Solo macOS")
        try:
            choice = input("\033[1mOpción [1-4] (Intro para opción 1): \033[0m").strip()
        except (EOFError, KeyboardInterrupt):
            choice = "1"

        if choice == "2":
            args.target = "linux"
        elif choice == "3":
            args.target = "windows"
        elif choice == "4":
            args.target = "macos"
        else:
            args.target = "all"

    # 3. Packaging format
    if not getattr(args, "package", None):
        print("\n\033[1;33m? [3/4] Seleccione el formato de salida / empaquetado:\033[0m")
        print("  [1] Binarios directos + Paquetes/Instaladores (AppImage, deb, rpm, MSI, Inno, DMG) \033[2m[Predeterminado]\033[0m")
        print("  [2] Solo binarios directos (rápido, sin generadores de instaladores)")
        print("  [3] Solo paquetes e instaladores")
        try:
            choice = input("\033[1mOpción [1-3] (Intro para opción 1): \033[0m").strip()
        except (EOFError, KeyboardInterrupt):
            choice = "1"

        if choice == "2":
            args.package = "bin"
        elif choice == "3":
            args.package = "bundle"
        else:
            args.package = "all"

    # 4. Build Profile
    if not getattr(args, "profile", None):
        print("\n\033[1;33m? [4/4] Seleccione el modo de compilación:\033[0m")
        print("  [1] Release (Producción, optimizado) \033[2m[Predeterminado]\033[0m")
        print("  [2] Testing / Debug (Rápido, con símbolos y aserciones)")
        try:
            choice = input("\033[1mOpción [1-2] (Intro para opción 1): \033[0m").strip()
        except (EOFError, KeyboardInterrupt):
            choice = "1"

        if choice == "2":
            args.profile = "test"
        else:
            args.profile = "release"

    print("\033[2m----------------------------------------------------------------\033[0m\n")

