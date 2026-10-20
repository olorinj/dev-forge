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

    // 2. Java (Gradle / Maven)
    if path.join("build.gradle").is_file()
        || path.join("build.gradle.kts").is_file()
        || path.join("gradlew").is_file()
        || path.join("pom.xml").is_file()
    {
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProjectVersionInfo {
    pub raw: String,
    pub display: String,
    pub wix: String,
    pub branch: String,
    pub commit: String,
}

pub fn extract_project_version(path: &Path) -> ProjectVersionInfo {
    let mut raw_version = None;

    // 1. Cargo.toml
    let cargo_path = path.join("Cargo.toml");
    if cargo_path.is_file() {
        if let Ok(content) = std::fs::read_to_string(&cargo_path) {
            let mut in_package = false;
            for line in content.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with('[') && trimmed.ends_with(']') {
                    in_package = trimmed == "[package]";
                } else if in_package && trimmed.starts_with("version") {
                    if let Some(val) = extract_quoted_value(trimmed) {
                        raw_version = Some(val);
                        break;
                    }
                }
            }
        }
    }

    // 2. pyproject.toml
    if raw_version.is_none() {
        let pyproject_path = path.join("pyproject.toml");
        if pyproject_path.is_file() {
            if let Ok(content) = std::fs::read_to_string(&pyproject_path) {
                for line in content.lines() {
                    let trimmed = line.trim();
                    if trimmed.starts_with("version") {
                        if let Some(val) = extract_quoted_value(trimmed) {
                            raw_version = Some(val);
                            break;
                        }
                    }
                }
            }
        }
    }

    // 3. package.json
    if raw_version.is_none() {
        let pkg_path = path.join("package.json");
        if pkg_path.is_file() {
            if let Ok(content) = std::fs::read_to_string(&pkg_path) {
                for line in content.lines() {
                    let trimmed = line.trim();
                    if trimmed.starts_with("\"version\"") {
                        if let Some(val) = extract_quoted_value(trimmed) {
                            raw_version = Some(val);
                            break;
                        }
                    }
                }
            }
        }
    }

    // 4. CMakeLists.txt
    if raw_version.is_none() {
        let cmake_path = path.join("CMakeLists.txt");
        if cmake_path.is_file() {
            if let Ok(content) = std::fs::read_to_string(&cmake_path) {
                for line in content.lines() {
                    if line.contains("VERSION") && line.contains("project(") {
                        if let Some(idx) = line.find("VERSION") {
                            let rest = line[idx + 7..].trim_start();
                            let ver: String = rest
                                .chars()
                                .take_while(|c| c.is_ascii_digit() || *c == '.')
                                .collect();
                            if !ver.is_empty() {
                                raw_version = Some(ver);
                                break;
                            }
                        }
                    }
                }
            }
        }
    }

    let raw = raw_version.unwrap_or_else(|| "0.1.0".to_string());

    let (branch, commit) = extract_git_info(path);

    let safe_branch = branch.replace(['/', '\\', ':', '*', '?', '"', '<', '>', '|'], "-");
    let display = if !safe_branch.is_empty() && safe_branch != "HEAD" {
        format!("{}-{}", raw, safe_branch)
    } else {
        raw.clone()
    };

    let wix = sanitize_wix_version(&raw);

    ProjectVersionInfo {
        raw,
        display,
        wix,
        branch,
        commit,
    }
}

fn extract_quoted_value(line: &str) -> Option<String> {
    let parts: Vec<&str> = line.split('"').collect();
    if parts.len() >= 3 {
        return Some(parts[1].to_string());
    }
    let parts_sq: Vec<&str> = line.split('\'').collect();
    if parts_sq.len() >= 3 {
        return Some(parts_sq[1].to_string());
    }
    None
}

fn extract_git_info(path: &Path) -> (String, String) {
    let mut branch = String::new();
    let mut commit = String::new();

    if let Ok(out) = std::process::Command::new("git")
        .args([
            "-C",
            &path.to_string_lossy(),
            "rev-parse",
            "--abbrev-ref",
            "HEAD",
        ])
        .output()
    {
        if out.status.success() {
            let b = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !b.is_empty() && b != "HEAD" {
                branch = b;
            }
        }
    }

    if let Ok(out) = std::process::Command::new("git")
        .args([
            "-C",
            &path.to_string_lossy(),
            "rev-parse",
            "--short",
            "HEAD",
        ])
        .output()
    {
        if out.status.success() {
            commit = String::from_utf8_lossy(&out.stdout).trim().to_string();
        }
    }

    (branch, commit)
}

fn sanitize_wix_version(raw: &str) -> String {
    let clean = raw.split('-').next().unwrap_or(raw);
    let parts: Vec<&str> = clean.split('.').collect();
    let mut nums = Vec::new();
    for part in parts {
        let digits: String = part.chars().take_while(|c| c.is_ascii_digit()).collect();
        if !digits.is_empty() {
            nums.push(digits);
        } else {
            break;
        }
    }

    while nums.len() < 3 {
        nums.push("0".to_string());
    }

    format!("{}.{}.{}", nums[0], nums[1], nums[2])
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

    #[test]
    fn test_extract_project_version_cargo() {
        let tmp = tempfile::tempdir().unwrap();
        fs::write(
            tmp.path().join("Cargo.toml"),
            "[package]\nname = \"demo\"\nversion = \"1.2.3-rc1\"\n",
        )
        .unwrap();
        let ver = extract_project_version(tmp.path());
        assert_eq!(ver.raw, "1.2.3-rc1");
        assert_eq!(ver.wix, "1.2.3");
    }

    #[test]
    fn test_extract_project_version_pyproject() {
        let tmp = tempfile::tempdir().unwrap();
        fs::write(
            tmp.path().join("pyproject.toml"),
            "[project]\nname = \"demo-py\"\nversion = \"0.4.2\"\n",
        )
        .unwrap();
        let ver = extract_project_version(tmp.path());
        assert_eq!(ver.raw, "0.4.2");
        assert_eq!(ver.wix, "0.4.2");
    }

    #[test]
    fn test_sanitize_wix_version() {
        assert_eq!(sanitize_wix_version("1.2.3"), "1.2.3");
        assert_eq!(sanitize_wix_version("2.0.0-beta.1"), "2.0.0");
        assert_eq!(sanitize_wix_version("42"), "42.0.0");
        assert_eq!(sanitize_wix_version("0.1"), "0.1.0");
    }
}
