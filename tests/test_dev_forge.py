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


if __name__ == "__main__":
    unittest.main()
