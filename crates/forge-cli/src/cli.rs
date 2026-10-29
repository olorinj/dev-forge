use clap::{Args, Parser, Subcommand, ValueEnum};
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(
    name = "dev-forge",
    author = "dev-forge team",
    version = "0.1.0",
    about = "Universal multi-language headless build forge orchestrator",
    long_about = "A high-performance, 100% offline multi-toolchain compilation and virtualization orchestrator."
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Commands,
}

#[derive(Subcommand, Debug)]
pub enum Commands {
    /// Detect host hardware resources and dimension optimal VM parameters
    Tune,

    /// Show current status of forge virtual machines
    Status,

    /// Boot virtual machines in headless mode
    Up {
        /// Specific VM to boot (forge-linux | forge-windows)
        #[arg(default_value = "forge-linux")]
        machine: String,

        /// Force re-provisioning on boot
        #[arg(long)]
        provision: bool,
    },

    /// Gracefully stop virtual machines to release host memory
    Halt {
        /// Specific VM to stop (forge-linux | forge-windows)
        machine: Option<String>,

        /// Force immediate shutdown
        #[arg(short, long)]
        force: bool,
    },

    /// Re-provision build tools and packages inside the virtual machines
    Provision {
        /// Specific VM to provision (forge-linux | forge-windows)
        machine: Option<String>,
    },

    /// Open an interactive shell or execute a remote command inside the Linux VM
    Ssh {
        /// Specific VM (default: forge-linux)
        #[arg(default_value = "forge-linux")]
        machine: String,

        /// Specific command to execute non-interactively
        #[arg(short, long)]
        command: Option<String>,
    },

    /// Compile a target client project inside the isolated VM build environment
    Build(BuildArgs),

    /// Run the in-VM health-check and HashForge multi-language verification suite
    TestVm {
        /// Specific VM to verify (default: forge-linux)
        #[arg(default_value = "forge-linux")]
        machine: String,
    },

    /// Diagnose host virtualization, hypervisors, ports and environment health
    Doctor,

    /// Clean persistent host compiler cache (~/.dev-forge/cache)
    CleanCache {
        /// Specific subsystem cache to clean (cargo | go | pip | gradle | sccache)
        #[arg(short, long)]
        subsystem: Option<String>,
    },

    /// Open VS Code Remote-SSH session inside VM with development profile
    Ide(IdeArgs),

    /// Install dev-forge binary into ~/.local/bin for global execution
    InstallBin,

    /// Manage the isolated CI/CD runner VM (forge-runner) and pipeline verification
    Runner(RunnerArgs),

    /// Manage, package and install pre-baked VirtualBox custom boxes (VDI format)
    Box {
        #[command(subcommand)]
        action: BoxAction,
    },

    /// Generate native shell completion scripts
    Completions {
        /// Shell type
        #[arg(value_enum)]
        shell: clap_complete::Shell,
    },
}

#[derive(Args, Debug, Clone)]
pub struct BuildArgs {
    /// Path to the client project to compile (optional, defaults to current directory or recent selector)
    #[arg(short, long)]
    pub project: Option<PathBuf>,

    /// Target destination platform (linux | windows | macos | all)
    #[arg(short, long)]
    pub target: Option<TargetPlatform>,

    /// Component to build (all | cli | gui | test)
    #[arg(long, value_enum)]
    pub component: Option<BuildComponent>,

    /// Packaging format (all | bin | bundle)
    #[arg(long, value_enum)]
    pub package: Option<BuildPackage>,

    /// Build profile (release | test | debug)
    #[arg(long, value_enum)]
    pub profile: Option<BuildProfile>,

    /// Build only testing executables / test runners
    #[arg(long)]
    pub test: bool,

    /// Force interactive terminal selection menu
    #[arg(short, long)]
    pub interactive: bool,

    /// Clean intermediate caches before compilation
    #[arg(short, long)]
    pub clean: bool,

    /// Keep virtual machines running after compilation finishes
    #[arg(short, long)]
    pub keep_vm: bool,

    /// Force re-provisioning of packages in the VM prior to building
    #[arg(short, long)]
    pub update: bool,

    /// Compiler to use for Python standalone binaries (nuitka | pyinstaller)
    #[arg(long, value_enum, default_value = "nuitka")]
    pub compiler: PythonCompiler,

    /// Convenience flag to force PyInstaller for Python builds
    #[arg(long)]
    pub pyinstaller: bool,
}

#[derive(ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum BuildComponent {
    All,
    Cli,
    Gui,
    Test,
}

impl std::fmt::Display for BuildComponent {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::All => write!(f, "all"),
            Self::Cli => write!(f, "cli"),
            Self::Gui => write!(f, "gui"),
            Self::Test => write!(f, "test"),
        }
    }
}

#[derive(ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum BuildPackage {
    All,
    Bin,
    Bundle,
    Single,
}

impl std::fmt::Display for BuildPackage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::All => write!(f, "all"),
            Self::Bin => write!(f, "bin"),
            Self::Bundle => write!(f, "bundle"),
            Self::Single => write!(f, "single"),
        }
    }
}

#[derive(ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum BuildProfile {
    Release,
    Debug,
    Test,
}

impl std::fmt::Display for BuildProfile {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Release => write!(f, "release"),
            Self::Debug => write!(f, "debug"),
            Self::Test => write!(f, "test"),
        }
    }
}

#[derive(ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum PythonCompiler {
    Nuitka,
    Pyinstaller,
}

impl std::fmt::Display for PythonCompiler {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Nuitka => write!(f, "nuitka"),
            Self::Pyinstaller => write!(f, "pyinstaller"),
        }
    }
}

#[derive(Args, Debug)]
pub struct IdeArgs {
    /// Specific VM to connect to (default: forge-linux)
    #[arg(default_value = "forge-linux")]
    pub machine: String,

    /// Programming profile with pre-configured extensions and settings (rust | python | cpp | web | full)
    #[arg(short, long, value_enum, default_value = "full")]
    pub profile: IdeProfile,

    /// Path to workspace directory on host to bind (default: current directory)
    #[arg(short = 'w', long, alias = "workspace")]
    pub project: Option<PathBuf>,

    /// Configure SSH and environment without launching VS Code UI
    #[arg(long)]
    pub no_launch: bool,
}

#[derive(Args, Debug, Clone)]
pub struct RunnerArgs {
    #[command(subcommand)]
    pub action: RunnerAction,
}

#[derive(Subcommand, Debug, Clone)]
pub enum RunnerAction {
    /// Boot the isolated CI/CD runner VM
    Up {
        /// Force re-provisioning on boot
        #[arg(long)]
        provision: bool,
    },
    /// Stop the runner VM
    Halt {
        /// Force immediate shutdown
        #[arg(short, long)]
        force: bool,
    },
    /// Show runner VM status
    Status,
    /// Open SSH shell into runner VM
    Ssh {
        /// Command to execute non-interactively
        #[arg(short, long)]
        command: Option<String>,
    },
    /// Register runner node to a remote GitLab instance
    Register {
        /// Runner registration token
        token: String,
        /// GitLab URL (default: https://gitlab.com)
        #[arg(default_value = "https://gitlab.com")]
        url: String,
    },
    /// Launch offline local GitLab CE container inside runner for air-gapped CI
    StartGitlab,
}

#[derive(Subcommand, Debug, Clone)]
pub enum BoxAction {
    /// Rebuild a base machine from upstream with full provisioning, hardening, packaging and verification
    Rebuild {
        /// Target machine to rebuild: 'forge-linux', 'forge-windows', 'forge-runner', or 'all'
        #[arg(default_value = "all")]
        machine: String,

        /// Semantic version tag for the rebuilt box
        #[arg(short, long, default_value = "1.0.0")]
        version: String,

        /// Rebuild stage execution mode: 'all', 'deploy-only', or 'package-only'
        #[arg(short, long, default_value = "all")]
        stage: String,

        /// Skip clean boot verification test after packaging
        #[arg(long, default_value_t = false)]
        skip_test: bool,

        /// Custom output directory for the .box file (defaults to partition with most space)
        #[arg(short, long)]
        out_dir: Option<PathBuf>,
    },

    /// Publish packaged box artifacts to Vagrant Cloud (app.vagrantup.com)
    Publish {
        /// Target box to publish: 'linux', 'windows', 'runner', or 'all'
        #[arg(default_value = "all")]
        machine: String,

        /// Version to publish to Vagrant Cloud
        #[arg(short, long, default_value = "1.0.0")]
        version: String,

        /// Target user or organization in Vagrant Cloud (reads from DEVFORGE_BOX_ORG or VAGRANT_CLOUD_USER if omitted)
        #[arg(short, long, alias = "org")]
        user: Option<String>,

        /// Dry-run mode: validate files, hashes and tokens without uploading
        #[arg(short = 'n', long, default_value_t = false)]
        dry_run: bool,

        /// Publish as active release (default true; if false, creates as draft)
        #[arg(long, default_value_t = true)]
        release: bool,

        /// Non-interactive confirmation (auto-yes for CI/CD and autonomous agents)
        #[arg(short, long, default_value_t = false)]
        yes: bool,

        /// Custom catalog description for the box
        #[arg(short, long)]
        description: Option<String>,

        /// Directory containing .box and .sha256 artifacts to publish
        #[arg(long, default_value = "dist/boxes")]
        box_dir: PathBuf,
    },

    /// Package a virtual machine into an optimized pre-baked VDI box
    Package {
        /// Target machine to package: 'forge-linux', 'forge-windows', 'forge-runner', or 'all'
        #[arg(default_value = "forge-linux")]
        machine: String,

        /// Version tag for the packaged box (e.g. 1.0.0)
        #[arg(short, long, default_value = "1.0.0")]
        version: String,

        /// Custom output directory for the .box file (defaults to partition with most space)
        #[arg(short, long)]
        out_dir: Option<PathBuf>,
    },

    /// Register/install a locally generated box into Vagrant for instant usage
    Install {
        /// Target machine name: 'forge-linux', 'forge-windows', or 'forge-runner'
        #[arg(default_value = "forge-linux")]
        machine: String,

        /// Optional version tag of the box to install (if omitted, installs the latest found)
        #[arg(short, long)]
        version: Option<String>,

        /// Custom path to the .box file (if omitted, searches in ~/.dev-forge/boxes or dist/boxes)
        #[arg(short, long)]
        box_file: Option<PathBuf>,
    },

    /// List all dev-forge boxes installed locally in Vagrant
    List,
}

#[derive(ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum IdeProfile {
    Rust,
    Python,
    Cpp,
    Web,
    Full,
}

impl std::fmt::Display for IdeProfile {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Rust => write!(f, "rust"),
            Self::Python => write!(f, "python"),
            Self::Cpp => write!(f, "cpp"),
            Self::Web => write!(f, "web"),
            Self::Full => write!(f, "full"),
        }
    }
}

#[derive(ValueEnum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum TargetPlatform {
    Linux,
    Windows,
    Macos,
    All,
}

impl std::fmt::Display for TargetPlatform {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Linux => write!(f, "linux"),
            Self::Windows => write!(f, "windows"),
            Self::Macos => write!(f, "macos"),
            Self::All => write!(f, "all"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_build_interactive_trigger() {
        let cli = Cli::try_parse_from(["dev-forge", "build", "-p", "/tmp/proj"]).unwrap();
        if let Commands::Build(args) = cli.command {
            assert!(args.target.is_none());
            assert!(args.component.is_none());
            assert!(args.package.is_none());
            assert!(!args.test);
            assert!(!args.interactive);
        } else {
            panic!("Expected Commands::Build");
        }
    }

    #[test]
    fn test_parse_build_flags() {
        let cli = Cli::try_parse_from([
            "dev-forge",
            "build",
            "-p",
            "/tmp/proj",
            "-t",
            "linux",
            "--component",
            "test",
            "--package",
            "bin",
            "--test",
        ])
        .unwrap();

        if let Commands::Build(args) = cli.command {
            assert_eq!(args.target, Some(TargetPlatform::Linux));
            assert_eq!(args.component, Some(BuildComponent::Test));
            assert_eq!(args.package, Some(BuildPackage::Bin));
            assert!(args.test);
        } else {
            panic!("Expected Commands::Build");
        }
    }

    #[test]
    fn test_enum_displays() {
        assert_eq!(BuildComponent::All.to_string(), "all");
        assert_eq!(BuildComponent::Cli.to_string(), "cli");
        assert_eq!(BuildComponent::Gui.to_string(), "gui");
        assert_eq!(BuildComponent::Test.to_string(), "test");

        assert_eq!(BuildPackage::All.to_string(), "all");
        assert_eq!(BuildPackage::Bin.to_string(), "bin");
        assert_eq!(BuildPackage::Bundle.to_string(), "bundle");

        assert_eq!(BuildProfile::Release.to_string(), "release");
        assert_eq!(BuildProfile::Test.to_string(), "test");
    }
}
