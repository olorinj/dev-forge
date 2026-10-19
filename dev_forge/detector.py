"""Multi-language project type detector for dev-forge."""

from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Optional


class PythonManager(Enum):
    UV = "uv"
    POETRY = "poetry"
    PIPENV = "pipenv"
    PIP = "pip / requirements.txt"

    def __str__(self) -> str:
        return self.value


@dataclass
class PythonDetails:
    manager: PythonManager
    is_multipython: bool
    matrix_tool: Optional[str] = None


class ProjectTypeKind(Enum):
    RUST_TAURI = "Rust + Tauri (Desktop GUI)"
    RUST = "Rust (Cargo)"
    PYTHON = "Python"
    JAVA = "Java (Gradle / Maven)"
    GO = "Go"
    NODE = "Node.js (JavaScript / TypeScript)"
    CCPP = "C / C++ (CMake / Makefile)"
    GENERIC = "Generic"

    def __str__(self) -> str:
        return self.value


@dataclass
class ProjectType:
    kind: ProjectTypeKind
    python_details: Optional[PythonDetails] = None

    def __str__(self) -> str:
        if self.kind == ProjectTypeKind.PYTHON and self.python_details:
            d = self.python_details
            if d.is_multipython:
                tool = d.matrix_tool or "matrix"
                return f"Python (Manager: {d.manager}, Multi-Python: {tool})"
            return f"Python (Manager: {d.manager})"
        return self.kind.value


def detect_project_type(path: Path) -> ProjectType:
    """Analyze directory structure and manifests to detect project toolchain."""
    # 1. Rust / Tauri
    if (path / "Cargo.toml").is_file():
        if (
            (path / "src-tauri").is_dir()
            or (path / "src-tauri" / "tauri.conf.json").is_file()
            or (path / "tauri.conf.json").is_file()
        ):
            return ProjectType(kind=ProjectTypeKind.RUST_TAURI)
        return ProjectType(kind=ProjectTypeKind.RUST)

    # 2. Java (Gradle / Maven)
    if (
        (path / "build.gradle").is_file()
        or (path / "build.gradle.kts").is_file()
        or (path / "gradlew").is_file()
        or (path / "pom.xml").is_file()
    ):
        return ProjectType(kind=ProjectTypeKind.JAVA)

    # 3. Python
    if is_python_project(path):
        return ProjectType(kind=ProjectTypeKind.PYTHON, python_details=detect_python_details(path))

    # 4. Go
    if (path / "go.mod").is_file():
        return ProjectType(kind=ProjectTypeKind.GO)

    # 5. Node.js
    if (path / "package.json").is_file():
        return ProjectType(kind=ProjectTypeKind.NODE)

    # 6. C / C++
    if (path / "CMakeLists.txt").is_file() or (path / "Makefile").is_file():
        return ProjectType(kind=ProjectTypeKind.CCPP)

    return ProjectType(kind=ProjectTypeKind.GENERIC)


def is_python_project(path: Path) -> bool:
    """Check if the directory has Python manifests or entry points."""
    manifests = [
        "uv.lock",
        "poetry.lock",
        "Pipfile",
        "pyproject.toml",
        "requirements.txt",
        "setup.py",
        "tox.ini",
        "noxfile.py",
        "main.py",
    ]
    return any((path / m).is_file() for m in manifests)


def detect_python_details(path: Path) -> PythonDetails:
    """Detect package manager and multi-python matrix runner."""
    is_multipython = False
    matrix_tool: Optional[str] = None

    if (path / "tox.ini").is_file():
        is_multipython = True
        matrix_tool = "tox"
    elif (path / "noxfile.py").is_file():
        is_multipython = True
        matrix_tool = "nox"
    elif (path / ".python-version").is_file():
        try:
            content = (path / ".python-version").read_text(encoding="utf-8")
            lines = [line.strip() for line in content.splitlines() if line.strip()]
            if len(lines) > 1:
                is_multipython = True
                matrix_tool = f"pyenv ({len(lines)} versions)"
        except Exception:
            pass

    # Manager detection
    if (path / "uv.lock").is_file():
        manager = PythonManager.UV
    elif (path / "poetry.lock").is_file():
        manager = PythonManager.POETRY
    elif (path / "Pipfile").is_file():
        manager = PythonManager.PIPENV
    elif (path / "pyproject.toml").is_file():
        try:
            content = (path / "pyproject.toml").read_text(encoding="utf-8")
            if "[tool.uv]" in content:
                manager = PythonManager.UV
            elif "[tool.poetry]" in content:
                manager = PythonManager.POETRY
            else:
                manager = PythonManager.PIP
        except Exception:
            manager = PythonManager.PIP
    else:
        manager = PythonManager.PIP

    return PythonDetails(manager=manager, is_multipython=is_multipython, matrix_tool=matrix_tool)
