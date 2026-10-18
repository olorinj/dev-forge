use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PythonManager {
    Uv,
    Poetry,
    Pipenv,
    Pip,
}

impl std::fmt::Display for PythonManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Uv => write!(f, "uv"),
            Self::Poetry => write!(f, "poetry"),
            Self::Pipenv => write!(f, "pipenv"),
            Self::Pip => write!(f, "pip / requirements.txt"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PythonDetails {
    pub manager: PythonManager,
    pub is_multipython: bool,
    pub matrix_tool: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ProjectType {
    RustTauri,
    Rust,
    Python(PythonDetails),
    JavaAndroid,
    Java,
    Go,
    Node,
    CCpp,
    Generic,
}

impl std::fmt::Display for ProjectType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::RustTauri => write!(f, "Rust + Tauri (Desktop GUI)"),
            Self::Rust => write!(f, "Rust (Cargo)"),
            Self::Python(details) => {
                if details.is_multipython {
                    write!(
                        f,
                        "Python (Manager: {}, Multi-Python: {})",
                        details.manager,
                        details.matrix_tool.as_deref().unwrap_or("matrix")
                    )
                } else {
                    write!(f, "Python (Manager: {})", details.manager)
                }
            }
            Self::JavaAndroid => write!(f, "Java / Kotlin (Android)"),
            Self::Java => write!(f, "Java (Gradle / Maven)"),
            Self::Go => write!(f, "Go"),
            Self::Node => write!(f, "Node.js (JavaScript / TypeScript)"),
            Self::CCpp => write!(f, "C / C++ (CMake / Makefile)"),
            Self::Generic => write!(f, "Generic"),
        }
    }
}

pub fn detect_project_type(path: &Path) -> ProjectType {
    // 1. Rust / Tauri
    if path.join("Cargo.toml").is_file() {
        if path.join("src-tauri").is_dir()
            || path.join("src-tauri/tauri.conf.json").is_file()
            || path.join("tauri.conf.json").is_file()
        {
            return ProjectType::RustTauri;
        }
        return ProjectType::Rust;
    }

    // 2. Java / Android
    if path.join("build.gradle").is_file()
        || path.join("build.gradle.kts").is_file()
        || path.join("gradlew").is_file()
    {
        let is_android = path.join("app/src/main").is_dir()
            || std::fs::read_to_string(path.join("build.gradle"))
                .map(|s| s.contains("com.android"))
                .unwrap_or(false)
            || std::fs::read_to_string(path.join("build.gradle.kts"))
                .map(|s| s.contains("com.android"))
                .unwrap_or(false);

        if is_android {
            return ProjectType::JavaAndroid;
        }
        return ProjectType::Java;
    }

    if path.join("pom.xml").is_file() {
        return ProjectType::Java;
    }

    // 3. Python (with uv, poetry, pipenv, requirements, multi-python matrix detection)
    if is_python_project(path) {
        return ProjectType::Python(detect_python_details(path));
    }

    // 4. Go
    if path.join("go.mod").is_file() {
        return ProjectType::Go;
    }

    // 5. Node.js
    if path.join("package.json").is_file() {
        return ProjectType::Node;
    }

    // 6. C / C++
    if path.join("CMakeLists.txt").is_file() || path.join("Makefile").is_file() {
        return ProjectType::CCpp;
    }

    ProjectType::Generic
}

fn is_python_project(path: &Path) -> bool {
    path.join("uv.lock").is_file()
        || path.join("poetry.lock").is_file()
        || path.join("Pipfile").is_file()
        || path.join("pyproject.toml").is_file()
        || path.join("requirements.txt").is_file()
        || path.join("setup.py").is_file()
        || path.join("tox.ini").is_file()
        || path.join("noxfile.py").is_file()
        || path.join("main.py").is_file()
}

fn detect_python_details(path: &Path) -> PythonDetails {
    // Multi-python matrix check
    let mut is_multipython = false;
    let mut matrix_tool: Option<String> = None;

    if path.join("tox.ini").is_file() {
        is_multipython = true;
        matrix_tool = Some("tox".to_string());
    } else if path.join("noxfile.py").is_file() {
        is_multipython = true;
        matrix_tool = Some("nox".to_string());
    } else if path.join(".python-version").is_file() {
        if let Ok(content) = std::fs::read_to_string(path.join(".python-version")) {
            let lines: Vec<&str> = content
                .lines()
                .map(|l| l.trim())
                .filter(|l| !l.is_empty())
                .collect();
            if lines.len() > 1 {
                is_multipython = true;
                matrix_tool = Some(format!("pyenv ({} versions)", lines.len()));
            }
        }
    }

    // Manager check
    let manager = if path.join("uv.lock").is_file() {
        PythonManager::Uv
    } else if path.join("poetry.lock").is_file() {
        PythonManager::Poetry
    } else if path.join("Pipfile").is_file() {
        PythonManager::Pipenv
    } else if path.join("pyproject.toml").is_file() {
        let content = std::fs::read_to_string(path.join("pyproject.toml")).unwrap_or_default();
        if content.contains("[tool.uv]") {
            PythonManager::Uv
        } else if content.contains("[tool.poetry]") {
            PythonManager::Poetry
        } else {
            PythonManager::Pip
        }
    } else {
        PythonManager::Pip
    };

    PythonDetails {
        manager,
        is_multipython,
        matrix_tool,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn test_detect_rust_and_tauri() {
        let tmp = tempfile::tempdir().unwrap();
        fs::write(tmp.path().join("Cargo.toml"), "[package]\nname = \"demo\"").unwrap();
        assert_eq!(detect_project_type(tmp.path()), ProjectType::Rust);

        fs::create_dir_all(tmp.path().join("src-tauri")).unwrap();
        assert_eq!(detect_project_type(tmp.path()), ProjectType::RustTauri);
    }

    #[test]
    fn test_detect_python_uv() {
        let tmp = tempfile::tempdir().unwrap();
        fs::write(tmp.path().join("uv.lock"), "# uv lockfile").unwrap();
        let pt = detect_project_type(tmp.path());
        match pt {
            ProjectType::Python(d) => {
                assert_eq!(d.manager, PythonManager::Uv);
                assert!(!d.is_multipython);
            }
            _ => panic!("Expected Python project"),
        }
    }

    #[test]
    fn test_detect_python_poetry() {
        let tmp = tempfile::tempdir().unwrap();
        fs::write(tmp.path().join("poetry.lock"), "# poetry lockfile").unwrap();
        let pt = detect_project_type(tmp.path());
        match pt {
            ProjectType::Python(d) => {
                assert_eq!(d.manager, PythonManager::Poetry);
            }
            _ => panic!("Expected Python project"),
        }
    }

    #[test]
    fn test_detect_python_multipython_tox() {
        let tmp = tempfile::tempdir().unwrap();
        fs::write(tmp.path().join("requirements.txt"), "pytest").unwrap();
        fs::write(
            tmp.path().join("tox.ini"),
            "[tox]\nenvlist = py310,py311,py312",
        )
        .unwrap();
        let pt = detect_project_type(tmp.path());
        match pt {
            ProjectType::Python(d) => {
                assert_eq!(d.manager, PythonManager::Pip);
                assert!(d.is_multipython);
                assert_eq!(d.matrix_tool.as_deref(), Some("tox"));
            }
            _ => panic!("Expected Python project"),
        }
    }
}
