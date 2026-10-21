"""Command-line interface parser and dispatcher for dev-forge."""

import argparse
import sys
from pathlib import Path
from dev_forge.banner import print_banner
from dev_forge.config import generate_host_profile
from dev_forge.vagrant import (
    cmd_build,
    cmd_halt,
    cmd_provision,
    cmd_ssh,
    cmd_status,
    cmd_test_vm,
    cmd_up,
)


def create_parser() -> argparse.ArgumentParser:
    """Construct the command-line argument parser."""
    parser = argparse.ArgumentParser(
        prog="dev-forge",
        description="Universal multi-language headless build forge orchestrator (Python Engine)",
    )
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    # 1. tune
    subparsers.add_parser("tune", help="Detect host hardware and dimension optimal VM parameters")

    # 2. status
    subparsers.add_parser("status", help="Show current status of forge virtual machines")

    # 3. up
    up_parser = subparsers.add_parser("up", help="Boot virtual machines in headless mode")
    up_parser.add_argument(
        "machine",
        nargs="?",
        default="forge-linux",
        help="Specific VM to boot (forge-linux | forge-windows)",
    )
    up_parser.add_argument("--provision", action="store_true", help="Force re-provisioning on boot")

    # 4. halt
    halt_parser = subparsers.add_parser("halt", help="Gracefully stop virtual machines to release memory")
    halt_parser.add_argument(
        "machine",
        nargs="?",
        default=None,
        help="Specific VM to stop (forge-linux | forge-windows)",
    )
    halt_parser.add_argument("-f", "--force", action="store_true", help="Force immediate shutdown")

    # 5. provision
    prov_parser = subparsers.add_parser("provision", help="Re-provision build tools inside VMs")
    prov_parser.add_argument(
        "machine",
        nargs="?",
        default=None,
        help="Specific VM to provision (forge-linux | forge-windows)",
    )

    # 6. ssh
    ssh_parser = subparsers.add_parser("ssh", help="Open an interactive shell or execute a remote command")
    ssh_parser.add_argument(
        "machine",
        nargs="?",
        default="forge-linux",
        help="Specific VM (default: forge-linux)",
    )
    ssh_parser.add_argument("-c", "--command", help="Specific command to execute non-interactively")

    # 7. build
    build_parser = subparsers.add_parser("build", help="Compile a target client project inside the VM")
    build_parser.add_argument(
        "-p",
        "--project",
        type=Path,
        required=True,
        help="Path to the client project to compile (mandatory)",
    )
    build_parser.add_argument(
        "-t",
        "--target",
        default=None,
        choices=["linux", "windows", "macos", "all"],
        help="Target destination platform (linux | windows | macos | all)",
    )
    build_parser.add_argument(
        "--component",
        default=None,
        choices=["all", "cli", "gui", "test"],
        help="Component to build (all | cli | gui | test)",
    )
    build_parser.add_argument(
        "--package",
        default=None,
        choices=["all", "bin", "bundle"],
        help="Packaging format (all | bin | bundle)",
    )
    build_parser.add_argument(
        "--profile",
        default=None,
        choices=["release", "debug", "test"],
        help="Build profile (release | debug | test)",
    )
    build_parser.add_argument(
        "--test",
        action="store_true",
        help="Build only testing executables / test runners",
    )
    build_parser.add_argument(
        "-i",
        "--interactive",
        action="store_true",
        help="Force interactive terminal selection menu",
    )
    build_parser.add_argument(
        "-c",
        "--clean",
        action="store_true",
        help="Clean intermediate caches before compilation",
    )
    build_parser.add_argument(
        "-k",
        "--keep-vm",
        action="store_true",
        help="Keep virtual machines running after compilation finishes",
    )
    build_parser.add_argument(
        "-u",
        "--update",
        action="store_true",
        help="Force re-provisioning of packages in the VM prior to building",
    )
    build_parser.add_argument(
        "--compiler",
        default="nuitka",
        choices=["nuitka", "pyinstaller"],
        help="Compiler to use for Python standalone binaries (nuitka | pyinstaller)",
    )
    build_parser.add_argument(
        "--pyinstaller",
        action="store_true",
        help="Convenience flag to force PyInstaller for Python builds",
    )

    # 8. ide
    ide_parser = subparsers.add_parser("ide", help="Open VS Code Remote-SSH session inside VM with development profile")
    ide_parser.add_argument(
        "machine",
        nargs="?",
        default="forge-linux",
        help="Specific VM to connect to (default: forge-linux)",
    )
    ide_parser.add_argument(
        "-p",
        "--profile",
        default="full",
        choices=["rust", "python", "cpp", "web", "full"],
        help="Programming profile with pre-configured extensions and settings",
    )
    ide_parser.add_argument(
        "--project",
        type=Path,
        default=None,
        help="Path to workspace directory on host to bind",
    )
    ide_parser.add_argument(
        "--no-launch",
        action="store_true",
        help="Configure SSH and environment without launching VS Code UI",
    )

    # 9. test-vm
    test_parser = subparsers.add_parser("test-vm", help="Run the in-VM health-check and verification suite")
    test_parser.add_argument(
        "machine",
        nargs="?",
        default="forge-linux",
        help="Specific VM to verify (default: forge-linux)",
    )

    # 9. doctor
    subparsers.add_parser("doctor", help="Diagnose host virtualization, hypervisors and environment health")

    # 10. clean-cache
    cache_parser = subparsers.add_parser("clean-cache", help="Clean persistent host compiler cache (~/.dev-forge/cache)")
    cache_parser.add_argument("-s", "--subsystem", help="Specific subsystem to clean (cargo | go | pip | gradle | sccache)")

    # 11. completions
    comp_parser = subparsers.add_parser("completions", help="Generate shell completions")
    comp_parser.add_argument("shell", choices=["bash", "zsh", "powershell", "fish"])

    return parser


def main(argv=None) -> None:
    """CLI Entrypoint function."""
    print_banner()
    parser = create_parser()
    args = parser.parse_args(argv)

    if args.subcommand == "tune":
        generate_host_profile()
    elif args.subcommand == "status":
        cmd_status()
    elif args.subcommand == "up":
        cmd_up(args.machine, args.provision)
    elif args.subcommand == "halt":
        cmd_halt(args.machine, args.force)
    elif args.subcommand == "provision":
        cmd_provision(args.machine)
    elif args.subcommand == "ssh":
        cmd_ssh(args.machine, args.command)
    elif args.subcommand == "build":
        cmd_build(
            args.project,
            args.target,
            args.clean,
            args.keep_vm,
            args.update,
            compiler=args.compiler,
            pyinstaller=args.pyinstaller,
            component=args.component,
            package=args.package,
            profile=args.profile,
            test=args.test,
            interactive=args.interactive,
        )
    elif args.subcommand == "ide":
        from dev_forge.ide import cmd_ide
        cmd_ide(args.machine, args.profile, args.project, args.no_launch)
    elif args.subcommand == "test-vm":
        cmd_test_vm(args.machine)
    elif args.subcommand == "doctor":
        from dev_forge.doctor import run_doctor
        run_doctor()
    elif args.subcommand == "clean-cache":
        from dev_forge.cache import clean_cache
        clean_cache(args.subsystem)
    elif args.subcommand == "completions":
        print(f"# Completions for {args.shell} are automatically supported via dev-forge")
