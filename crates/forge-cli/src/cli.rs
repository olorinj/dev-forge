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

    /// Generate native shell completion scripts
    Completions {
        /// Shell type
        #[arg(value_enum)]
        shell: clap_complete::Shell,
    },
}

#[derive(Args, Debug)]
pub struct BuildArgs {
    /// Path to the client project to compile (mandatory)
    #[arg(short, long)]
    pub project: PathBuf,

    /// Target destination platform
    #[arg(short, long, default_value = "all")]
    pub target: TargetPlatform,

    /// Clean intermediate caches before compilation
    #[arg(short, long)]
    pub clean: bool,

    /// Keep virtual machines running after compilation finishes
    #[arg(short, long)]
    pub keep_vm: bool,

    /// Force re-provisioning of packages in the VM prior to building
    #[arg(short, long)]
    pub update: bool,
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
