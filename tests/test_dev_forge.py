"""Unit tests for Python dev_forge orchestrator using unittest."""

import tempfile
import unittest
from pathlib import Path
from dev_forge.detector import ProjectTypeKind, PythonManager, detect_project_type
from dev_forge.hardware import detect_hardware


class TestDevForge(unittest.TestCase):
    def test_hardware_detection(self):
        hw = detect_hardware()
        self.assertGreaterEqual(hw.logical_cores, 1)
        self.assertGreaterEqual(hw.physical_cores, 1)
        self.assertGreater(hw.total_ram_mb, 1024)
        self.assertNotEqual(hw.keyboard_layout, "")

    def test_detect_rust_project(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / "Cargo.toml").write_text('[package]\nname = "test-pkg"\nversion = "0.1.0"', encoding="utf-8")
            pt = detect_project_type(p)
            self.assertEqual(pt.kind, ProjectTypeKind.RUST)

    def test_detect_python_uv(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / "uv.lock").write_text("# uv lockfile", encoding="utf-8")
            pt = detect_project_type(p)
            self.assertEqual(pt.kind, ProjectTypeKind.PYTHON)
            self.assertIsNotNone(pt.python_details)
            self.assertEqual(pt.python_details.manager, PythonManager.UV)

    def test_detect_python_multipython(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / "requirements.txt").write_text("pytest\n", encoding="utf-8")
            (p / "tox.ini").write_text("[tox]\nenvlist = py310,py311\n", encoding="utf-8")
            pt = detect_project_type(p)
            self.assertEqual(pt.kind, ProjectTypeKind.PYTHON)
            self.assertIsNotNone(pt.python_details)
            self.assertTrue(pt.python_details.is_multipython)
            self.assertEqual(pt.python_details.matrix_tool, "tox")

    def test_detect_c_cpp(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / "CMakeLists.txt").write_text("cmake_minimum_required(VERSION 3.10)\nproject(demo C)", encoding="utf-8")
            pt = detect_project_type(p)
            self.assertEqual(pt.kind, ProjectTypeKind.CCPP)

    def test_detect_go(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / "go.mod").write_text("module demo\n\ngo 1.23\n", encoding="utf-8")
            pt = detect_project_type(p)
            self.assertEqual(pt.kind, ProjectTypeKind.GO)

    def test_detect_node(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / "package.json").write_text('{"name": "demo", "version": "1.0.0"}', encoding="utf-8")
            pt = detect_project_type(p)
            self.assertEqual(pt.kind, ProjectTypeKind.NODE)

    def test_cache_size_calculation(self):
        from dev_forge.cache import get_dir_size
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / "a.bin").write_bytes(b"12345")
            (p / "sub").mkdir()
            (p / "sub" / "b.bin").write_bytes(b"67890")
            self.assertEqual(get_dir_size(p), 10)

    def test_version_extraction(self):
        from dev_forge.detector import extract_project_version
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / "Cargo.toml").write_text('[package]\nname = "demo"\nversion = "2.1.3-beta"', encoding="utf-8")
            ver = extract_project_version(p)
            self.assertEqual(ver.raw, "2.1.3-beta")
            self.assertEqual(ver.wix, "2.1.3")

    def test_parse_ssh_config(self):
        from dev_forge.ide import parse_ssh_config
        sample = "Host forge-linux\n  HostName 127.0.0.1\n  User vagrant\n  Port 2200\n  IdentityFile \"/path/to/key\"\n"
        h, p, u, k = parse_ssh_config(sample)
        self.assertEqual(h, "127.0.0.1")
        self.assertEqual(p, "2200")
        self.assertEqual(u, "vagrant")
        self.assertEqual(k, "/path/to/key")

    def test_inject_vscode_profile(self):
        from dev_forge.ide import inject_vscode_profile
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            inject_vscode_profile(p, "rust")
            ext_file = p / ".vscode" / "extensions.json"
            self.assertTrue(ext_file.is_file())
            content = ext_file.read_text(encoding="utf-8")
            self.assertIn("rust-lang.rust-analyzer", content)


    def test_extract_project_name(self):
        from dev_forge.detector import extract_project_name
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / "Cargo.toml").write_text('[package]\nname = "lexishield"\nversion = "2.0.1"', encoding="utf-8")
            self.assertEqual(extract_project_name(p), "lexishield")

        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / "pyproject.toml").write_text('[project]\nname = "hashforge-py"\n', encoding="utf-8")
            self.assertEqual(extract_project_name(p), "hashforge-py")

        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / "package.json").write_text('{"name": "@org/web-app"}', encoding="utf-8")
            self.assertEqual(extract_project_name(p), "web-app")

    def test_menu_prompt_defaults(self):
        from unittest.mock import patch
        from dev_forge.menu import prompt_menu

        class DummyArgs:
            def __init__(self):
                self.project = Path("/dummy/proj")
                self.component = None
                self.target = None
                self.package = None
                self.profile = None
                self.test = False

        args = DummyArgs()
        with patch("builtins.input", return_value=""):
            prompt_menu(args)

        self.assertEqual(args.component, "all")
        self.assertEqual(args.target, "all")
        self.assertEqual(args.package, "all")
        self.assertEqual(args.profile, "release")

    def test_menu_prompt_test_selection(self):
        from unittest.mock import patch
        from dev_forge.menu import prompt_menu

        class DummyArgs:
            def __init__(self):
                self.project = Path("/dummy/proj")
                self.component = None
                self.target = None
                self.package = None
                self.profile = None
                self.test = False

        args = DummyArgs()
        # Option 4 for component (test), 2 for Linux, 2 for bin, 2 for test profile
        with patch("builtins.input", side_effect=["4", "2", "2", "2"]):
            prompt_menu(args)

        self.assertEqual(args.component, "test")
        self.assertTrue(args.test)
        self.assertEqual(args.target, "linux")
        self.assertEqual(args.package, "bin")
        self.assertEqual(args.profile, "test")

    def test_expand_path_and_recents(self):
        from unittest.mock import patch
        from dev_forge.config import expand_path, load_recent_projects, save_recent_project
        self.assertEqual(expand_path("test/rel"), Path("test/rel"))
        home_expanded = expand_path("~")
        self.assertEqual(home_expanded, Path.home())

        with tempfile.TemporaryDirectory() as tmp:
            tmp_cfg = Path(tmp)
            with patch("dev_forge.config.get_user_config_dir", return_value=tmp_cfg):
                p = tmp_cfg / "my_project"
                p.mkdir()
                save_recent_project(p)
                recents = load_recent_projects()
                self.assertTrue(any(r == p.resolve() for r in recents))

    def test_cli_optional_project(self):
        from dev_forge.cli import create_parser
        parser = create_parser()
        args = parser.parse_args(["build"])
        self.assertIsNone(args.project)
        args_with_p = parser.parse_args(["build", "-p", "/some/path"])
        self.assertEqual(args_with_p.project, Path("/some/path"))


    def test_versioned_binary_naming_convention(self):
        from dev_forge.detector import extract_project_version, extract_project_name
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            (p / "Cargo.toml").write_text('[package]\nname = "lexishield"\nversion = "2.0.1"', encoding="utf-8")
            ver = extract_project_version(p)
            app = extract_project_name(p)
            raw = ver.raw
            
            # Canonical and versioned format assertions
            canonical_cli = f"{app}-cli-linux.x86_64"
            versioned_cli = f"{app}-cli-{raw}-linux.x86_64"
            canonical_gui = f"{app}-gui-linux.x86_64"
            versioned_gui = f"{app}-gui-{raw}-linux.x86_64"
            canonical_win_gui = f"{app}-gui-windows.x86_64.exe"
            versioned_win_gui = f"{app}-gui-{raw}-windows.x86_64.exe"

            self.assertEqual(canonical_cli, "lexishield-cli-linux.x86_64")
            self.assertEqual(versioned_cli, "lexishield-cli-2.0.1-linux.x86_64")
            self.assertEqual(canonical_gui, "lexishield-gui-linux.x86_64")
            self.assertEqual(versioned_gui, "lexishield-gui-2.0.1-linux.x86_64")
            self.assertEqual(canonical_win_gui, "lexishield-gui-windows.x86_64.exe")
            self.assertEqual(versioned_win_gui, "lexishield-gui-2.0.1-windows.x86_64.exe")


    def test_forge_dir_isolation_from_client_vagrantfile(self):
        from dev_forge.vagrant import is_dev_forge_root
        with tempfile.TemporaryDirectory() as tmp:
            client_dir = Path(tmp)
            # A client project that happens to have a Vagrantfile
            (client_dir / "Vagrantfile").write_text("# client vagrantfile", encoding="utf-8")
            self.assertFalse(is_dev_forge_root(client_dir))

            # dev-forge has its ansible/linux.yml
            (client_dir / "provision" / "ansible").mkdir(parents=True)
            (client_dir / "provision" / "ansible" / "linux.yml").write_text("# ansible", encoding="utf-8")
            self.assertTrue(is_dev_forge_root(client_dir))

    def test_cli_runner_parser(self):
        from dev_forge.cli import create_parser
        parser = create_parser()

        # runner up
        args = parser.parse_args(["runner", "up", "--provision"])
        self.assertEqual(args.subcommand, "runner")
        self.assertEqual(args.runner_action, "up")
        self.assertTrue(args.provision)

        # runner register
        args = parser.parse_args(["runner", "register", "token-xyz", "https://gitlab.example.com"])
        self.assertEqual(args.runner_action, "register")
        self.assertEqual(args.token, "token-xyz")
        self.assertEqual(args.url, "https://gitlab.example.com")


if __name__ == "__main__":
    unittest.main()
